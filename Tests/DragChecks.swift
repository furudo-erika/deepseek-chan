import Foundation
import CoreGraphics

@main struct DragChecks {
    static func main() {
        let drag = ScreenDrag(pointerStart: CGPoint(x: 500, y: 500), windowStart: CGPoint(x: 400, y: 400))
        // After each move the pointer sits at the same local window coordinate.
        // Local-coordinate feedback would alternate between movement and zero.
        let screenEvents = [CGPoint(x: 510, y: 510), CGPoint(x: 520, y: 520), CGPoint(x: 530, y: 530), CGPoint(x: 520, y: 520)]
        let expected = [CGPoint(x: 410, y: 410), CGPoint(x: 420, y: 420), CGPoint(x: 430, y: 430), CGPoint(x: 420, y: 420)]
        for (event, position) in zip(screenEvents, expected) {
            precondition(drag.position(pointer: event) == position, "Moving the window must not change the drag anchor")
        }
        precondition(drag.position(pointer: CGPoint(x: 520, y: 520)) == expected.last!, "A stationary pointer must not oscillate")
        let leftDisplay = ScreenDrag(pointerStart: CGPoint(x: -800, y: 200), windowStart: CGPoint(x: -900, y: 100))
        precondition(leftDisplay.position(pointer: CGPoint(x: -750, y: 150)) == CGPoint(x: -850, y: 50), "Negative screen coordinates must work")
        let anchor = CGPoint(x: -700, y: 430)
        for size in [CGSize(width: 240, height: 250), CGSize(width: 320, height: 350), CGSize(width: 320, height: 440), CGSize(width: 360, height: 490), CGSize(width: 360, height: 500), CGSize(width: 360, height: 520), CGSize(width: 360, height: 560)] {
            let origin = PetPlacement.origin(anchor: anchor, size: size)
            let local = PetPlacement.anchor(in: size)
            precondition(CGPoint(x: origin.x + local.x, y: origin.y + local.y) == anchor, "Idle, bubble and chat must keep the same character center")
        }
        let left = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1512, height: 900)
        precondition(PetPlacement.screen(for: anchor, frames: [left, right]) == left, "A bubble must stay on the pet's display, not chase the pointer")
        precondition(PetPlacement.screen(for: anchor, frames: [right]) == right, "Recover when a display is removed")
        let safe = PetPlacement.clamped(origin: CGPoint(x: -1600, y: -200), size: CGSize(width: 360, height: 440), to: left)
        precondition(safe == CGPoint(x: -1440, y: -100))
        let edge = PetPlacement.clamped(origin: CGPoint(x: 1450, y: 850), size: CGSize(width: 360, height: 490), to: right)
        precondition(edge == CGPoint(x: 1152, y: 410))
        let tiny = PetPlacement.clamped(origin: .zero, size: CGSize(width: 360, height: 490), to: CGRect(x: 5, y: 10, width: 200, height: 100))
        precondition(tiny == CGPoint(x: 5, y: 10), "Oversized windows must not invert clamp bounds")
        print("PASS: continuous movement, reversal, stationary pointer, and negative-screen coordinates")
        print("PASS: stable idle/bubble/chat anchor, display selection/removal, edge clamping and small displays")
    }
}
