# DeepSeek-chan for Windows

The first Windows desktop release is **1.9.0**. It shares the original 279 illustrated poses with the native Mac app and runs in a small, transparent Electron window.

## Install

Download **DeepSeek-chan-1.9.0-windows-x64-setup.exe** and its `.sha256` file from [Releases](https://github.com/furudo-erika/deepseek-chan/releases). Run the installer for your own Windows account, then open **DeepSeek-chan** from Start or the desktop shortcut. No administrator access, Python, Node.js or AI account is required to use the pet. Requires Windows 10/11, x64; ARM64 and 32-bit Windows are not published targets.

The installer is **unsigned**. Windows may show an unknown-publisher/SmartScreen prompt. Verify that the download came from this repository and compare its checksum; do not disable Windows protections globally. The macOS DMG remains a separate native application.

In PowerShell, compare the hash to the downloaded checksum file:

```powershell
Get-FileHash .\DeepSeek-chan-1.9.0-windows-x64-setup.exe -Algorithm SHA256
Get-Content .\DeepSeek-chan-1.9.0-windows-x64-setup.exe.sha256
```

## What she can do

- Drag her to a corner; click her for a head pat. Right-click for settings.
- Mouse movement starts a focus cycle. At the deadline she moves to the active display's center and dances, with **Rest 5 min** and **In 5 min** buttons. An open panel cannot hide these buttons, and an unsent chat draft is preserved.
- Browse all 279 poses, switch between Classic and Halloween, chat, dance, and receive short multilingual stories every 2–3 minutes. She waits while you type; Calm motion and the system's reduced-motion preference soften movement.
- Close a panel to return to the pet. **Hide to tray** hides her without quitting; use her system-tray icon to restore or quit.
- Use local replies without an account. Optional OpenRouter replies require your own key. The Windows key is encrypted with the signed-in Windows account's DPAPI protection; other applications running as that same user are outside this protection boundary. No chat transcripts are saved. Only explicit submitted chat messages are sent to OpenRouter; task states are never sent.

This first port has its own compact controls. It does not yet include Mac favorites or every contextual conversation routine. Linux is still planned.

## Task buddies

The Windows app reads the same bounded local snapshot protocol as the Mac app from `%USERPROFILE%\.deepseek-chan\tasks`. Current task status appears under **Tasks**. Working, waiting, completed, failed, cancelled and idle states have different reactions. Old events do not replay at launch; active states without updates become stale after five minutes.

**Tasks → Copy MCP config** copies a configuration using the installed app's real connector path. Merge that entry into your client's existing MCP configuration. It uses `py -3`, so install Python 3.9+ with its Windows launcher if you want coding-tool integrations. Change `--source codex` to `claude`, `cursor`, `pi`, `omp`, `grok`, `dsh` or `t3` as appropriate. For clients that accept a command instead of JSON, use the same executable and arguments from that configuration. Restart the client, then ask it to use `report_task` for task lifecycle updates.

MCP reporting depends on the agent choosing to send updates. The Python `emit` command also works on Windows, using a Windows file lock and atomic snapshots. No shell-output scraping or inbound network listener is used. Files inherit the access controls of the current user's profile; POSIX permission bits do not provide Windows ACL guarantees.

**Native hook installers and the automatic T3 watcher remain macOS-only in this release.** They are not advertised as tested Windows integrations. See the [full connection guide](task-buddies.md) for the Mac adapters. Do not copy another machine's credentials, task snapshots or configuration into an installer.

## Build and verify

On Windows with Node.js 22 and Python 3.9+:

```powershell
npm ci --prefix desktop
npm --prefix desktop test
npm --prefix desktop run dist:win
$env:CHAN_EXE = (Resolve-Path 'dist/windows/win-unpacked/DeepSeek-chan.exe').Path
npm --prefix desktop run test:app
```

The **Release packages** GitHub workflow builds on `windows-2025`, checks the packaged app, installs the actual EXE silently, runs the installed app checks, and uninstalls it. It checks startup, all 279 poses in the catalog, renderer isolation, offline chat, Halloween, local task feedback, draft preservation through reminders and the five-minute rest state. It saves a screenshot for visual inspection. This is automated Windows runner coverage, not a claim of hands-on testing on every Windows PC, display/DPI arrangement or security product. Live OpenRouter calls are not part of these tests.

Only source and explicitly selected assets/connectors enter the app archive. Development files, credentials, private preferences, PDBs and source maps are excluded. The packaging check inspects our unpacked resources before artifacts are uploaded. Electron's required third-party notices and licenses remain included.

Build dependencies are pinned in `desktop/package-lock.json`. The current build-tool dependency audit reports a moderate `sprintf-js` advisory via electron-builder's logging/proxy tools; it has no patched published version at the time of this release. Those build dependencies are not shipped in `app.asar`; the runtime consists of Electron and the allowlisted application files.
