import SwiftUI

/// Large seven-segment style clock for the timer card.
struct SevenSegmentClock: View {
    let text: String
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    var color: Color = Theme.ink

    private static let ratio: CGFloat = 0.52      // digit width / height
    private static let spacing: CGFloat = 0.11    // gap / height
    private static let colon: CGFloat = 0.20      // colon width / height
    private static let skew: CGFloat = 0.10

    /// Width of the text at a height of 1.
    private func unitWidth() -> CGFloat {
        var w: CGFloat = 0
        for (i, ch) in text.enumerated() {
            w += ch == ":" ? Self.colon : Self.ratio
            if i < text.count - 1 { w += Self.spacing }
        }
        return w + Self.skew
    }

    var body: some View {
        let h = min(maxHeight, maxWidth / max(unitWidth(), 0.01))
        let t = h * 0.13
        Canvas { ctx, size in
            ctx.transform = CGAffineTransform(a: 1, b: 0, c: -Self.skew, d: 1, tx: Self.skew * h, ty: 0)
            var x: CGFloat = 0
            for ch in text {
                if ch == ":" {
                    let w = h * Self.colon
                    let d = t * 1.05
                    for fy in [0.32, 0.68] {
                        let r = CGRect(x: x + (w - d) / 2, y: h * fy - d / 2, width: d, height: d)
                        ctx.fill(Path(roundedRect: r, cornerRadius: d * 0.2), with: .color(color))
                    }
                    x += w + h * Self.spacing
                } else {
                    let w = h * Self.ratio
                    let mask = Self.mask(for: ch)
                    for seg in 0..<7 {
                        let path = Self.segment(seg, w: w, h: h, t: t, origin: x)
                        let on = mask & (1 << seg) != 0
                        ctx.fill(path, with: .color(color.opacity(on ? 1 : 0.07)))
                    }
                    x += w + h * Self.spacing
                }
            }
        }
        .frame(width: unitWidth() * h, height: h)
    }

    // Bits: a b c d e f g
    private static func mask(for c: Character) -> Int {
        switch c {
        case "0": return 0b0111111
        case "1": return 0b0000110
        case "2": return 0b1011011
        case "3": return 0b1001111
        case "4": return 0b1100110
        case "5": return 0b1101101
        case "6": return 0b1111101
        case "7": return 0b0000111
        case "8": return 0b1111111
        case "9": return 0b1101111
        default: return 0
        }
    }

    private static func segment(_ index: Int, w: CGFloat, h: CGFloat, t: CGFloat, origin x: CGFloat) -> Path {
        let gap = t * 0.18
        let left = x + t / 2, right = x + w - t / 2
        let top = t / 2, mid = h / 2, bottom = h - t / 2
        switch index {
        case 0: return hSeg(x0: left + gap, x1: right - gap, y: top, t: t)      // a
        case 1: return vSeg(x: right, y0: top + gap, y1: mid - gap, t: t)       // b
        case 2: return vSeg(x: right, y0: mid + gap, y1: bottom - gap, t: t)    // c
        case 3: return hSeg(x0: left + gap, x1: right - gap, y: bottom, t: t)  // d
        case 4: return vSeg(x: left, y0: mid + gap, y1: bottom - gap, t: t)     // e
        case 5: return vSeg(x: left, y0: top + gap, y1: mid - gap, t: t)        // f
        default: return hSeg(x0: left + gap, x1: right - gap, y: mid, t: t)     // g
        }
    }

    private static func hSeg(x0: CGFloat, x1: CGFloat, y: CGFloat, t: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x0 + t / 2, y: y - t / 2))
        p.addLine(to: CGPoint(x: x1 - t / 2, y: y - t / 2))
        p.addLine(to: CGPoint(x: x1, y: y))
        p.addLine(to: CGPoint(x: x1 - t / 2, y: y + t / 2))
        p.addLine(to: CGPoint(x: x0 + t / 2, y: y + t / 2))
        p.closeSubpath()
        return p
    }

    private static func vSeg(x: CGFloat, y0: CGFloat, y1: CGFloat, t: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y0))
        p.addLine(to: CGPoint(x: x + t / 2, y: y0 + t / 2))
        p.addLine(to: CGPoint(x: x + t / 2, y: y1 - t / 2))
        p.addLine(to: CGPoint(x: x, y: y1))
        p.addLine(to: CGPoint(x: x - t / 2, y: y1 - t / 2))
        p.addLine(to: CGPoint(x: x - t / 2, y: y0 + t / 2))
        p.closeSubpath()
        return p
    }
}
