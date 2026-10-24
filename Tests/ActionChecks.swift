import Foundation

@main struct ActionChecks {
    static func main() throws {
        let all = ActionLibrary.all
        precondition(all.count == 285)
        precondition(Set(all.map(\.id)).count == all.count)
        precondition(Set(all.map { "\($0.atlas):\($0.frame)" }).count == all.count, "No duplicated artwork counts")
        precondition(ActionLibrary.categories.count == 32)
        let trophy = all.first { $0.id == "trophy" }!
        precondition(trophy.matches("  TINY   victory  "))
        precondition(trophy.matches("trophy") && trophy.matches("happy victory"))
        precondition(trophy.matches("  ") && !trophy.matches("missing action"))
        precondition(all.first { $0.id == "kiss" }!.matches("啾"))
        let layouts = try JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: URL(fileURLWithPath: "Assets/atlas-layout.json")))
        let regions = try JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: URL(fileURLWithPath: "Assets/atlas-regions.json")))
        precondition(regions.count == 171)
        for action in all {
            precondition(!action.line.isEmpty && action.line.count < 60)
            precondition((0..<9).contains(action.frame))
            let rect = layouts[action.atlas]![action.frame]
            precondition(rect.count == 4 && rect[0] >= 0 && rect[1] >= 0 && rect[2] > 0 && rect[3] > 0)
            precondition(rect[0] + rect[2] <= 1.000001 && rect[1] + rect[3] <= 1.000001)
            let path = "Assets/" + (action.atlas.hasPrefix("actions-") ? "actions/" : "") + action.atlas + ".png"
            precondition(FileManager.default.fileExists(atPath: path))
            if action.atlas.hasPrefix("actions-extra-") || HalloweenTheme.isHalloween(action) {
                let outline = regions["\(action.atlas):\(action.frame)"]!
                precondition(outline.count >= 4)
                precondition(outline.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } })
            }
        }
        for id in ["kite_flying", "heart_dance"] {
            let action = all.first { $0.id == id }!
            let frames = Set((0..<30).map { action.animationFrame(at: Double($0) * 0.2) })
            precondition(frames.count == 3, "Each scene cycles its three drawn keyframes")
            precondition(action.animationFrame(at: -1) == action.frame)
        }
        var shuffle = ActionShuffle()
        var current = 0
        let choices = Array(all.indices)
        for _ in 0..<5 {
            var seen: Set<Int> = []
            for _ in choices {
                let next = shuffle.next(in: choices, avoiding: current)
                precondition(next != current, "No immediate repeats across bag boundaries")
                precondition(seen.insert(next).inserted, "Every action once per cycle")
                current = next
            }
            precondition(seen == Set(choices))
        }
        for _ in 0..<20 { precondition([7, 42].contains(shuffle.next(in: [7, 42], avoiding: current))) }
        precondition(shuffle.next(in: [77], avoiding: 77) == 77)
        precondition(shuffle.next(in: [], avoiding: 77) == 77)
        for motion in PetMotion.allCases {
            for step in 0..<100 {
                let m = motion.sample(at: Double(step) / 10)
                precondition(m.x.isFinite && m.y.isFinite && m.angle.isFinite)
                precondition(abs(m.x) <= 10 && abs(m.y) <= 18 && abs(m.angle) <= 8)
                precondition((0.9...1.1).contains(m.scaleX) && (0.9...1.1).contains(m.scaleY))
            }
        }
        print("PASS: 285 unique actions/artwork cells, 32 categories, assets/crops, five full shuffle cycles, pool changes, empty/single favorites, bounded motion")
    }
}
