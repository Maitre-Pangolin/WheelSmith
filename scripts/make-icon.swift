// Renders Support/AppIcon.icns from LogoMark. Run ./scripts/make-icon.sh after changing the mark.
// Compiled together with Sources/WheelSmith/LogoMark.swift, so the app icon and the menu bar icon
// share one shape.
import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 2 else {
            FileHandle.standardError.write("usage: make-icon <output.iconset>\n".data(using: .utf8)!)
            exit(2)
        }
        let iconset = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 1 ? "" : "@2x"
                let png = try render(pixels: points * scale)
                try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
    }

    static func render(pixels: Int) throws -> Data {
        let size = CGFloat(pixels)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: size / 1024, y: size / 1024)

        // Apple's macOS icon grid: an 824pt rounded square centered in 1024, with a soft drop shadow.
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(squircle)
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Midnight backdrop: deep navy, a little lighter at the top.
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        let backdrop = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.13, green: 0.13, blue: 0.22, alpha: 1),
            CGColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(backdrop, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        ctx.restoreGState()

        // Hairline edge, like the wheel's stroke.
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183,
                           transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        ctx.setLineWidth(4)
        ctx.strokePath()

        // Shifted down-left a touch: the raised segment makes the mark heavier toward the top right.
        let markRect = CGRect(x: 150, y: 150, width: 680, height: 680)
        let (ring, segment) = LogoMark().parts(in: markRect)

        // Ring: soft white.
        ctx.addPath(ring)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.92))
        ctx.fillPath()

        // Segment: the wheel's hover gradient, with its glow.
        let violet = CGColor(red: 0.49, green: 0.36, blue: 1.0, alpha: 1)
        let blue = CGColor(red: 0.18, green: 0.62, blue: 1.0, alpha: 1)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 60, color: CGColor(red: 0.36, green: 0.48, blue: 1.0, alpha: 0.9))
        ctx.addPath(segment)
        ctx.setFillColor(violet)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(segment)
        ctx.clip()
        let bounds = segment.boundingBoxOfPath
        let hover = CGGradient(colorsSpace: space, colors: [violet, blue] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(hover, start: CGPoint(x: bounds.minX, y: bounds.maxY),
                               end: CGPoint(x: bounds.maxX, y: bounds.minY), options: [])
        ctx.restoreGState()

        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }
}
