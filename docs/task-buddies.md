# Task buddies

DeepSeek-chan can follow coding tasks on the same Mac. She types while an agent works, waves when it needs you, celebrates a finished turn, and offers a little comfort when something fails. This is an external desktop companion, not a replacement for Codex's built-in pet.

**Requires the new source/development build. The published 1.8.1 DMG does not contain this feature.** Build with `zsh scripts/package-debug.sh`, then open `dist/DeepSeek-chan.app`. Python 3.9+ is required for connectors; Pi/OMP also need their own runtime. No Python packages or API keys are needed.

Open **Task buddies** using the terminal icon in the dashboard, the pet's context menu, or the menu-bar menu. Copy a setup command, run it in Terminal, and follow the tool-specific instructions below. Install the app in its permanent location first: moving it later changes connector paths.

## Connections at a glance

| Tool | Connection | What it observes |
| --- | --- | --- |
| Codex | MCP `report_task`; optional `notify` hook | Agent-reported state; native hook detects turn completion only |
| Claude Code | Lifecycle hooks | Prompt start, tool activity, permission/question waits, stop and terminal failure |
| Cursor | Lifecycle hooks | Prompt start, tool activity, completed/error/aborted stop |
| Pi | Extension | Start, heartbeat, final settled state, shutdown |
| OMP | Extension | Start, heartbeat, end of agent run, shutdown |
| Grok Build / Grok CLI | Command wrapper or explicit events | Process lifetime; not individual interactive turns or approvals |
| dsh (DeepSeek Harness) | Command wrapper or explicit events | Process lifetime; not individual interactive turns or approvals |
| Other local tools | MCP or CLI events | Explicit states sent by the integration |

Hooks/extensions run automatically once loaded. MCP depends on the agent choosing to report states. A process wrapper can only tell that a process is running or has exited; an interactive CLI may sit at a prompt while still shown as working. No connector infers that tests passed or a deployment succeeded from a completed turn.

## Codex

The Task buddies panel copies a command using the installed app's bundled connector. From a source checkout, the equivalent is:

```sh
codex mcp add deepseek-chan -- python3 "$PWD/integrations/chan.py" mcp --source codex
```

Restart Codex so the new MCP tool becomes available. Ask:

> Use DeepSeek-chan's report_task tool for this task. Use a unique task ID for this conversation and a short, non-sensitive title. Report working when starting, waiting when you need me, and completed, failed, or cancelled when the turn ends. Refresh working occasionally during long tasks.

For **automatic completion notifications**, add this top-level setting to your Codex configuration, using an absolute path:

```toml
notify = ["python3", "/absolute/path/to/deepseek-chan/integrations/chan.py", "hook", "codex"]
```

Preserve any existing `notify` handler: this is a single setting, so chain handlers in your own script instead of overwriting one. The completion hook drops message contents and uses only event type and a hashed thread ID. MCP and notify use different IDs unless you deliberately align them; normally choose one mode to avoid duplicate completion reactions.

Sources: [Codex MCP](https://developers.openai.com/codex/mcp), [Codex notifications](https://developers.openai.com/codex/config-advanced#notifications).

## Claude Code and Cursor

From a checkout:

```sh
python3 integrations/chan.py install claude
# Or:
python3 integrations/chan.py install cursor
```

The installer adds hooks to `~/.claude/settings.json` or `~/.cursor/hooks.json`, preserving other settings and existing hooks. It writes a private timestamped backup before a change. Running the same installer again is idempotent. Restart your client. To inspect the fragment without changing settings:

```sh
python3 integrations/chan.py config claude
python3 integrations/chan.py config cursor
```

Only a session/conversation identifier and lifecycle metadata are used. No prompt, tool argument, transcript, file path, email address, or assistant message is stored. Hooks emit no stdout and return success even if the companion is unavailable. They never approve, block, retry, or continue an agent task. Claude's ordinary idle notifications are intentionally ignored; permission prompts and elicitation dialogs produce a waiting reaction. A recoverable tool failure is not treated as terminal task failure.

Sources: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Cursor hooks](https://cursor.com/docs/hooks).

## Pi and OMP

Launch with the extension (keep all files in `integrations/` together):

```sh
pi --extension "$PWD/integrations/pi.ts"
omp --extension "$PWD/integrations/omp.ts"
```

The Pi adapter targets the current `agent_settled` event so it waits for automatic continuations. OMP uses its `agent_end` contract, which describes one agent run. Both send a heartbeat every minute while active, inspect only the last assistant message's stop-reason metadata, and stop their timers on session shutdown. `DEEPSEEK_CHAN_PYTHON` can select an absolute Python executable if `python3` is unavailable to the agent.

Sources: [Pi extension lifecycle](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md), [OMP extension types](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/extensibility/extensions/types.ts). Older clients may require an adapter change; event-driven tests are not a claim that every installed client version was tested live.

## Grok Build, dsh, and command-line tools

Run a command through the local wrapper:

```sh
python3 integrations/chan.py run --source grok --title "Grok CLI session" -- grok
python3 integrations/chan.py run --source dsh --title "dsh session" -- dsh
```

It preserves stdin, stdout, stderr, and normal exit codes, without parsing terminal output. For detailed per-task feedback, send explicit events from your own hooks or agent instructions:

```sh
python3 integrations/chan.py emit --source grok --task unique-task-123 --status working --title "Fix the icon"
python3 integrations/chan.py emit --source grok --task unique-task-123 --status waiting --title "Choose an icon"
python3 integrations/chan.py emit --source grok --task unique-task-123 --status completed --title "Icon ready for review"
```

Supported states: `working`, `waiting`, `completed`, `failed`, `cancelled`. Sources: `codex`, `claude`, `cursor`, `pi`, `omp`, `grok`, `dsh`, `other`. Use a stable, unique task ID per conversation, and a title of at most 80 characters. Do not put private content in labels.

Any client with local stdio MCP support can instead launch:

```sh
python3 /absolute/path/to/integrations/chan.py mcp --source grok
```

This is a generic MCP connection; native Grok Build and dsh lifecycle plugins are not included yet. Remote/cloud agents need an explicit event relay onto this Mac; this feature does not read remote machines or install a network listener.

## Behavior, privacy, and disabling

- Events stay in `~/.deepseek-chan/tasks/`, with a private directory and one atomic JSON snapshot per source/task. The writer keeps at most 128 snapshots and cleans entries older than a day on subsequent writes. Files can remain on disk when no writer runs; the app ignores entries older than a day.
- Explicit CLI/MCP labels are displayed as plain text. Task feedback uses authored dialogue and never calls OpenRouter. A label is visible on your desktop, so keep it non-sensitive.
- The app polls off the UI thread every two seconds. Newer task states replace queued older ones; unchanged heartbeats are silent. Notifications are spaced at least 12 seconds apart. Waiting/failure events take priority.
- Reactions wait while you drag, type a draft, view settings, take an eye break, or hide the pet. A deferred reaction expires after two minutes instead of interrupting much later. Existing snapshots appear in the panel after launch, but their old reactions do not replay.
- Working/waiting snapshots without an update for five minutes show **No recent update**. This means unknown liveness, not completion or failure. Hook-only clients can reach this state during long thinking periods without tool events.
- Use **React to agent tasks** to pause reactions and reads. This does not stop agents or remove their hooks. Turn **Little hellos** off separately if you also want to stop unrelated pet chatter.
- To disconnect, remove only the entries containing `chan.py` from the relevant client's hook config, remove the Codex MCP entry (`codex mcp remove deepseek-chan`), or launch Pi/OMP without the extension. Remove an optional Codex `notify` entry only if you added it. Keep unrelated settings intact.

For isolated tests, set `DEEPSEEK_CHAN_HOME` to a temporary absolute directory in both the writer and app process. The JSON protocol is intentionally small and independent of Swift so future Windows/Linux apps can consume the same states; the current writer uses a POSIX file lock and the desktop app remains macOS-only.

## Verification boundary

Automated checks cover concurrent writers, private file permissions, payload filtering, hook mapping, preserving existing settings, MCP stdio requests, process exit propagation, Pi/OMP event callbacks, Swift decoding, stale/duplicate/out-of-order events, queue bounds and outfit-aware reaction poses. No paid model request is needed. Actual provider-driven approvals, every client version, and remote-agent relays are not covered by these checks.

The development build was also exercised in the native macOS app: a CLI event appeared in the task panel, an installed stdio MCP call produced a Halloween completion reaction, and a waiting event stayed queued while an unsent chat draft remained unchanged. Full live sessions in all seven coding clients have not been verified.
