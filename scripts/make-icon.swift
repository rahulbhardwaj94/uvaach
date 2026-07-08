// Generates the LokVaani app icon without any design tools:
//   swift scripts/make-icon.swift
// Draws a white lightning bolt (speed) flanked by voice bars (vaani) on a
// dark squircle, writes Resources/AppIcon.icns (via iconutil) and
// assets/icon.png for the README.
import AppKit

let canvas: CGFloat = 1024

func draw(into size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = size / canvas // scale factor from the 1024 design grid

    // Background squircle (macOS icon grid: ~10% margin, ~22% corner radius).
    let bgRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
    let gradient = NSGradient(
        starting: NSColor(white: 0.16, alpha: 1),
        ending: NSColor(white: 0.02, alpha: 1)
    )!
    gradient.draw(in: squircle, angle: -90)
    NSColor(white: 1, alpha: 0.10).setStroke()
    squircle.lineWidth = max(1, 6 * s)
    squircle.stroke()

    // Lightning bolt, centered. Points on the 1024 grid (y-up).
    let bolt = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [
        (562, 800), (386, 500), (492, 500), (438, 240), (638, 556), (524, 556),
    ]
    bolt.move(to: NSPoint(x: pts[0].0 * s, y: pts[0].1 * s))
    for p in pts.dropFirst() { bolt.line(to: NSPoint(x: p.0 * s, y: p.1 * s)) }
    bolt.close()
    bolt.lineJoinStyle = .round
    NSColor.white.setFill()
    bolt.fill()
    NSColor.white.setStroke()
    bolt.lineWidth = 18 * s
    bolt.stroke()

    // Voice bars either side of the bolt.
    func bar(x: CGFloat, height: CGFloat, alpha: CGFloat) {
        let rect = NSRect(
            x: (x - 14) * s, y: (520 - height / 2) * s,
            width: 28 * s, height: height * s
        )
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14 * s, yRadius: 14 * s).fill()
    }
    bar(x: 244, height: 120, alpha: 0.40)
    bar(x: 312, height: 210, alpha: 0.65)
    bar(x: 712, height: 210, alpha: 0.65)
    bar(x: 780, height: 120, alpha: 0.40)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(
    at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for (suffix, scale) in [("", 1), ("@2x", 2)] {
        let px = CGFloat(base * scale)
        let data = draw(into: px).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
try draw(into: 512).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("assets/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path,
    "-o", root.appendingPathComponent("Resources/AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("Wrote Resources/AppIcon.icns and assets/icon.png")
