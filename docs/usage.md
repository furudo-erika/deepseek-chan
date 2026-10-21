# Coding Plan usage

The pet keeps her cute chatter in the speech bubble above her. A separate bubble **below** her shows remaining quota as progress bars, so both are visible together. Clicking the pet still gives her a head pat and a cute reply. **Details ›** opens all quota windows, reset dates and API-key connections. The compact bar uses the most constrained returned window for each provider, named below the bar. API credit balances show currency amounts because the provider does not supply a percentage budget. Missing accounts show a connection state, never a zero bar.

| Provider | What is displayed | Connection |
| --- | --- | --- |
| Codex | Session and weekly quota, when the account returns them | Local Codex `auth.json` under `CODEX_HOME` or `~/.codex` |
| Claude | Five-hour, weekly and returned model-specific windows | Claude Code credentials file; macOS also reads the default Claude Code Keychain entry |
| Grok | Weekly quota, or the returned monthly limit | Grok Build `auth.json` under `GROK_HOME` or `~/.grok` |
| Cursor | Cursor Models, Other Models and monthly quota when available | Cursor CLI sign-in or the desktop client's read-only local state database; macOS also supports the Cursor token Keychain entry |
| DeepSeek | Available API balance in the returned currency | **Connect API balance → DeepSeek**, then save your API key |
| OpenRouter | API credits minus usage, in USD | **Connect API balance → OpenRouter**, then save a key with access to the credits endpoint |

DeepSeek and OpenRouter rows are **API balances**, not inferred coding-subscription allowances. If a provider does not return a supported window, the app does not invent it. Multiple currencies are not added together. Negative API credit balances remain visible.

On Windows, Claude's file is normally `%USERPROFILE%\.claude\.credentials.json`, Cursor's CLI state is under `%APPDATA%\Cursor`, and its desktop state is under `%APPDATA%\Cursor\User\globalStorage`. Mac Cursor CLI state is under `~/.cursor`; desktop state is under `~/Library/Application Support/Cursor`. The app never reads browser cookies, chat transcripts or arbitrary project files. Environment overrides must be inherited by the app process.

For the four coding clients, sign in using the provider's own app/CLI, then press **Refresh**. This release reads the default local account; it does not import Orca's private multi-account profiles. On Mac, a client Keychain item can be inaccessible to another app. The panel will show the connection instruction if no usable credential is available. Sign-in renewal belongs to the original client; the pet never refreshes or rewrites its OAuth credentials.

The lower quota bubble updates independently of her normal stories and touch reactions. Eye-break controls temporarily take priority. Grey bars and `old` labels identify last-known data after a refresh failure.

## Freshness and errors

Launching the pet starts a read-only refresh, followed by a refresh every five minutes. Manual refresh is throttled to once per 30 seconds. Provider 429 responses back off, and sign-in changes invalidate the previous account's values. A failed refresh may retain clearly marked **Last known** values for the same credential. Missing credentials clear the values. A zero remainder is only shown if the provider actually reports it.

These account-usage endpoints can change independently of the app. Authentication errors, denied access, unsupported payloads, network errors and missing windows remain visible states; a blank or unavailable window is not proof of an unlimited plan.

## Privacy

Requests use only six fixed HTTPS provider endpoints with redirects rejected. No AI generation is performed. Requests and responses are size/time bounded. No raw provider error, email, name, account ID or credential is displayed or logged. Usage snapshots stay in memory. Internal credential fingerprints isolate accounts and never leave the service.

Manually entered API keys use macOS Keychain or Windows DPAPI via Electron safeStorage. An existing OpenRouter key from the old chat feature can be reused for a balance query. **Remove key** clears both that legacy key and the new OpenRouter usage key. Credentials already owned by Codex, Claude, Grok or Cursor are never deleted by the pet. No credential or personal setting is included in published packages. Other software running as the same OS user is outside the encryption boundary.

## Verification

Tests cover the six response formats, missing versus zero quota, error/backoff behavior, overage, reset timestamps, account changes during requests, key removal, and renderer isolation. Windows CI launches both the packaged and installed app against synthetic provider responses, and installs/uninstalls the EXE. The native Mac parser uses the exact same normalization source through JavaScriptCore. This is not hands-on testing on every user's Windows PC or a live verification of every API-key account.

Protocol references: [DeepSeek balance](https://api-docs.deepseek.com/api/get-user-balance/), [OpenRouter credits](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits), [Grok client network hosts](https://docs.x.ai/build/enterprise). The coding-client quota endpoints are client integrations rather than a promise of stable public APIs.
