#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
APP="$ROOT/dist/release/DeepSeek-chan.app"
[[ -d "$APP" ]] || { print -u2 'Run scripts/package-release.sh first.'; exit 2; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DEST=${1:-"$HOME/Desktop/DeepSeek-chan-${VERSION}-arm64.dmg"}
[[ ! -e "$DEST" ]] || { print -u2 "Already exists: $DEST"; exit 2; }
STAGE=$(mktemp -d "$ROOT/.build/dmg-stage.XXXXXX")
ditto "$APP" "$STAGE/DeepSeek-chan.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TXT'
DeepSeek-chan

Drag DeepSeek-chan.app to Applications, then open it from Applications.
Requires Apple Silicon and macOS 26 or later.

Halloween wardrobe: select Outfit > Halloween in the main window.
285 illustrated poses, little stories, and five-minute eye breaks.

This personal release is ad-hoc signed, not Apple-notarized. macOS may
require explicit approval before first launch on another computer.

Open Coding Plan to view Codex, Claude, Grok, Cursor and OpenCode quotas.
OpenCode Go uses your local sign-in or an optional Go key for subscription quota.
The package contains no API keys, account details or personal preferences.
Fan-made; not affiliated with DeepSeek.
TXT
codesign --verify --deep --strict "$STAGE/DeepSeek-chan.app"
hdiutil create -volname "DeepSeek-chan $VERSION" -srcfolder "$STAGE" -format UDZO -fs HFS+ "$DEST"
hdiutil verify "$DEST"
(cd "${DEST:A:h}" && shasum -a 256 "${DEST:t}") > "${DEST}.sha256"
printf 'DMG: %s\n' "$DEST"
