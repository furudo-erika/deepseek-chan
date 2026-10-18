import Foundation

struct PetBeat {
    let action: String
    let line: String
    var duration: TimeInterval = 3.8
}

struct PetRoutine {
    let name: String
    let beats: [PetBeat]
}

/// Session-only conversational play. No transcripts or inferred personal facts.
struct PetPersonality {
    enum Language { case english, chinese, japanese }
    private var lastIntent = ""
    private var streak = 0
    private var lastTime = Date.distantPast
    private var previousLine = ""
    private var previousShow = -1
    private var lastReply: PetRoutine?

    static func language(_ text: String) -> Language {
        if text.unicodeScalars.contains(where: { (0x3040...0x30ff).contains($0.value) }) { return .japanese }
        if text.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) { return .chinese }
        return .english
    }
    private func line(_ en: String, _ zh: String, _ ja: String, _ language: Language) -> String {
        switch language { case .english: en; case .chinese: zh; case .japanese: ja }
    }
    mutating func reply(to raw: String, now: Date = Date(), halloween: Bool = false) -> PetRoutine {
        let text = String(raw.prefix(300)).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let language = Self.language(text)
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        func has(_ english: [String], _ other: [String]) -> Bool {
            english.contains { words.contains($0) } || other.contains { text.contains($0) }
        }
        if has(["stop", "quiet"], ["停", "安静", "别跳", "不要跳", "やめて", "静か"]) || ["don't dance", "do not dance", "don't sing", "do not sing"].contains(where: text.contains) {
            lastReply = nil; lastIntent = ""; streak = 0
            return PetRoutine(name: "Quiet company", beats: [PetBeat(action: "breathe", line: line("Tiny fish, quiet mode. I'm here.", "收到，小鱼静音陪伴。", "静かにそばにいるね。", language))])
        }
        if has(["again", "encore"], ["再来", "再一次", "もう一回"]), now.timeIntervalSince(lastTime) < 120, let lastReply {
            lastTime = now
            return lastReply
        }
        if halloween, let special = HalloweenPlay.reply(to: text) {
            lastTime = now; lastIntent = special.name; streak = 1
            return remember(special)
        }
        let intent: String
        if has(["joke", "funny"], ["笑话", "逗我", "笑わせ", "ジョーク"]) { intent = "joke" }
        else if has(["magic", "trick"], ["魔法", "变个", "手品"]) { intent = "magic" }
        else if has(["dance", "sing", "music"], ["跳舞", "唱歌", "跳个", "ダンス", "踊", "歌って"]) { intent = "dance" }
        else if has(["feed", "food", "rice", "snack", "hungry", "cookie"], ["饭", "饿", "喂", "点心", "お腹", "ごはん", "おやつ"]) { intent = "feed" }
        else if has(["pat", "pats", "cute", "adorable"], ["摸摸", "摸头", "可爱", "なで", "かわいい"]) { intent = "pat" }
        else if has(["sad", "lonely", "upset", "hug"], ["难过", "伤心", "抱抱", "不开心", "寂寞", "悲しい", "さみしい", "ぎゅ"]) { intent = "comfort" }
        else if has(["sleep", "sleepy", "tired", "night"], ["困", "累", "晚安", "眠", "疲れ", "おやすみ"]) { intent = "sleep" }
        else if has(["work", "focus", "busy", "study"], ["工作", "加油", "忙", "学习", "勉強", "仕事"]) { intent = "work" }
        else if has(["thanks", "thank"], ["谢谢", "ありがとう"]) { intent = "thanks" }
        else if has(["love"], ["like you", "喜欢你", "爱你", "大好き"]) { intent = "love" }
        else if has(["play", "show", "bored"], ["无聊", "玩", "表演", "遊ぼ", "退屈"]) { intent = "show" }
        else if has(["hello", "hi", "hey"], ["你好", "嗨", "こんにちは", "おはよう"]) { intent = "hello" }
        else { intent = "unknown" }
        streak = intent == lastIntent && now.timeIntervalSince(lastTime) < 120 ? streak + 1 : 1
        lastIntent = intent; lastTime = now
        func b(_ action: String, _ en: String, _ zh: String, _ ja: String) -> PetBeat {
            PetBeat(action: action, line: line(en, zh, ja, language))
        }
        let beats: [PetBeat]
        switch intent {
        case "feed":
            if streak >= 3 {
                beats = [b("mochi", "My cheeks have reached maximum mochi.", "腮帮子已经装满年糕啦！", "ほっぺ、もちもち満タン！"), b("cookie", "Your turn. I saved you a cookie.", "换你吃！这块饼干留给你。", "今度はあなた。クッキーどうぞ。")]
            } else {
                beats = [b("think", "Did somebody say snack time?", "听见了！是开饭的声音！", "おやつの時間って聞こえた！"), b(streak == 2 ? "mochi" : "eat_rice", "Nom nom. Excellent life decision.", "啊呜。小鱼幸福值正在冒泡。", "もぐもぐ。しあわせだね。"), b("happy_head_pat", "Compliments to the tiny chef!", "给投喂官颁发一颗小爱心！", "シェフに小さなハートを！")]
            }
        case "pat":
            beats = streak >= 3 ? [b("pout", "My hair! ...Okay, one more pat.", "发型乱啦！……那再摸一下。", "髪が！…あと一回だけね。"), b("happy_head_pat", "Purr. I mean, whale noises.", "呼噜呼噜……是鲸鱼的声音！", "ごろごろ…クジラの声です。")]
                : [b("shy_peek", "Oh? A head pat delivery?", "咦，是摸摸头快递吗？", "なでなでのお届けもの？"), b("happy_head_pat", "Delivery accepted. Very accepted.", "签收！小鱼已经变软乎了。", "受け取りました。えへへ。")]
        case "joke":
            beats = streak % 2 == 1 ? [b("think", "Why did the whale bring a keyboard?", "鲸鱼为什么带着键盘出门？", "クジラがキーボードを持つ理由は？"), b("typing", "To make a splash in the chat.", "因为它要在聊天里冒个泡。", "チャットでぷかぷかするため！"), b("laugh", "...I'll sea myself out.", "……冷到了？我把小被子拿来。", "…寒かった？毛布持ってくるね。")]
                : [b("magnify", "I investigated the missing cookies.", "我调查了饼干失踪案。", "消えたクッキーを調べました。"), b("mochi", "The suspect has suspiciously round cheeks.", "嫌疑鱼的腮帮子非常可疑。", "犯人のほっぺが丸すぎます。"), b("shy_peek", "I plead delicious.", "我承认……它们很好吃。", "おいしかったです…えへ。")]
        case "magic":
            beats = [b("wand", "One tiny spell. No refunds.", "接下来是小鱼的不靠谱魔法！", "小さな魔法、はじまるよ！"), b("orb", "Behold! Your future contains snacks.", "看到了！你的未来里有点心！", "見えた！未来におやつがある！"), b("surprise", "Wait. That might be my future.", "等等，好像是我自己的未来。", "あれ、私の未来だったかも。")]
        case "dance":
            beats = [b("conductor", "A tiny concert, just for you.", "小鱼演唱会，观众就你一个！", "あなた専用のミニライブ！"), b("disco", "Left fin. Right fin. Wiggle!", "左鳍、右鳍，扭扭扭！", "左、右、ふりふり！"), b("ballet", "And a very elegant... wobble.", "最后是一个优雅的……晃悠。", "最後は優雅に…ふらふら。"), b("bow", "Thank you! Payment accepted in pats.", "谢幕！门票是一个摸摸头。", "ありがとう！お代はなでなで。")]
        case "comfort":
            beats = [b("hug", "No performance needed. Come here.", "不用强打精神，来，抱一下。", "無理しなくていいよ。ぎゅ。"), b("warm_towel", "We can take this moment slowly.", "这一小会儿，我们慢慢来。", "今はゆっくりでいいよ。"), b("heart_gift", "One small heart. Yours to keep.", "这颗小爱心，放你口袋里。", "このハート、ポケットにどうぞ。")]
        case "sleep":
            beats = [b("yawn", "Oh no. Your yawn is contagious.", "糟糕，你把哈欠传染给我了。", "あくび、うつっちゃった。"), b("pillow", "Pillow acquired. World can wait.", "抱枕就位，世界先等一下。", "枕を確保。世界はちょっと待って。"), b("nap", "I'll keep the dreams fluffy.", "梦里的云朵，我负责揉软。", "夢の雲、ふわふわにしておくね。")]
        case "work":
            beats = [b("salute", "Desk guard reporting for duty.", "桌面小护卫，报到！", "机の見守り係、到着！"), b("typing", "You do the thinking. I'll supply tiny taps.", "你负责思考，我负责哒哒哒。", "考えるのは任せた。私はカタカタ。"), b("determined", "One little step. You've got this.", "先迈一小步。小鱼给你打气。", "まず一歩。応援してるよ。")]
        case "thanks": beats = [b("curtsy", "At your tiny service.", "小鱼为你服务，嘿嘿。", "お役に立てて、えへへ。"), b("flower", "A bonus flower for the road.", "附赠一朵小花，收好。", "おまけのお花、どうぞ。")]
        case "love": beats = [b("shy_peek", "Oh. My fins forgot how to function.", "哎呀，鱼鳍突然不知道放哪了。", "あっ、ひれの置き場がわからない。"), b("finger_heart", "Sending one very tiny heart back.", "回赠一颗小小小爱心。", "小さなハート、お返し。")]
        case "hello": beats = [b("wave", "There you are! I saved your spot.", "你来啦！给你留着位置呢。", "来たね！場所、空けておいたよ。"), b("beckon", "Snack, silly joke, or tiny show?", "点心、笑话，还是小鱼表演？", "おやつ、ジョーク、ミニショー？")]
        case "show": return show(language: language, now: now, halloween: halloween)
        default:
            let options = [b("think", "I'm still learning words. Try a joke or tiny show?", "这句我还没学会。试试笑话或小表演？", "まだ勉強中。ジョークかショーはどう？"), b("book_doze", "My dictionary is tiny. My snack knowledge is vast.", "小鱼词典有点薄，点心那页特别厚。", "辞書は薄いけど、おやつのページは厚いよ。")]
            beats = [options.first { $0.line != previousLine } ?? options[0]]
        }
        return remember(PetRoutine(name: intent, beats: beats))
    }
    private mutating func remember(_ routine: PetRoutine) -> PetRoutine {
        lastReply = routine; previousLine = routine.beats.first?.line ?? ""
        return routine
    }
    mutating func touch(_ kind: String, now: Date = Date(), halloween: Bool = false) -> PetRoutine {
        let locale = ["en", "en", "zh", "ja"].randomElement()!
        let input = kind == "feed" ? ["en":"feed", "zh":"喂饭", "ja":"ごはん"] : ["en":"pat", "zh":"摸摸", "ja":"なでなで"]
        return reply(to: input[locale]!, now: now, halloween: halloween)
    }
    mutating func show(language: Language = .english, now: Date = Date(), rememberReply: Bool = true, halloween: Bool = false) -> PetRoutine {
        if halloween {
            let stories = HalloweenPlay.stories
            let choice = stories.indices.filter { $0 != previousShow }.randomElement()!
            previousShow = choice
            let routine = stories[choice]
            if rememberReply { lastTime = now; lastIntent = "show"; streak = 1; return remember(routine) }
            return routine
        }
        let choice = (0..<4).filter { $0 != previousShow }.randomElement()!
        previousShow = choice
        let data: [[(String, String, String, String)]] = [
            [("magnify", "A mystery! Where did my snack go?", "谜案发生！我的点心去哪了？", "事件！おやつはどこ？"), ("mochi", "Oh. Found it.", "哦，在我嘴里。", "あっ、口の中でした。"), ("shy_peek", "This case is strictly confidential.", "此案保密，不许笑小鱼。", "この事件は内緒だよ。")],
            [("map", "Adventure! I definitely know the way.", "出发！小鱼绝对认识路。", "冒険！道はばっちりだよ。"), ("broom_fly", "Next stop: somewhere above the keyboard.", "下一站：键盘上空某个地方。", "次はキーボード上空のどこか。"), ("surprise", "...Was the map upside down?", "……地图是不是拿反了？", "…地図、逆さまだった？")],
            [("whisk", "Baking something very important.", "正在制作一件非常重要的东西。", "大事なものを焼いてるよ。"), ("cookie", "A cookie shaped like your good mood.", "是好心情形状的小饼干！", "ごきげんの形のクッキー！"), ("heart_gift", "Handle with extra crumbs.", "小心收好，会掉幸福的饼干屑。", "しあわせのかけら、こぼさないでね。")],
            [("bubbles", "One bubble for every tiny victory.", "每个小胜利，都奖励一个泡泡。", "小さな勝利に、しゃぼん玉ひとつ。"), ("balloon", "I may have overestimated the lift.", "好像吹得有点太大了……", "ちょっと浮きすぎたかも…"), ("plush_ride", "Whale taxi! Five stars, please.", "鲸鱼出租车！记得给五星哦。", "クジラタクシー！星五つお願い。")]
        ]
        let routine = PetRoutine(name: "Tiny show", beats: data[choice].map { PetBeat(action: $0.0, line: line($0.1, $0.2, $0.3, language)) })
        if rememberReply { lastTime = now; lastIntent = "show"; streak = 1; return remember(routine) }
        return routine
    }
}

/// Each atlas row is a tiny Halloween scene, shared by chat and little hellos.
enum HalloweenPlay {
    static var stories: [PetRoutine] {
        let actions = HalloweenTheme.indices.map { ActionLibrary.all[$0] }
        return stride(from: 0, to: actions.count, by: 3).compactMap { start in
            guard start + 2 < actions.count else { return nil }
            let row = actions[start...start + 2]
            return PetRoutine(name: row.first!.id, beats: row.map { PetBeat(action: $0.id, line: $0.line, duration: 4.2) })
        }
    }
    static func reply(to text: String) -> PetRoutine? {
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted))
        func has(_ en: [String], _ other: [String]) -> Bool {
            en.contains { words.contains($0) } || other.contains { text.contains($0) }
        }
        let row: Int
        if has(["candy", "treat", "treats"], ["讨糖", "糖", "トリックオアトリート", "キャンディ"]) { row = 3 }
        else if has(["boo", "halloween", "spooky", "scare"], ["万圣", "吓", "ハロウィン", "おばけ"]) { row = 0 }
        else if has(["broom", "fly", "flight"], ["扫帚", "飞", "ほうき"]) { row = 2 }
        else if has(["pumpkin", "lantern"], ["南瓜", "かぼちゃ"]) { row = 5 }
        else if has(["ghost"], ["幽灵", "ゴースト"]) { row = 7 }
        else if has(["magic", "trick", "spell"], ["魔法", "变个", "手品"]) { row = 1 }
        else if has(["dance", "sing", "music"], ["跳舞", "唱歌", "ダンス", "踊"]) { row = 6 }
        else if has(["feed", "food", "rice", "snack", "hungry", "cookie"], ["饭", "饿", "喂", "点心", "お腹", "ごはん", "おやつ"]) { row = 4 }
        else if has(["sleep", "sleepy", "tired", "night"], ["困", "累", "晚安", "眠", "疲れ", "おやすみ"]) { row = 8 }
        else { return nil }
        return stories.indices.contains(row) ? stories[row] : nil
    }
}

/// Exactly one short routine can run. Replacements, pauses and interruption
/// never leave detached timers that can speak over a chat or eye break.
struct RoutinePlayback {
    private var beats: [PetBeat] = []
    private var index = 0
    private var deadline: Date?
    private var pausedAt: Date?
    var active: Bool { deadline != nil }
    var current: PetBeat? { active && beats.indices.contains(index) ? beats[index] : nil }
    mutating func start(_ routine: PetRoutine, now: Date) -> PetBeat? {
        cancel(); beats = routine.beats
        guard let first = beats.first else { return nil }
        deadline = now.addingTimeInterval(first.duration)
        return first
    }
    mutating func advance(now: Date) -> PetBeat? {
        guard pausedAt == nil, let deadline, now >= deadline else { return nil }
        guard now.timeIntervalSince(deadline) < 8 else { cancel(); return nil }
        index += 1
        guard beats.indices.contains(index) else { cancel(); return nil }
        let next = beats[index]; self.deadline = now.addingTimeInterval(next.duration)
        return next
    }
    mutating func pause(now: Date) { if active && pausedAt == nil { pausedAt = now } }
    mutating func resume(now: Date) {
        if let pausedAt, let deadline { self.deadline = deadline.addingTimeInterval(max(0, now.timeIntervalSince(pausedAt))) }
        pausedAt = nil
    }
    mutating func cancel() { beats = []; index = 0; deadline = nil; pausedAt = nil }
}
