import Foundation

@main struct HalloweenChecks {
    static func main() {
        let library = ActionLibrary.all
        let witch = Set(HalloweenTheme.indices)
        let classic = Set(HalloweenTheme.classicIndices)
        precondition(witch.count == 27 && classic.count == 252 && witch.isDisjoint(with: classic))
        precondition(witch.union(classic) == Set(library.indices))
        for i in library.indices {
            precondition(witch.contains(HalloweenTheme.wearingCostume(i)))
            for sleep in [false, true] {
                for dance in [false, true] {
                    for tick in 0..<30 {
                        let shown = HalloweenTheme.displayIndex(i, enabled: true, sleeping: sleep, dancing: dance, time: Double(tick) * 0.42)
                        precondition(witch.contains(shown))
                        if sleep { precondition(shown == HalloweenTheme.index("rest")) }
                        precondition(HalloweenTheme.displayIndex(i, enabled: false, sleeping: sleep, dancing: dance, time: 1) == (sleep ? 5 : i))
                    }
                }
            }
        }
        let favorite = HalloweenTheme.index("broom")
        precondition(HalloweenTheme.choices(enabled: true, favorites: [library[favorite].id, "wave"], favoritesOnly: true) == [favorite])
        precondition(Set(HalloweenTheme.choices(enabled: true, favorites: ["wave"], favoritesOnly: true)) == witch)
        precondition(Set(HalloweenTheme.choices(enabled: false, favorites: [library[favorite].id], favoritesOnly: true)) == classic)
        let stories = ProactiveLibrary.halloweenRoutines
        precondition(stories.count == 9 && Set(stories.map(\.name)).count == 9)
        precondition(Set(stories.flatMap { $0.beats.map(\.line) }).count == 27)
        precondition(stories.allSatisfy { $0.beats.count == 3 && $0.beats.allSatisfy { $0.action.hasPrefix("halloween_") && $0.line.count < 60 } })
        var deck = ProactiveDeck()
        var last = ""
        for _ in 0..<3 {
            var visited = Set<String>()
            for i in 0..<9 {
                if i == 4 { deck = ProactiveDeck(remaining: deck.remaining, last: deck.last) }
                let story = deck.next(in: stories)!
                precondition(story.name != last && visited.insert(story.name).inserted)
                last = story.name
            }
            precondition(visited.count == 9)
        }
        var pet = PetPersonality()
        let prompts = ["trick or treat", "讨糖", "キャンディ", "boo", "magic", "扫帚", "pumpkin", "ghost", "dance", "snack", "sleep"]
        for prompt in prompts {
            let story = pet.reply(to: prompt, halloween: true)
            precondition(story.beats.count == 3 && story.beats.allSatisfy { $0.action.hasPrefix("halloween_") })
            precondition(pet.reply(to: "again", halloween: true).name == story.name)
        }
        precondition(pet.reply(to: "stop magic", halloween: true).name == "Quiet company")
        precondition(!pet.reply(to: "again", halloween: true).beats.contains { $0.action.hasPrefix("halloween_") })
        precondition(HalloweenPlay.reply(to: "I like treating people kindly") == nil, "English uses whole words")
        var previous = ""
        for _ in 0..<30 {
            let show = pet.show(rememberReply: false, halloween: true)
            precondition(show.name != previous)
            previous = show.name
        }
        precondition(ProactiveLibrary.routines.count == 48, "Classic stories remain separate")
        print("PASS: 27 costume poses, classic/favorite pool isolation, all sleep/dance/chat mappings, 9 seasonal stories, saved no-repeat cycles, multilingual cues, encore/stop, varied shows")
    }
}
