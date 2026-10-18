import Foundation

struct PetAction: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let atlas: String
    let frame: Int
    let motion: PetMotion
    let line: String
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        let searchable = name + " " + category + " " + id.replacingOccurrences(of: "_", with: " ") + " " + line
        return words.allSatisfy { searchable.localizedCaseInsensitiveContains(String($0)) }
    }
    /// Short bursts and pauses give expressive poses their own rhythm.
    func sample(at time: Double) -> MotionSample {
        let t = max(0, time)
        switch id {
        case "eat_rice", "mochi", "cookie", "halloween_cookie":
            let chew = t.truncatingRemainder(dividingBy: 3.2) < 1.6 ? sin(t * 13) : 0
            return .init(y: -1.5 * abs(chew), angle: chew, scaleX: 1 + 0.018 * chew, scaleY: 1 - 0.015 * chew)
        case "laugh", "halloween_giggle":
            let giggle = t.truncatingRemainder(dividingBy: 2.8) < 1.5 ? sin(t * 17) : 0
            return .init(x: 1.5 * giggle, y: -2 * abs(giggle), angle: 2.5 * giggle)
        case "surprise", "halloween_spell_pop":
            let startle = exp(-t * 2.4) * sin(t * 11)
            return .init(y: -14 * abs(startle), angle: 5 * startle, scaleX: 1 - 0.035 * startle, scaleY: 1 + 0.045 * startle)
        case "shy_peek", "halloween_shy":
            return .init(x: 4 * sin(t * 1.3), y: 1.5 * (1 - cos(t * 1.3)), angle: 4 * sin(t * 1.3))
        case "happy_head_pat":
            return .init(y: 1.5 * sin(t * 2.2), angle: 3.5 * sin(t * 2.2), scaleX: 1.015, scaleY: 0.985)
        case "yawn", "book_doze", "nap", "halloween_yawn", "halloween_rest":
            let nod = pow(max(0, sin(t * 1.1)), 4)
            return .init(y: 3 * nod, angle: 3 * nod, scaleY: 1 - 0.018 * nod)
        case "wand", "orb", "halloween_wand":
            return .init(x: 2 * sin(t * 1.6), y: -4 - 3 * sin(t * 2), angle: 2 * sin(t * 1.6))
        default: return motion.sample(at: t)
        }
    }
    var reactionSymbol: String? {
        switch id {
        case "happy_head_pat", "finger_heart", "heart_gift", "hug", "halloween_share", "halloween_ghost_cuddle", "halloween_pumpkin_pat": "♡"
        case "wand", "orb", "cookie", "halloween_wand", "halloween_candy": "✧"
        case "surprise", "halloween_spell_pop": "!"
        case "disco", "conductor", "ballet", "halloween_dance_left", "halloween_dance_right", "halloween_twirl": "♪"
        case "nap", "yawn": "z"
        default: nil
        }
    }
}

enum ActionLibrary {
    private struct Manifest: Decodable { let actions: [PetAction] }
    static let all: [PetAction] = {
        let url = Bundle.main.url(forResource: "action-library", withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/action-library.json")
        do { return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).actions }
        catch { fatalError("Invalid action library: \(error)") }
    }()
    static let categories = all.reduce(into: [String]()) { if !$0.contains($1.category) { $0.append($1.category) } }
    static func action(_ index: Int) -> PetAction { all[all.indices.contains(index) ? index : 0] }
    static func indices(category: String) -> [Int] { all.indices.filter { all[$0].category == category } }
}

/// Costume pools are explicit: classic artwork never slips into a witch routine.
enum HalloweenTheme {
    static func isHalloween(_ action: PetAction) -> Bool { action.id.hasPrefix("halloween_") }
    static let indices = ActionLibrary.all.indices.filter { isHalloween(ActionLibrary.all[$0]) }
    static let classicIndices = ActionLibrary.all.indices.filter { !isHalloween(ActionLibrary.all[$0]) }
    static func index(_ suffix: String) -> Int {
        ActionLibrary.all.firstIndex { $0.id == "halloween_" + suffix } ?? 0
    }
    static var sleepyIndices: [Int] { [index("yawn"), index("rest"), index("full")] }
    static func wearingCostume(_ index: Int) -> Int {
        let action = ActionLibrary.action(index)
        if isHalloween(action) { return index }
        let suffix: String
        switch action.id {
        case "wave", "salute", "beckon", "breathe": suffix = "hat_hello"
        case "eat_rice", "mochi", "cookie": suffix = "cookie"
        case "shy_peek", "pout": suffix = "shy"
        case "happy_head_pat", "hug", "warm_towel": suffix = "ghost_cuddle"
        case "heart_gift", "finger_heart", "flower": suffix = "share"
        case "wand", "orb": suffix = "wand"
        case "surprise": suffix = "spell_pop"
        case "laugh": suffix = "giggle"
        case "broom_fly", "plush_ride", "balloon": suffix = "broom"
        case "nap", "pillow", "book_doze": suffix = "rest"
        case "yawn": suffix = "yawn"
        case "conductor": suffix = "dance_left"
        case "disco": suffix = "dance_right"
        case "ballet": suffix = "twirl"
        case "bow", "curtsy": suffix = "landing"
        default: suffix = "hat_hello"
        }
        return self.index(suffix)
    }
    static func displayIndex(_ action: Int, enabled: Bool, sleeping: Bool, dancing: Bool, time: Double) -> Int {
        guard enabled else { return sleeping ? 5 : action }
        if sleeping { return index("rest") }
        if dancing {
            let sequence = ["dance_left", "dance_right", "dance_left", "dance_right", "twirl", "twirl"]
            return index(sequence[Int(max(0, time) / 0.42) % sequence.count])
        }
        return wearingCostume(action)
    }
    static func choices(enabled: Bool, favorites: Set<String>, favoritesOnly: Bool) -> [Int] {
        let pool = enabled ? indices : classicIndices
        let matching = pool.filter { favorites.contains(ActionLibrary.all[$0].id) }
        return favoritesOnly && !matching.isEmpty ? matching : pool
    }
}

/// A shuffled bag visits each eligible action once before reshuffling. Changing
/// modes discards the old bag so a nap cannot leak into an awake-only selection.
struct ActionShuffle {
    private var pool: [Int] = []
    private var bag: [Int] = []
    mutating func next(in choices: [Int], avoiding current: Int) -> Int {
        let unique = Array(Set(choices)).sorted()
        guard !unique.isEmpty else { return current }
        if unique != pool { pool = unique; bag = [] }
        if bag.isEmpty { bag = pool.shuffled() }
        if bag.last == current, bag.count > 1 { bag.swapAt(bag.count - 1, 0) }
        return bag.removeLast()
    }
}

struct MotionSample {
    var x = 0.0, y = 0.0, angle = 0.0, scaleX = 1.0, scaleY = 1.0
}

enum PetMotion: String, Codable, CaseIterable {
    case breathe, bow, nod, float, hop, sway, bounce, swing, shimmy, peek
    func sample(at t: Double) -> MotionSample {
        switch self {
        case .breathe: return .init(y: -1.5 * sin(t * 1.7), scaleY: 1 + 0.012 * sin(t * 1.7))
        case .bow: return .init(y: 3 * (1 - cos(t * 2)), angle: 3 * sin(t * 2), scaleY: 0.97 + 0.03 * cos(t * 2))
        case .nod: return .init(y: 2 * sin(t * 3), angle: 2 * sin(t * 3), scaleY: 1 + 0.015 * sin(t * 3))
        case .float: return .init(x: 4 * sin(t * 1.5), y: -6 - 5 * sin(t * 1.8), angle: 3 * sin(t * 1.5))
        case .hop: return .init(y: -12 * abs(sin(t * 3.2)), angle: 3 * sin(t * 3.2), scaleX: 1 + 0.025 * cos(t * 6.4), scaleY: 1 - 0.025 * cos(t * 6.4))
        case .sway: return .init(x: 2 * sin(t * 2.2), angle: 5 * sin(t * 2.2))
        case .bounce: return .init(y: -4 * abs(sin(t * 4)), scaleX: 1 + 0.018 * cos(t * 8), scaleY: 1 - 0.025 * cos(t * 8))
        case .swing: return .init(x: 5 * sin(t * 2), angle: 6 * sin(t * 2))
        case .shimmy: return .init(x: 3 * sin(t * 7), y: -2 * abs(sin(t * 3.5)), angle: 3 * sin(t * 7))
        case .peek: return .init(x: 4 * sin(t * 1.8), y: 2 * (1 - cos(t * 1.8)), angle: 7 * sin(t * 1.8))
        }
    }
}
