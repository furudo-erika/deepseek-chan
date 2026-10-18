import SwiftUI
import AppKit

/// Render the exact production sprite view for offline visual acceptance.
@main struct RenderActions {
    @MainActor static func main() throws {
        for category in ActionLibrary.categories {
            let indices = ActionLibrary.indices(category: category)
            let content = VStack(spacing: 12) {
                Text(category).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(150)), count: 3), spacing: 12) {
                    ForEach(indices, id: \.self) { i in
                        let a = ActionLibrary.all[i]
                        VStack(spacing: 6) {
                            CompanionSprite(frame: a.frame, side: 140, artwork: a.atlas)
                            Text(a.name).font(.system(size: 12)).foregroundStyle(Color.ink)
                        }.padding(4).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.padding(20).frame(width: 510).background(Color.mist).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            guard let image = renderer.cgImage else { fatalError("Render failed") }
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            let slug = category.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "&", with: "and")
            try data.write(to: URL(fileURLWithPath: ".build/qa-actions-\(slug).png"))
        }
        print("Rendered all \(ActionLibrary.all.count) production sprite crops into \(ActionLibrary.categories.count) category sheets.")
    }
}
