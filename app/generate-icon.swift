import AppKit
import CoreText

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let s = CGFloat(size)
let context = NSGraphicsContext.current!.cgContext

// Dark rounded-rect background
let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.22, yRadius: s * 0.22)
NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
bgPath.fill()

// Draw the "G" centered using Core Text path for precise control
let fontSize = s * 0.52
let font = CTFontCreateWithName("Helvetica Neue Bold" as CFString, fontSize, nil)
var glyphs: [CGGlyph] = [0]
var chars: [UniChar] = [0x47] // "G"
CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 1)

// Get the glyph's actual path bounding box
if let glyphPath = CTFontCreatePathForGlyph(font, glyphs[0], nil) {
    let pathBounds = glyphPath.boundingBox

    // Center the glyph path in the icon
    let offsetX = (s - pathBounds.width) / 2 - pathBounds.origin.x
    let offsetY = (s - pathBounds.height) / 2 - pathBounds.origin.y

    context.saveGState()
    context.translateBy(x: offsetX, y: offsetY)

    // Fill the G
    context.addPath(glyphPath)
    context.setFillColor(NSColor(red: 0.50, green: 0.50, blue: 0.54, alpha: 1).cgColor)
    context.fillPath()

    context.restoreGState()
}

// Draw prohibition symbol
let prohibColor = NSColor(red: 0.88, green: 0.20, blue: 0.18, alpha: 0.92).cgColor
let lineWidth = s * 0.058
let inset = s * 0.15

let center = CGPoint(x: s / 2, y: s / 2)
let radius = s / 2 - inset

// Circle
context.setStrokeColor(prohibColor)
context.setLineWidth(lineWidth)
context.strokeEllipse(in: CGRect(
    x: center.x - radius, y: center.y - radius,
    width: radius * 2, height: radius * 2
).insetBy(dx: lineWidth / 2, dy: lineWidth / 2))

// Diagonal slash (upper-left to lower-right)
let innerRadius = radius - lineWidth / 2
let angle1 = CGFloat.pi * 0.75
let angle2 = -CGFloat.pi * 0.25
context.setLineCap(.round)
context.move(to: CGPoint(x: center.x + innerRadius * cos(angle1), y: center.y + innerRadius * sin(angle1)))
context.addLine(to: CGPoint(x: center.x + innerRadius * cos(angle2), y: center.y + innerRadius * sin(angle2)))
context.strokePath()

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to generate icon\n", stderr)
    exit(1)
}
try! pngData.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
