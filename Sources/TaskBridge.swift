import Foundation

/// Versioned local snapshots. Text is display-only and never sent to the AI client.
struct CompanionTask: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case working, waiting, completed, failed, cancelled, idle
        var label: String {
            switch self {
            case .working: "Working"
            case .waiting: "Needs you"
            case .completed: "Turn finished"
            case .failed: "Needs a fix"
            case .cancelled: "Stopped"
            case .idle: "Idle"
            }
        }
        var priority: Int {
            switch self { case .waiting, .failed: 3; case .completed: 2; case .cancelled: 1; case .working, .idle: 0 }
        }
    }
    let version: Int
    let event_id: String
    let source: String
    let task_id: String
    let title: String
    let status: Status
    let updated_at: Double
    var id: String { source + ":" + task_id }
    var sourceName: String {
        ["codex": "Codex", "claude": "Claude Code", "cursor": "Cursor", "pi": "Pi", "omp": "OMP", "grok": "Grok", "dsh": "dsh", "t3": "T3 Code", "other": "Agent"][source] ?? source
    }
    func isStale(at now: Date) -> Bool { (status == .working || status == .waiting) && now.timeIntervalSince1970 - updated_at > 300 }
    func valid(at now: Date) -> Bool {
        let age = now.timeIntervalSince1970 - updated_at
        return version == 1 && updated_at.isFinite && age >= -30 && age < 86400
            && ["codex", "claude", "cursor", "pi", "omp", "grok", "dsh", "t3", "other"].contains(source)
            && !task_id.isEmpty && task_id.utf8.count <= 128 && !event_id.isEmpty && event_id.utf8.count <= 128
            && !title.isEmpty && title.count <= 80 && !title.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

struct TaskSnapshot: Sendable {
    var tasks: [CompanionTask] = []
    var error: String? = nil
}

actor TaskInbox {
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["DEEPSEEK_CHAN_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true).appendingPathComponent("tasks")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".deepseek-chan/tasks")
    }
    func read(directory: URL = TaskInbox.directory, now: Date = Date()) -> TaskSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return TaskSnapshot() }
        do {
            guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
                return TaskSnapshot(error: "Cannot read the task inbox.")
            }
            var tasks: [CompanionTask] = []
            var inspected = 0
            for case let file as URL in entries {
                inspected += 1
                if inspected > 256 { break }
                guard file.pathExtension == "json",
                      let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let handle = try? FileHandle(forReadingFrom: file) else { continue }
                let data = try? handle.read(upToCount: 8193)
                try? handle.close()
                guard let data, data.count <= 8192, let task = try? JSONDecoder().decode(CompanionTask.self, from: data), task.valid(at: now) else { continue }
                tasks.append(task)
            }
            return TaskSnapshot(tasks: tasks)
        }
    }
}

/// Latest event per task wins, including while the user is busy. No replay of old notifications on launch.
struct TaskFeedback {
    private(set) var tasks: [String: CompanionTask] = [:]
    private var pending: [String: CompanionTask] = [:]
    private var nextReaction = Date.distantPast
    private var acceptAfter: Date
    init(now: Date = Date()) { acceptAfter = now }
    mutating func reset(now: Date) { self = TaskFeedback(now: now) }
    mutating func ingest(_ updates: [CompanionTask], now: Date) {
        for task in updates.sorted(by: { $0.updated_at < $1.updated_at }) where task.valid(at: now) {
            let old = tasks[task.id]
            if let old, old.updated_at > task.updated_at || old.event_id == task.event_id { continue }
            tasks[task.id] = task
            // Heartbeats refresh liveness without producing more speech.
            if old?.status == task.status && old?.title == task.title { continue }
            pending.removeValue(forKey: task.id)
            if task.updated_at >= acceptAfter.timeIntervalSince1970 && now.timeIntervalSince1970 - task.updated_at < 120 {
                pending[task.id] = task
            }
        }
        tasks = tasks.filter { now.timeIntervalSince1970 - $0.value.updated_at < 86400 }
        if tasks.count > 128 {
            tasks = Dictionary(uniqueKeysWithValues: tasks.values.sorted { $0.updated_at > $1.updated_at }.prefix(128).map { ($0.id, $0) })
        }
        pending = pending.filter { tasks[$0.key] != nil && now.timeIntervalSince1970 - $0.value.updated_at < 120 }
        if pending.count > 32 {
            pending = Dictionary(uniqueKeysWithValues: pending.values.sorted { $0.updated_at > $1.updated_at }.prefix(32).map { ($0.id, $0) })
        }
    }
    mutating func next(now: Date, blocked: Bool) -> CompanionTask? {
        pending = pending.filter { now.timeIntervalSince1970 - $0.value.updated_at < 120 }
        guard !blocked, now >= nextReaction else { return nil }
        let next = pending.values.sorted {
            if $0.status.priority != $1.status.priority { return $0.status.priority > $1.status.priority }
            return $0.updated_at < $1.updated_at
        }.first
        if let next { pending.removeValue(forKey: next.id); nextReaction = now.addingTimeInterval(12) }
        return next
    }
    var sortedTasks: [CompanionTask] { tasks.values.sorted { $0.updated_at > $1.updated_at } }
}

struct TaskPersonality {
    private var lastLines: [CompanionTask.Status: String] = [:]
    mutating func routine(for task: CompanionTask) -> PetRoutine {
        let poses: [String]
        let lines: [String]
        switch task.status {
        case .working:
            poses = ["typing", "think"]
            lines = ["Tiny coding hat: on! ♡", "がんばって！I'll guard the snacks.", "小鱼监工，轻轻敲键盘。", "You build. I'll provide moral support."]
        case .waiting:
            poses = ["wave", "shy_peek"]
            lines = ["Psst… your agent needs you. ♡", "ちょっと！A tiny decision awaits.", "戳戳，轮到你啦。", "One human-sized answer, please!"]
        case .completed:
            poses = ["trophy", "happy_head_pat"]
            lines = ["Turn finished! Tiny victory wiggle!", "おつかれさま！Ready for your review.", "收工一小步，撒花一大把！", "Your agent is back. Cookie break? ♡"]
        case .failed:
            poses = ["magnify", "heart_gift"]
            lines = ["A little snag. We can untangle it.", "だいじょうぶ。Let's take a look.", "不慌，小鱼陪你找问题。", "Something needs a fix. I'm here. ♡"]
        case .idle:
            poses = ["breathe", "wave"]
            lines = ["Your agent is quiet now. Tiny stretch?", "ひと休み。I'll stay nearby.", "先歇一下，看看任务进展吧。"]
        case .cancelled:
            poses = ["breathe", "wave"]
            lines = ["Tools down. Tiny stretch?", "Stopped for now. ひと休み。", "先歇一下，小鱼还在。"]
        }
        let line = lines.filter { $0 != lastLines[task.status] }.randomElement() ?? lines[0]
        lastLines[task.status] = line
        // Resolve against the catalog so this contract remains valid if pose IDs change.
        let available = Set(ActionLibrary.all.map(\.id))
        let a = poses.map { available.contains($0) ? $0 : "think" }
        return PetRoutine(name: "Task buddy", beats: [
            PetBeat(action: a[0], line: "\(task.sourceName): \(String(task.title.prefix(42)))", duration: 3.5),
            PetBeat(action: a[1], line: line, duration: 5)
        ])
    }
}
