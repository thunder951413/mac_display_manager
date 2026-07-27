import AppKit

enum LumaFlowMenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()

            let display = NSBezierPath(
                roundedRect: NSRect(x: 1.5, y: 4.5, width: 17, height: 12),
                xRadius: 2.2,
                yRadius: 2.2
            )
            display.lineWidth = 1.35
            display.stroke()

            let curve = NSBezierPath()
            curve.move(to: NSPoint(x: 4.2, y: 8))
            curve.curve(
                to: NSPoint(x: 15.8, y: 13.2),
                controlPoint1: NSPoint(x: 8, y: 7.6),
                controlPoint2: NSPoint(x: 11.8, y: 12.7)
            )
            curve.lineCapStyle = .round
            curve.lineWidth = 1.45
            curve.stroke()

            for point in [
                NSPoint(x: 4.2, y: 8),
                NSPoint(x: 10, y: 9.7),
                NSPoint(x: 15.8, y: 13.2)
            ] {
                let node = NSBezierPath(
                    ovalIn: NSRect(
                        x: point.x - 1.05,
                        y: point.y - 1.05,
                        width: 2.1,
                        height: 2.1
                    )
                )
                node.lineWidth = 1
                node.stroke()
            }

            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 10, y: 4.5))
            stand.line(to: NSPoint(x: 10, y: 2.2))
            stand.move(to: NSPoint(x: 6.8, y: 2.2))
            stand.line(to: NSPoint(x: 13.2, y: 2.2))
            stand.lineCapStyle = .round
            stand.lineWidth = 1.35
            stand.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
