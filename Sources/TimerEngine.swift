import Foundation

struct TimerEngine {
    enum Phase: String { case waiting, focusing, reminding, resting, paused }
    private(set) var phase: Phase = .waiting
    private(set) var deadline: Date?
    private(set) var completedBreaks = 0
    var interval: TimeInterval = 20 * 60
    let restDuration: TimeInterval = 5 * 60

    mutating func tick(now: Date, mouseMoved: Bool, idle: TimeInterval) {
        if phase == .resting {
            if let deadline, now >= deadline {
                completedBreaks += 1
                reset()
            }
            return
        }
        if phase == .paused { return }
        if idle >= restDuration { reset(); return }
        if phase == .waiting && mouseMoved {
            phase = .focusing
            deadline = now.addingTimeInterval(interval)
        }
        if phase == .focusing, let deadline, now >= deadline {
            phase = .reminding
            self.deadline = nil
        }
    }
    mutating func startBreak(now: Date) {
        phase = .resting
        deadline = now.addingTimeInterval(restDuration)
    }
    mutating func snooze(now: Date) {
        phase = .focusing
        deadline = now.addingTimeInterval(5 * 60)
    }
    mutating func setInterval(_ seconds: TimeInterval, now: Date) {
        interval = seconds
        if phase == .focusing { deadline = now.addingTimeInterval(seconds) }
    }
    mutating func togglePause() {
        if phase == .paused { reset() }
        else { phase = .paused; deadline = nil }
    }
    mutating func reset() { phase = .waiting; deadline = nil }
    mutating func wake(now: Date) {
        if phase == .resting { tick(now: now, mouseMoved: false, idle: 0) }
        else if phase != .paused { reset() }
    }
    func remaining(now: Date) -> TimeInterval {
        max(0, deadline?.timeIntervalSince(now) ?? interval)
    }
}
