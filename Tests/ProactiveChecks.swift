import Foundation

@main struct ProactiveChecks {
    static func main() {
        let stories = ProactiveLibrary.routines
        precondition(stories.count == 50)
        precondition(Set(stories.map(\.name)).count == 50)
        precondition(Set(stories.flatMap { $0.beats.map(\.line) }).count == 150)
        let actions = Set(ActionLibrary.all.map(\.id))
        for story in stories {
            precondition(story.beats.count == 3)
            for beat in story.beats {
                precondition(actions.contains(beat.action) && !beat.line.isEmpty && beat.line.count < 60)
            }
        }
        var deck = ProactiveDeck()
        var previous = ""
        for _ in 0..<3 {
            var seen: Set<String> = []
            for index in 0..<50 {
                if index == 19 { deck = ProactiveDeck(remaining: deck.remaining, last: deck.last) }
                let story = deck.next(in: stories)!
                precondition(story.name != previous && seen.insert(story.name).inserted)
                previous = story.name
            }
            precondition(seen.count == 50)
        }
        var stale = ProactiveDeck(remaining: ["deleted", stories[0].name, stories[0].name])
        precondition(stale.next(in: stories)?.name == stories[0].name)
        precondition(stale.next(in: []) == nil)
        let start = Date(timeIntervalSince1970: 1000)
        var clock = ProactiveSchedule(now: start, delay: 120)
        func ready(_ elapsed: Double, chat: Bool = false, bubble: Bool = false, blocked: Bool = false, draft: Bool = false, idle: Double = 0) -> Bool {
            clock.shouldSpeak(now: start.addingTimeInterval(elapsed), chatOpen: chat, ambientVisible: bubble, blocked: blocked, hasDraft: draft, idle: idle)
        }
        precondition(!ready(119) && ready(120))
        precondition(ready(120, chat: true, bubble: true), "Quiet open chat must permit proactive talk")
        precondition(!ready(120, bubble: true), "Do not interrupt another ordinary bubble")
        precondition(!ready(120, chat: true, draft: true), "Unsent draft stays private and uninterrupted")
        precondition(!ready(120, blocked: true), "Rest, hidden pet, sheets and dragging block chatter")
        precondition(!ready(120, idle: 600) && ready(120, idle: 599))
        clock.typed(now: start.addingTimeInterval(115))
        precondition(!ready(130, chat: true) && ready(145, chat: true))
        clock.schedule(now: start.addingTimeInterval(150), delay: 180)
        precondition(!ready(329) && ready(330))
        for _ in 0..<100 {
            let random = ProactiveSchedule(now: start)
            precondition((120...180).contains(random.due.timeIntervalSince(start)))
        }
        print("PASS: 50 stories / 150 unique lines, three no-repeat cycles, restart continuity, stale IDs, 2–3-minute cadence, quiet open chat, draft/typing guards, activity and interruption gates")
    }
}
