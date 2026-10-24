import Foundation

/// One authored three-beat story per row of the expansion atlases.
enum ProactiveLibrary {
    static var halloweenRoutines: [PetRoutine] { HalloweenPlay.stories }
    static var routines: [PetRoutine] {
        let actions = ActionLibrary.all.filter { $0.atlas.hasPrefix("actions-extra-") || $0.atlas == "actions-breeze-dance" }
        return stride(from: 0, to: actions.count, by: 3).compactMap { start in
            guard start + 2 < actions.count else { return nil }
            let row = Array(actions[start...start + 2])
            return PetRoutine(name: row[0].id, beats: row.map { PetBeat(action: $0.id, line: $0.line, duration: 4.2) })
        }
    }
}

/// Saved between launches: finish all stories before refilling the bag.
struct ProactiveDeck {
    private(set) var remaining: [String]
    private(set) var last: String?
    init(remaining: [String] = [], last: String? = nil) {
        self.remaining = remaining; self.last = last
    }
    mutating func next(in stories: [PetRoutine]) -> PetRoutine? {
        guard !stories.isEmpty else { return nil }
        let ids = Set(stories.map(\.name))
        var seen: Set<String> = []
        remaining = remaining.filter { ids.contains($0) && seen.insert($0).inserted }
        if remaining.isEmpty { remaining = stories.map(\.name).shuffled() }
        if remaining.last == last, remaining.count > 1 { remaining.swapAt(0, remaining.count - 1) }
        let selected = remaining.removeLast(); last = selected
        return stories.first { $0.name == selected }
    }
}

struct ProactiveSchedule {
    private(set) var due: Date
    private(set) var lastInput = Date.distantPast
    init(now: Date = Date(), delay: TimeInterval = Double.random(in: 120...180)) {
        due = now.addingTimeInterval(delay)
    }
    mutating func schedule(now: Date, delay: TimeInterval = Double.random(in: 120...180)) {
        due = now.addingTimeInterval(delay)
    }
    mutating func typed(now: Date) { lastInput = now }
    func shouldSpeak(now: Date, chatOpen: Bool, ambientVisible: Bool, blocked: Bool, hasDraft: Bool, idle: TimeInterval) -> Bool {
        now >= due && !blocked && !hasDraft && now.timeIntervalSince(lastInput) >= 30
            && (chatOpen || !ambientVisible) && idle < 600
    }
}
