import AppKit
import SwiftUI

struct TaskBuddiesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = "codex"
    @State private var copied = false
    private var integrationPath: String { Bundle.main.resourceURL!.appendingPathComponent("integrations").path }
    private func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private var command: String {
        let script = quote(integrationPath + "/chan.py")
        switch source {
        case "codex": return "codex mcp add deepseek-chan -- python3 \(script) mcp --source codex"
        case "claude", "cursor": return "python3 \(script) install \(source)"
        case "pi", "omp": return "\(source) --extension \(quote(integrationPath + "/" + source + ".ts"))"
        default: return "python3 \(script) run --source \(source) -- \(source)"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task buddies").font(.system(size: 23, weight: .bold, design: .rounded))
                    Text("You build. I'll keep you company. ♡").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Toggle("React to agent tasks", isOn: $model.taskFeedbackEnabled).toggleStyle(.switch)
            Text(model.taskConnectionError ?? (model.taskFeedbackEnabled ? "Local only. Task details never go to the AI chat service." : "Reactions paused. Your coding tools can keep working."))
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                if model.connectedTasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal").font(.system(size: 30)).foregroundStyle(Color.ocean)
                        Text("Waiting for our first task").font(.headline)
                        Text("Connect a tool below, then start a new turn.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.connectedTasks.prefix(20)) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: symbol(task)).foregroundStyle(task.status == .waiting ? .orange : Color.ocean).frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("\(task.sourceName) · \(String(task.task_id.prefix(6))) · \(task.isStale(at: model.now) ? "No recent update" : task.status.label)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Date(timeIntervalSince1970: task.updated_at), style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }.padding(10).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }.frame(height: 200)
            Divider()
            HStack {
                Picker("Connect", selection: $source) {
                    Text("Codex · MCP").tag("codex")
                    Text("Claude Code · hooks").tag("claude")
                    Text("Cursor · hooks").tag("cursor")
                    Text("Pi · extension").tag("pi")
                    Text("OMP · extension").tag("omp")
                    Text("Grok · CLI session").tag("grok")
                    Text("dsh · CLI session").tag("dsh")
                }.onChange(of: source) { _, _ in copied = false }
                Button(copied ? "Copied!" : "Copy setup command") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string); copied = true
                }
            }
            Text(source == "codex" ? "Run the command in Terminal, restart Codex, and ask it to report this task to DeepSeek-chan. MCP updates are agent-driven; automatic completion hooks are in the guide." : source == "claude" || source == "cursor" ? "Run in Terminal, then restart the client. Setup preserves existing hooks and saves a backup. Requires Python 3.9+." : source == "pi" || source == "omp" ? "Run in Terminal to launch with the pet extension. Requires Python 3.9+. Events stay on this Mac." : "Launch through this command. She follows the CLI process until it exits; individual turns and approvals are not detected.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Preview reaction ♡") { model.previewTaskBuddy() }
                Spacer()
                Link("Connection guide", destination: URL(string: "https://github.com/furudo-erika/deepseek-chan/blob/feat/task-buddies/docs/task-buddies.md")!)
            }
        }.padding(24).frame(width: 570, height: 550)
            .background(Color(red: 0.94, green: 0.97, blue: 1)).preferredColorScheme(.light)
    }
    private func symbol(_ task: CompanionTask) -> String {
        if task.isStale(at: model.now) { return "clock.badge.questionmark" }
        switch task.status {
        case .working: return "keyboard"
        case .waiting: return "hand.wave"
        case .completed: return "checkmark.circle"
        case .failed: return "wrench.and.screwdriver"
        case .cancelled: return "pause.circle"
        }
    }
}
