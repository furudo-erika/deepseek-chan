import Foundation

@main struct PersonalityChecks {
    static func main() {
        var pet = PetPersonality()
        let now = Date(timeIntervalSince1970: 10_000)
        let ids = Set(ActionLibrary.all.map(\.id))
        let requests = ["Tell a joke", "讲个笑话", "ジョーク", "magic trick", "变魔法", "手品", "dance", "跳舞", "踊って", "feed", "喂饭", "ごはん", "pat", "摸摸头", "なでなで", "I'm sad", "抱抱", "悲しい", "sleepy", "晚安", "おやすみ", "work", "工作", "仕事", "thanks", "谢谢", "ありがとう", "love you", "喜欢你", "大好き", "hello", "你好", "こんにちは", "play", "无聊", "遊ぼ", "this is a test", "这句听不懂", "これは何ですか"]
        for request in requests {
            let reply = pet.reply(to: request, now: now)
            precondition(!reply.beats.isEmpty && reply.beats.count <= 4)
            for beat in reply.beats {
                precondition(ids.contains(beat.action), "Missing action: \(beat.action)")
                precondition(!beat.line.isEmpty && beat.line.count <= 65, beat.line)
                precondition(PetPersonality.language(request) == PetPersonality.language(beat.line), "Language: \(request) => \(beat.line)")
            }
        }
        precondition(pet.reply(to: "this", now: now).name == "unknown", "hi must match a word, not this")
        precondition(pet.reply(to: "I like apples", now: now).name == "unknown")
        precondition(pet.reply(to: "I don't feel happy, I'm sad", now: now).name == "comfort")
        for request in ["stop", "don't dance", "不要跳舞", "やめて"] {
            let reply = pet.reply(to: request, now: now)
            precondition(reply.name == "Quiet company" && reply.beats.count == 1)
            precondition(pet.reply(to: "again", now: now).name == "unknown", "Stop clears encore memory")
        }
        var food = PetPersonality()
        precondition(food.reply(to: "feed", now: now).beats[1].action == "eat_rice")
        precondition(food.reply(to: "喂饭", now: now.addingTimeInterval(1)).beats[1].action == "mochi")
        precondition(food.reply(to: "ごはん", now: now.addingTimeInterval(2)).beats.first?.action == "mochi")
        precondition(food.reply(to: "feed", now: now.addingTimeInterval(123)).beats[1].action == "eat_rice", "Streak expires")
        var pats = PetPersonality()
        _ = pats.reply(to: "pat", now: now); _ = pats.reply(to: "pat", now: now)
        precondition(pats.reply(to: "pat", now: now).beats.first?.action == "pout")
        let joke = pet.reply(to: "joke", now: now)
        precondition(pet.reply(to: "joke", now: now).beats.first?.action != joke.beats.first?.action)
        let show = pet.show(language: .chinese, now: now)
        _ = pet.show(rememberReply: false)
        precondition(pet.reply(to: "再来", now: now.addingTimeInterval(10)).beats.map(\.line) == show.beats.map(\.line), "Silent idle shows must not replace the requested encore")
        precondition(pet.reply(to: "again", now: now.addingTimeInterval(131)).name == "unknown", "Encore expires")
        var seen: Set<String> = []
        var last = ""
        for _ in 0..<100 {
            let show = pet.show()
            let first = show.beats[0].action
            precondition(first != last)
            last = first; seen.insert(first)
            precondition(show.beats.allSatisfy { ids.contains($0.action) })
        }
        precondition(seen.count == 4)
        var playback = RoutinePlayback()
        precondition(playback.start(joke, now: now)?.action == "think")
        precondition(playback.advance(now: now.addingTimeInterval(3)) == nil)
        precondition(playback.advance(now: now.addingTimeInterval(4))?.action == "typing")
        playback.pause(now: now.addingTimeInterval(5))
        precondition(playback.advance(now: now.addingTimeInterval(50)) == nil)
        playback.resume(now: now.addingTimeInterval(55))
        precondition(playback.advance(now: now.addingTimeInterval(57)) == nil)
        precondition(playback.advance(now: now.addingTimeInterval(58))?.action == "laugh")
        precondition(playback.advance(now: now.addingTimeInterval(62)) == nil && !playback.active)
        _ = playback.start(joke, now: now)
        _ = playback.start(show, now: now.addingTimeInterval(1))
        precondition(playback.advance(now: now.addingTimeInterval(5))?.action == show.beats[1].action, "Latest routine wins")
        playback.cancel()
        precondition(playback.advance(now: now.addingTimeInterval(6)) == nil && playback.current == nil)
        _ = playback.start(joke, now: now)
        precondition(playback.advance(now: now.addingTimeInterval(30)) == nil && !playback.active, "Stale beats cannot burst after a stall")
        precondition(playback.start(PetRoutine(name: "empty", beats: []), now: now) == nil && !playback.active)
        for action in ActionLibrary.all {
            for step in 0..<200 {
                let motion = action.sample(at: Double(step) / 20)
                precondition(motion.x.isFinite && motion.y.isFinite && motion.angle.isFinite)
                precondition(abs(motion.x) <= 10 && abs(motion.y) <= 18 && abs(motion.angle) <= 8)
                precondition((0.9...1.1).contains(motion.scaleX) && (0.9...1.1).contains(motion.scaleY))
            }
        }
        print("PASS: 39 multilingual prompts, intent boundaries, repeated feeding/pats, joke variation, encore/expiry, four shows, pause/resume/replacement/cancel/stale routines, \(ActionLibrary.all.count) bounded pose rhythms")
    }
}
