import Foundation

/// One fixed screen-space anchor for an entire drag. Never feed the moving
/// window's local coordinates back into the next position calculation.
struct ScreenDrag {
    let pointerStart: CGPoint
    let windowStart: CGPoint
    func position(pointer: CGPoint) -> CGPoint {
        CGPoint(x: windowStart.x + pointer.x - pointerStart.x,
                y: windowStart.y + pointer.y - pointerStart.y)
    }
}

/// Both the SwiftUI layout and NSPanel placement use this character center.
/// Growing a speech/chat panel preserves the character's screen-space anchor.
enum PetPlacement {
    static func anchor(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height >= 560 ? 300 : size.height >= 440 ? 180 : 125)
    }
    static func origin(anchor: CGPoint, size: CGSize) -> CGPoint {
        let local = self.anchor(in: size)
        return CGPoint(x: anchor.x - local.x, y: anchor.y - local.y)
    }
    static func clamped(origin: CGPoint, size: CGSize, to screen: CGRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, screen.minX), max(screen.minX, screen.maxX - size.width)),
                y: min(max(origin.y, screen.minY), max(screen.minY, screen.maxY - size.height)))
    }
    static func screen(for anchor: CGPoint, frames: [CGRect]) -> CGRect? {
        if let containing = frames.first(where: { $0.contains(anchor) }) { return containing }
        return frames.min { a, b in
            func distance(_ r: CGRect) -> CGFloat {
                let dx = max(r.minX - anchor.x, 0, anchor.x - r.maxX)
                let dy = max(r.minY - anchor.y, 0, anchor.y - r.maxY)
                return dx * dx + dy * dy
            }
            return distance(a) < distance(b)
        }
    }
}
