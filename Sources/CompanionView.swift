import SwiftUI
import AppKit

extension Color {
    static let ocean = Color(red: 0.12, green: 0.35, blue: 0.69)
    static let ink = Color(red: 0.12, green: 0.22, blue: 0.32)
    static let mist = Color(red: 0.91, green: 0.96, blue: 0.98)
}

enum CompanionArtwork {
    private static var cache: [String: NSImage] = [:]
    static func load(_ name: String) -> NSImage {
        if let cached = cache[name] { return cached }
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/\(name.hasPrefix("actions-") ? "actions/" : "")\(name).png")
        guard let image = NSImage(contentsOf: url) else { fatalError("Missing bundled companion artwork") }
        cache[name] = image
        return image
    }
    static let atlas = load("deepseek-chan-soft-atlas")
    static let dance = load("deepseek-chan-dance-atlas")
    static let daily = load("deepseek-chan-daily-atlas")
    static let layouts: [String: [[CGFloat]]] = {
        let url = Bundle.main.url(forResource: "atlas-layout", withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/atlas-layout.json")
        return try! JSONDecoder().decode([String: [[CGFloat]]].self, from: Data(contentsOf: url))
    }()
    // Explicit crop notches exclude neighboring cells where row silhouettes
    // interleave. The original transparent artwork remains unmodified.
    static let cutouts: [String: [[CGFloat]]] = {
        let url = Bundle.main.url(forResource: "atlas-cutouts", withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/atlas-cutouts.json")
        return try! JSONDecoder().decode([String: [[CGFloat]]].self, from: Data(contentsOf: url))
    }()
    static let regions: [String: [[CGFloat]]] = {
        let url = Bundle.main.url(forResource: "atlas-regions", withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/atlas-regions.json")
        return try! JSONDecoder().decode([String: [[CGFloat]]].self, from: Data(contentsOf: url))
    }()
}

private struct SpriteOutline: Shape {
    var points: [[CGFloat]]
    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path(rect) }
        var path = Path()
        path.move(to: CGPoint(x: first[0] * rect.width, y: first[1] * rect.height))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point[0] * rect.width, y: point[1] * rect.height)) }
        path.closeSubpath()
        return path
    }
}

private struct SpriteRegion: Shape {
    var cutouts: [[CGFloat]]
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for cut in cutouts {
            path.addRect(CGRect(x: cut[0] * rect.width, y: cut[1] * rect.height,
                                width: cut[2] * rect.width, height: cut[3] * rect.height))
        }
        return path
    }
}

/// Clips the original transparent atlas directly. No resaved or flattened sprites.
struct CompanionSprite: View {
    let frame: Int
    let side: CGFloat
    var dance = false
    var daily = false
    var artwork: String? = nil
    var body: some View {
        let name = artwork ?? (daily ? "deepseek-chan-daily-atlas" : dance ? "deepseek-chan-dance-atlas" : "deepseek-chan-soft-atlas")
        let rect = CompanionArtwork.layouts[name]?[frame] ?? [CGFloat(frame % 2) / 2, CGFloat(frame / 2) / 2, 0.5, 0.5]
        let scale = side / max(rect[2], rect[3])
        Image(nsImage: CompanionArtwork.load(name))
            .resizable().interpolation(.high)
            .frame(width: scale, height: scale)
            .offset(x: -rect[0] * scale, y: -rect[1] * scale)
            .frame(width: rect[2] * scale, height: rect[3] * scale, alignment: .topLeading)
            .clipped()
            .clipShape(SpriteRegion(cutouts: CompanionArtwork.cutouts["\(name):\(frame)"] ?? []), style: FillStyle(eoFill: true))
            .clipShape(SpriteOutline(points: CompanionArtwork.regions["\(name):\(frame)"] ?? []))
            .frame(width: side, height: side, alignment: .bottom)
    }
}

struct CompanionView: View {
    var knocking = false
    var sleeping = false
    var still = false
    var dancing = false
    var action = 0
    var replay = 0
    var calm = false
    var halloween = false
    @State private var motionStart = Date()
    @State private var frozenElapsed: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: calm && !dancing ? 1.0 / 12 : 1.0 / 20, paused: reduceMotion || still)) { timeline in
            let t = reduceMotion ? 0 : max(0, frozenElapsed ?? timeline.date.timeIntervalSince(motionStart))
            let selected = ActionLibrary.action(HalloweenTheme.displayIndex(action, enabled: halloween, sleeping: sleeping, dancing: dancing || knocking, time: t))
            let motion = reduceMotion ? MotionSample() : selected.sample(at: calm ? t * 0.65 : t)
            let strength = calm ? 0.3 : 1.0
            let useDance = dancing && Int(t / 4) % 3 != 2
            let useDaily = halloween || sleeping || (!knocking && !dancing)
            let frame = useDaily ? selected.frame : useDance ? Int(t / 0.32) % 4 : (Int(t / 0.38) % 2 == 0 ? 1 : 2)
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    CompanionSprite(frame: frame, side: side * 0.9, dance: useDance, artwork: useDaily ? selected.atlas : nil)
                        .scaleEffect(x: dancing ? 1 : 1 + (motion.scaleX - 1) * strength, y: dancing ? 1 : 1 + (motion.scaleY - 1) * strength, anchor: .bottom)
                        .rotationEffect(.degrees(reduceMotion ? 0 : dancing ? sin(t * 6) * 8 : motion.angle * strength), anchor: .bottom)
                        .offset(x: dancing && !reduceMotion ? sin(t * 3) * 10 : motion.x * strength,
                                y: dancing && !reduceMotion ? -abs(sin(t * 6)) * 18 : motion.y * strength)
                    if dancing {
                        Text("♪").font(.system(size: side * 0.12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ocean).offset(x: -side * 0.43, y: -side * 0.15)
                        Text("♡").font(.system(size: side * 0.1, weight: .bold, design: .rounded))
                            .foregroundStyle(.pink.opacity(0.8)).offset(x: side * 0.4, y: -side * 0.35)
                    }
                    if sleeping {
                        Text("z z Z").font(.system(size: side * 0.065, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ocean.opacity(0.6))
                            .offset(x: side * 0.34, y: -side * 0.25)
                    }
                    if !sleeping && !dancing && !knocking && !reduceMotion && t < 2.4, let symbol = selected.reactionSymbol {
                        Text(symbol).font(.system(size: side * 0.10, weight: .semibold, design: .rounded))
                            .foregroundStyle(symbol == "♡" ? Color.pink.opacity(0.8) : Color.ocean.opacity(0.8))
                            .offset(x: side * 0.35, y: -side * 0.23 - min(t, 2.4) * 9 * strength)
                            .opacity(min(1, t * 5) * max(0, 1 - t / 2.4))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onChange(of: still) { _, value in
            if value { frozenElapsed = Date().timeIntervalSince(motionStart) }
            else if let elapsed = frozenElapsed { motionStart = Date().addingTimeInterval(-elapsed); frozenElapsed = nil }
        }
        .onChange(of: action) { _, _ in motionStart = Date(); if still { frozenElapsed = 0 } }
        .onChange(of: replay) { _, _ in motionStart = Date(); if still { frozenElapsed = 0 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sleeping ? "DeepSeek-chan sleeping" : dancing ? "DeepSeek-chan dancing, waving and making hearts" : knocking ? "DeepSeek-chan tapping a bell" : "DeepSeek-chan: \(ActionLibrary.action(action).name)")
    }
}
