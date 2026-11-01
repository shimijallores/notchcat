import SwiftUI
import AppKit

/// 5x7 dot-matrix glyphs for the digits and the colon.
enum DotFont {
    static let rows = 7

    static func glyph(_ c: Character) -> [String] {
        switch c {
        case "0": return ["01110", "10001", "10011", "10101", "11001", "10001", "01110"]
        case "1": return ["00100", "01100", "00100", "00100", "00100", "00100", "01110"]
        case "2": return ["01110", "10001", "00001", "00010", "00100", "01000", "11111"]
        case "3": return ["11110", "00001", "00001", "01110", "00001", "00001", "11110"]
        case "4": return ["00010", "00110", "01010", "10010", "11111", "00010", "00010"]
        case "5": return ["11111", "10000", "11110", "00001", "00001", "10001", "01110"]
        case "6": return ["00110", "01000", "10000", "11110", "10001", "10001", "01110"]
        case "7": return ["11111", "00001", "00010", "00100", "01000", "01000", "01000"]
        case "8": return ["01110", "10001", "10001", "01110", "10001", "10001", "01110"]
        case "9": return ["01110", "10001", "10001", "01111", "00001", "00010", "01100"]
        case ":": return ["0", "1", "0", "0", "0", "1", "0"]
        default:  return Array(repeating: "00000", count: 7)
        }
    }

    /// Total columns for a string, with one blank column between glyphs.
    static func columns(for text: String) -> Int {
        let widths = text.map { glyph($0)[0].count }
        return widths.reduce(0, +) + max(0, widths.count - 1)
    }
}

enum PillMetrics {
    static func pitch(height: CGFloat) -> CGFloat { height * 0.62 / CGFloat(DotFont.rows) }
    static func hPad(height: CGFloat) -> CGFloat { height * 0.62 }

    static func width(for text: String, height: CGFloat) -> CGFloat {
        CGFloat(DotFont.columns(for: text)) * pitch(height: height) + hPad(height: height) * 2
    }
}

/// Draws text as lit dots over a faint grid of unlit ones.
struct DotMatrixText: View {
    let text: String
    let pitch: CGFloat
    var lit: Color = .white
    var unlitOpacity: Double = 0.10

    var body: some View {
        let cols = DotFont.columns(for: text)
        Canvas { ctx, size in
            let radius = pitch * 0.36
            let top = (size.height - CGFloat(DotFont.rows) * pitch) / 2
            var col = 0
            for ch in text {
                let glyph = DotFont.glyph(ch)
                let w = glyph[0].count
                for (r, row) in glyph.enumerated() {
                    for (c, bit) in row.enumerated() {
                        let cx = (CGFloat(col + c) + 0.5) * pitch
                        let cy = top + (CGFloat(r) + 0.5) * pitch
                        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                        if bit == "1" {
                            ctx.fill(Path(ellipseIn: rect), with: .color(lit))
                        } else if w > 1 {
                            ctx.fill(Path(ellipseIn: rect), with: .color(lit.opacity(unlitOpacity)))
                        }
                    }
                }
                col += w + 1
            }
        }
        .frame(width: CGFloat(cols) * pitch, height: CGFloat(DotFont.rows) * pitch + pitch * 2)
    }
}

/// Drives the pill's morph in and out of the notch's right shoulder.
@MainActor
final class PillUIState: ObservableObject {
    @Published var shown = false
}

/// The countdown capsule docked to the right shoulder of the notch.
struct PillView: View {
    @ObservedObject var timer: FocusTimer
    @ObservedObject var ui: PillUIState
    let height: () -> CGFloat
    let onTap: () -> Void

    var body: some View {
        let h = height()
        let text = timer.remaining.clockString

        Group {
            if timer.state == .finished {
                // Only the finished state animates; every other state redraws once per second at most.
                TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                    capsule(text: text, h: h, blinkOn: Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0)
                }
            } else {
                capsule(text: text, h: h, blinkOn: true)
            }
        }
        .frame(width: PillMetrics.width(for: text, height: h), height: h)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        // Grows horizontally out of the notch edge (leading side) rather than fading in from nowhere.
        .scaleEffect(x: ui.shown ? 1 : 0.12, y: ui.shown ? 1 : 0.7, anchor: .leading)
        .opacity(ui.shown ? 1 : 0)
        .animation(.spring(duration: 0.30, bounce: 0.1), value: ui.shown)
    }

    private func capsule(text: String, h: CGFloat, blinkOn: Bool) -> some View {
        let finished = timer.state == .finished
        let paused = timer.state == .paused
        return ZStack {
            Capsule().fill(Color.black)
            Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            DotMatrixText(text: text,
                          pitch: PillMetrics.pitch(height: h),
                          lit: finished ? Theme.amber : .white,
                          unlitOpacity: 0.09)
                .opacity(finished ? (blinkOn ? 1 : 0.25) : (paused ? 0.55 : 1))
        }
    }
}

/// Lets the first click act immediately on our non-activating panels.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
