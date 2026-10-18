#!/usr/bin/env python3
"""Catch accidental local files and common credential patterns before publication.
This focused check supplements a full secret scanner; it is not a secrecy guarantee.
Only filenames and rule names are printed, never matching values.
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
private_dirs = {'.build', 'dist', '.codex', '.claude', '.cursor', '.grok', '.deepseek-chan', '.mcp-auth'}
private_suffixes = {'.pem', '.key', '.p12', '.p8', '.keychain', '.mobileprovision', '.dmg', '.log', '.exe', '.pdb', '.asar', '.map'}
patterns = {
    'personal home path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'provider credential': re.compile(rb'(?:sk-or-v1-[a-f0-9]{32,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
}
failures = []
# Email metadata is public even when the source tree itself contains no address.
for row in subprocess.check_output(['git', 'log', '--all', '--format=%h%x00%ae%x00%ce'], cwd=root).decode().splitlines():
    commit, author, committer = row.split('\0')
    if any(not email.endswith('@users.noreply.github.com') and email != 'noreply@github.com' for email in (author, committer)):
        failures.append(('commit ' + commit, 'non-private author/committer email'))
for row in subprocess.check_output(['git', 'for-each-ref', 'refs/tags', '--format=%(refname:short)%00%(taggeremail:trim)'], cwd=root).decode().splitlines():
    tag, email = row.split('\0')
    if email and not email.endswith('@users.noreply.github.com') and email != 'noreply@github.com':
        failures.append(('tag ' + tag, 'non-private tagger email'))
for name in filter(None, files):
    path = Path(name)
    if private_dirs.intersection(path.parts) or path.suffix in private_suffixes or path.name.startswith('.env'):
        failures.append((name, 'private/generated file'))
    full = root / path
    if full.is_symlink():
        failures.append((name, 'unreviewed symlink'))
        continue
    if not full.is_file():
        continue
    data = full.read_bytes()
    # Scan text source; generated artwork and native icons are reviewed separately.
    if b'\x00' in data[:8192]:
        continue
    for rule, pattern in patterns.items():
        if pattern.search(data):
            failures.append((name, rule))
for name, rule in failures:
    print(f'{name}: {rule}', file=sys.stderr)
if failures:
    sys.exit(1)
print('PASS: public file inventory and credential/path checks')
