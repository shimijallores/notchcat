import SwiftUI
import AppKit

enum Theme {
    // Shell
    static let housing = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let housingRaised = Color(red: 0.115, green: 0.115, blue: 0.125)

    // Card pastels
    static let mint = Color(red: 0.745, green: 0.855, blue: 0.765)
    static let lavender = Color(red: 0.800, green: 0.775, blue: 0.930)
    static let sand = Color(red: 0.850, green: 0.820, blue: 0.610)
    static let slate = Color(red: 0.640, green: 0.710, blue: 0.800)

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
    var radius: CGFloat = Theme.cardRadius
    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
                    if settings.data.paperGrain {
                        Image(nsImage: Grain.image)
                            .resizable(resizingMode: .tile)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                            .allowsHitTesting(false)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
    }
}

extension View {
    func card(_ color: Color, radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(color: color, radius: radius))
    }
}

/// The cat mascot. Looked up without `Bundle.module`, whose generated accessor calls fatalError when
/// its resource bundle is missing (which is the case inside the packaged .app).
enum Mascot {
    static let image: NSImage? = {
        let name = "mascot", ext = "png"

        // 1. Packaged app: build-app.sh copies it into Contents/Resources.
        if let url = Bundle.main.url(forResource: name, withExtension: ext), let image = NSImage(contentsOf: url) {
            return image
        }
        // 2. Running from Xcode / `swift run`: SwiftPM puts the resource bundle next to the executable.
        let beside = [Bundle.main.executableURL?.deletingLastPathComponent(), Bundle.main.bundleURL.deletingLastPathComponent(), Bundle.main.bundleURL]
        for dir in beside.compactMap({ $0 }) {
            let bundle = dir.appendingPathComponent("NotchCat_NotchCat.bundle")
            if let b = Bundle(url: bundle), let url = b.url(forResource: name, withExtension: ext),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }()
}

/// The cat mascot (brand/zi-mascot.png, bundled as mascot.png).
struct MascotView: View {
    var size: CGFloat

    var body: some View {
        if let image = Mascot.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "cat.fill").resizable().scaledToFit()
                .frame(width: size, height: size).foregroundStyle(Theme.amber)
        }
    }
}
