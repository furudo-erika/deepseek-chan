import AppKit
import SwiftUI

@main struct GenerateIcon {
    @MainActor static func main() {
        let artwork = ZStack {
            RoundedRectangle(cornerRadius: 220).fill(LinearGradient(colors: [.white, .mist], startPoint: .topLeading, endPoint: .bottomTrailing))
            CompanionView(still: true).frame(width: 950, height: 950).offset(y: 10)
        }.frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: artwork)
        guard let cg = renderer.cgImage else { fatalError("Icon rendering failed") }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
