// Usage: swift make-icon.swift <mascot.png> <out.png>
// Draws the mascot on a warm rounded-square tile, 1024x1024.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let mascot = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon <mascot.png> <out.png>\n".utf8))
    exit(1)
}

let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// macOS icon grid: artwork inset ~100px with a ~185px corner radius.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.84, alpha: 1).setFill()
path.fill()

let m = NSRect(x: 512 - 270, y: 512 - 270, width: 540, height: 540)
mascot.draw(in: m, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()

if let data = rep.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: args[2]))
}
