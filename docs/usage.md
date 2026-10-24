# Coding Plan usage

Cute chatter stays above the pet. A separate bubble **below** her shows remaining subscription quota as progress bars. Clicking her still gives a head pat and a cute reply. **Details ›** opens every quota window and reset date. The compact bar names the most constrained returned window. Missing accounts show a connection state, never a zero bar.

| Provider | What is displayed | Connection |
| --- | --- | --- |
| Codex | Session and weekly quota, when returned | Local Codex `auth.json` under `CODEX_HOME` or `~/.codex` |
| Claude | Five-hour, weekly and returned model-specific windows | Claude Code credentials file; macOS also reads its default Keychain entry |
| Grok | Weekly quota, or the returned monthly limit | Grok Build `auth.json` under `GROK_HOME` or `~/.grok` |
| Cursor | Cursor Models, Other Models and monthly quota when available | Cursor CLI sign-in or the desktop client's read-only state database; macOS also supports its token Keychain entry |
| OpenCode | Go subscription: five-hour, weekly and monthly remaining quota | Local OpenCode Console sign-in, or an optional Go key in **Connect OpenCode Go** |

DeepSeek and OpenRouter API balance cards and their connection controls have been removed. Their old locally stored keys are no longer read by the quota service; the app does not erase unrelated client credentials.

## OpenCode

The pet reads the active OpenCode credential from `~/.local/share/opencode/opencode.db` (or the inherited `XDG_DATA_HOME/opencode` location). Reads are limited to the `opencode-go` and `opencode` credential records. It supports Go keys and default OpenCode Console OAuth credentials, including the workspace headers required by the usage endpoint. It never reads session messages or displays account metadata. Inactive v2 records do not fall back to an old v1 login.

For v1 installations without a v2 OpenCode credential, `auth.json` in the same directory is supported. Only the `opencode-go` or `opencode` entry is eligible; credentials for other providers are not reused. Self-hosted Console credentials are rejected. Sign-in renewal stays with OpenCode; the pet never refreshes or rewrites its OAuth credentials.

An optional manually saved Go key takes precedence over local discovery. **Remove key** removes only that override; the next refresh can use the local sign-in again. This is a subscription quota query, not a Zen credit-balance query. No plan or unsupported window is inferred from an empty response.

References: [OpenCode Go](https://opencode.ai/v2/docs/console/go/), [current Go usage endpoint](https://github.com/anomalyco/opencode/issues/52227), [OpenCode credential store](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/credential/sql.ts), [Console OAuth metadata](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/provider/opencode.ts).

## Other clients and freshness

On Windows, Claude's file is normally `%USERPROFILE%\.claude\.credentials.json`; Cursor CLI state is under `%APPDATA%\Cursor` and desktop state under `%APPDATA%\Cursor\User\globalStorage`. On Mac, Cursor CLI state is under `~/.cursor`; desktop state is under `~/Library/Application Support/Cursor`. Environment overrides must be inherited by the app process.

Sign in using the provider's own app/CLI, then press **Refresh**. This reads the default local account; it does not import Orca profiles. Some client Keychain items can be inaccessible to another Mac app.

Launching the pet starts a read-only refresh, followed by a refresh every five minutes. Manual refresh is throttled to once per 30 seconds. Provider 429 responses back off. Account changes clear previous-account values. Failed refreshes may retain clearly marked **Last known** values for the same credential; missing credentials clear them. A zero remainder appears only when reported by the provider.

The lower bubble updates independently of stories and touch reactions. Eye-break controls temporarily take priority. Grey bars and `old` labels identify last-known data. Endpoints can change independently of the app; unavailable data is not proof of unlimited quota.

## Privacy and verification

Requests use five fixed HTTPS usage endpoints, reject redirects, and are bounded in size and time. No AI generation is performed. No raw provider error, email, name, account ID or credential is displayed or logged. Snapshots stay in memory. Credential fingerprints isolate accounts and stay inside the service. Optional Go keys use macOS Keychain or Windows account encryption. Existing client credentials are never deleted by the pet.

Tests cover five response formats, missing versus zero quota, error/backoff behavior, reset dates, in-flight account changes, scoped OpenCode credential discovery, inactive records, custom-host rejection and renderer isolation. The native Mac parser uses the same normalization source through JavaScriptCore. Electron UI tests use synthetic responses; live provider availability remains account-specific.
