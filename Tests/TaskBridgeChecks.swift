import Foundation

@main struct TaskBridgeChecks {
    static func main() async throws {
        let start = Date(timeIntervalSince1970: 10000)
        func event(_ id: String = "one", _ status: CompanionTask.Status = .working, at offset: Double = 1, source: String = "codex", title: String = "Fix the icon") -> CompanionTask {
            CompanionTask(version: 1, event_id: UUID().uuidString, source: source, task_id: id, title: title, status: status, updated_at: start.timeIntervalSince1970 + offset)
        }
        func time(_ offset: Double) -> Date { start.addingTimeInterval(offset) }
        var state = TaskFeedback(now: start)
        let working = event()
        state.ingest([working], now: time(2))
        precondition(state.next(now: time(2), blocked: true) == nil, "Busy UI defers the event")
        let done = event("one", .completed, at: 3)
        state.ingest([done, working], now: time(4))
        precondition(state.next(now: time(4), blocked: false)?.status == .completed, "Newest status replaces queued work and ignores out-of-order delivery")
        state.ingest([done], now: time(5))
        precondition(state.next(now: time(20), blocked: false) == nil, "Polling must not repeat speech")
        state.ingest([event("other", .working, at: 21), event("one", .working, at: 22, source: "claude"), event("wait", .waiting, at: 23)], now: time(24))
        precondition(state.sortedTasks.count == 4, "Source and task ID isolate concurrent agents")
        precondition(state.next(now: time(24), blocked: false)?.status == .waiting, "Needs-human feedback wins")
        precondition(state.next(now: time(25), blocked: false) == nil, "Global cooldown limits bursts")
        precondition(state.next(now: time(36), blocked: false) != nil)
        state.ingest([event("other", .working, at: 50)], now: time(51))
        precondition(state.next(now: time(200), blocked: false) == nil, "Deferred old reactions expire")
        state.reset(now: time(201))
        state.ingest([done], now: time(202))
        precondition(state.next(now: time(202), blocked: false) == nil, "Turning back on never replays an old completion")
        precondition(working.isStale(at: time(302)) && !working.isStale(at: time(300)))
        precondition(!done.isStale(at: time(400)))
        precondition(!event(at: 40).valid(at: start))
        precondition(!event(at: -90000).valid(at: start))
        precondition(!event(title: "bad\nlabel").valid(at: start))
        precondition(!event(source: "unknown").valid(at: start))
        var heartbeat = TaskFeedback(now: start)
        heartbeat.ingest([working], now: time(2))
        precondition(heartbeat.next(now: time(2), blocked: false) != nil)
        heartbeat.ingest([event(at: 61)], now: time(62))
        precondition(heartbeat.next(now: time(62), blocked: false) == nil)
        precondition(heartbeat.sortedTasks[0].updated_at == time(61).timeIntervalSince1970)
        var bounded = TaskFeedback(now: start)
        bounded.ingest((0..<200).map { event("many-\($0)", .working, at: Double($0) / 100) }, now: time(3))
        precondition(bounded.sortedTasks.count == 128, "In-memory task retention is bounded")
        precondition(bounded.next(now: time(3), blocked: false) != nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try JSONEncoder().encode(working).write(to: directory.appendingPathComponent("good.json"))
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent("bad.json"))
        try Data(repeating: 65, count: 20000).write(to: directory.appendingPathComponent("large.json"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.json"), withDestinationURL: directory.appendingPathComponent("good.json"))
        let result = await TaskInbox().read(directory: directory, now: time(2))
        precondition(result.tasks == [working], "Reader excludes malformed, oversized and symlink entries")
        var personality = TaskPersonality()
        let available = Set(ActionLibrary.all.map(\.id))
        for status in CompanionTask.Status.allCases {
            var last = ""
            for _ in 0..<15 {
                let story = personality.routine(for: event("a", status))
                precondition(story.beats.count == 2)
                precondition(story.beats.allSatisfy { available.contains($0.action) && $0.line.count < 80 })
                precondition(story.beats.last!.line != last)
                last = story.beats.last!.line
                for beat in story.beats {
                    let index = ActionLibrary.all.firstIndex { $0.id == beat.action }!
                    precondition(HalloweenTheme.isHalloween(ActionLibrary.action(HalloweenTheme.wearingCostume(index))))
                }
            }
        }
        print("PASS: task isolation, ordering, coalescing, deduplication, priority, cooldown, stale/expired updates, disabled/restart replay, heartbeat silence, bounded file reader, varied reactions and Halloween mapping")
    }
}
