import AppKit

// Renders the Stage app icon: a dark tile with the persona sidebar and a docked Computer window.
// Usage: MakeIcon <output.png> [size]
@main
enum MakeIcon {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("usage: MakeIcon <output.png> [size]"); exit(2) }
        let size = args.count >= 3 ? Int(args[2]) ?? 1024 : 1024
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        draw(in: context)
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func draw(in ctx: CGContext) {
        // macOS icon grid: 824pt tile centered on a 1024 canvas, with a soft drop shadow.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = rounded(tile, 185)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
        ctx.addPath(tilePath)
        ctx.setFillColor(color(0x1B1A18))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let background = CGGradient(colorsSpace: space, colors: [color(0x34312C), color(0x1B1A18)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

        // Spotlight falling on the docked window.
        let light = CGGradient(colorsSpace: space, colors: [color(0xF6D9D2, 0.30), color(0xF6D9D2, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(light, startCenter: CGPoint(x: 640, y: 600), startRadius: 0,
                               endCenter: CGPoint(x: 640, y: 560), endRadius: 430, options: [])

        // Sidebar: one row per persona, the first one selected.
        let personas: [UInt32] = [0xD9553F, 0x3F8F5E, 0x4F6FD1]
        for (index, hex) in personas.enumerated() {
            let y = 690 - CGFloat(index) * 130
            if index == 0 {
                ctx.addPath(rounded(CGRect(x: 168, y: y - 36, width: 196, height: 104), 26))
                ctx.setFillColor(color(0x2C2A26))
                ctx.fillPath()
                ctx.addPath(rounded(CGRect(x: 168, y: y - 22, width: 12, height: 76), 6))
                ctx.setFillColor(color(hex))
                ctx.fillPath()
            }
            ctx.addPath(rounded(CGRect(x: 204, y: y + 4, width: 30, height: 30), 8))
            ctx.setFillColor(color(hex))
            ctx.fillPath()
            ctx.addPath(rounded(CGRect(x: 250, y: y + 10, width: 92, height: 18), 9))
            ctx.setFillColor(color(0xECE8E1, index == 0 ? 0.9 : 0.45))
            ctx.fillPath()
            ctx.addPath(rounded(CGRect(x: 250, y: y - 18, width: 62, height: 14), 7))
            ctx.setFillColor(color(0x8F8A80, index == 0 ? 0.8 : 0.4))
            ctx.fillPath()
        }

        // Docked Computer window.
        let window = CGRect(x: 400, y: 236, width: 452, height: 552)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.45))
        ctx.addPath(rounded(window, 44))
        ctx.setFillColor(color(0xF7F4EF))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(rounded(window, 44))
        ctx.clip()
        ctx.setFillColor(color(0xD9553F))
        ctx.fill(CGRect(x: window.minX, y: window.maxY - 14, width: window.width, height: 14))
        ctx.restoreGState()

        for (index, hex) in [UInt32(0xEE6A5F), 0xF5BF4F, 0x61C554].enumerated() {
            ctx.addEllipse(in: CGRect(x: 436 + CGFloat(index) * 40, y: 724, width: 24, height: 24))
            ctx.setFillColor(color(hex))
            ctx.fillPath()
        }

        // Chat: a question bubble on the right, an answer card on the left.
        ctx.addPath(rounded(CGRect(x: 610, y: 618, width: 204, height: 52), 26))
        ctx.setFillColor(color(0xF6D9D2))
        ctx.fillPath()
        ctx.addPath(rounded(CGRect(x: 438, y: 300, width: 376, height: 280), 30))
        ctx.setFillColor(color(0xFDFBF8))
        ctx.fillPath()
        ctx.addPath(rounded(CGRect(x: 438, y: 300, width: 376, height: 280), 30))
        ctx.setStrokeColor(color(0xE6E0D6))
        ctx.setLineWidth(4)
        ctx.strokePath()
        for (index, width) in [CGFloat(260), 300, 210].enumerated() {
            ctx.addPath(rounded(CGRect(x: 476, y: 512 - CGFloat(index) * 64, width: width, height: 22), 11))
            ctx.setFillColor(color(index == 0 ? 0x24221F : 0xC9C2B6, index == 0 ? 0.85 : 1))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}
