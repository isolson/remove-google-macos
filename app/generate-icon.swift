import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let s = CGFloat(size)

// Dark rounded-rect background
let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.22, yRadius: s * 0.22)
NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
bgPath.fill()

// Draw the Google "G" — large, centered, slightly muted
let fontSize = s * 0.58
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let gAttrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
]
let gStr = NSAttributedString(string: "G", attributes: gAttrs)
let gSize = gStr.size()
let gOrigin = NSPoint(
    x: (s - gSize.width) / 2,
    y: (s - gSize.height) / 2 - s * 0.01
)
gStr.draw(at: gOrigin)

// Draw prohibition circle (red, slightly transparent)
let context = NSGraphicsContext.current!.cgContext
let prohibColor = NSColor(red: 0.90, green: 0.22, blue: 0.20, alpha: 0.92)
let lineWidth = s * 0.065
let inset = s * 0.12
let circleRect = bgRect.insetBy(dx: inset, dy: inset)

// Circle
context.setStrokeColor(prohibColor.cgColor)
context.setLineWidth(lineWidth)
context.strokeEllipse(in: circleRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))

// Diagonal slash (top-left to bottom-right)
let center = CGPoint(x: s / 2, y: s / 2)
let radius = (s / 2 - inset) - lineWidth / 2
let angle1 = CGFloat.pi * 0.75   // 135° (upper-left)
let angle2 = -CGFloat.pi * 0.25  // -45° (lower-right)
context.setLineCap(.round)
context.move(to: CGPoint(x: center.x + radius * cos(angle1), y: center.y + radius * sin(angle1)))
context.addLine(to: CGPoint(x: center.x + radius * cos(angle2), y: center.y + radius * sin(angle2)))
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
