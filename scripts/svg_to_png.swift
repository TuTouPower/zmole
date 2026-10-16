// Renders an SVG into a transparent RGBA PNG using the system ImageIO/AppKit
// SVG support (no third-party dependency). Used by scripts/build_app_icon.sh.
//
// Usage: swift scripts/svg_to_png.swift <source.svg> <output.png> <pixel-size>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let side = Int(arguments[3]), side > 0 else {
    FileHandle.standardError.write(Data("usage: svg_to_png <source.svg> <output.png> <pixel-size>\n".utf8))
    exit(64)
}

let source = arguments[1]
let destination = arguments[2]

guard let image = NSImage(contentsOfFile: source) else {
    FileHandle.standardError.write(Data("svg_to_png: cannot load \(source)\n".utf8))
    exit(1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("svg_to_png: cannot create bitmap\n".utf8))
    exit(1)
}
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
image.draw(
    in: NSRect(x: 0, y: 0, width: side, height: side),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("svg_to_png: cannot encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: destination))
print("svg_to_png: wrote \(destination) (\(side)x\(side), transparent)")
