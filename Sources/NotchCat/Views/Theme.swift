import SwiftUI
import AppKit

enum Theme {
    // Shell
    static let housing = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let housingRaised = Color(red: 0.115, green: 0.115, blue: 0.125)

    // Card pastels
    static let mint = Color(red: 0.745, green: 0.855, blue: 0.765)
    static let lavender = Color(red: 0.800, green: 0.775, blue: 0.930)

    // Ink on pastels, and the accent taken from the mascot's golden eye
    static let ink = Color(red: 0.105, green: 0.115, blue: 0.110)
    static let amber = Color(red: 0.988, green: 0.757, blue: 0.314)

    static let cardRadius: CGFloat = 18
}

/// Soft paper grain, generated once and tiled.
enum Grain {
    static let image: NSImage = {
        let px = 96
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.bitmapData else { return NSImage() }
        var rng = SystemRandomNumberGenerator()
        for i in 0..<(px * px) {
            let a = UInt8.random(in: 0...26, using: &rng)
            let white = Bool.random(using: &rng)
            let v: UInt8 = white ? a : 0          // premultiplied
            data[i * 4 + 0] = v
            data[i * 4 + 1] = v
            data[i * 4 + 2] = v
            data[i * 4 + 3] = a
        }
        let image = NSImage(size: NSSize(width: px / 2, height: px / 2))
        image.addRepresentation(rep)
        return image
    }()
}

/// A pastel card with grain, used for every module in the housing.
struct CardBackground: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(color)
                    Image(nsImage: Grain.image)
                        .resizable(resizingMode: .tile)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .foregroundStyle(Theme.ink)
    }
}

extension View {
    func card(_ color: Color) -> some View { modifier(CardBackground(color: color)) }
}

/// The cat mascot (brand/zi-mascot.png, bundled as mascot.png).
struct MascotView: View {
    var size: CGFloat

    private static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "cat.fill").resizable().scaledToFit()
                .frame(width: size, height: size).foregroundStyle(Theme.amber)
        }
    }
}
