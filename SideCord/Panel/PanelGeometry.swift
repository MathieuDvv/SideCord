import AppKit

enum PanelGeometry {
    static let minimumWidth: CGFloat = 320
    static let maximumDisplayFraction: CGFloat = 0.8
    static let hiddenOvershoot: CGFloat = 4

    static func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return String(describing: screen)
    }

    static func constrainedWidth(
        _ requestedWidth: CGFloat,
        in usableFrame: NSRect,
        inset: CGFloat = 0
    ) -> CGFloat {
        let safeInset = constrainedInset(inset, in: usableFrame)
        let insetAvailableWidth = max(1, usableFrame.width - (safeInset * 2))
        let maximum = max(
            1,
            min(usableFrame.width * maximumDisplayFraction, insetAvailableWidth)
        )
        let minimum = min(minimumWidth, maximum)
        guard requestedWidth.isFinite else {
            return min(420, maximum)
        }
        return min(max(requestedWidth, minimum), maximum)
    }

    static func sidebarFrame(
        in usableFrame: NSRect,
        edge: SidebarEdge,
        requestedWidth: CGFloat,
        inset: CGFloat = 0
    ) -> NSRect {
        let safeInset = constrainedInset(inset, in: usableFrame)
        let width = constrainedWidth(requestedWidth, in: usableFrame, inset: safeInset)
        let x = edge == .left
            ? usableFrame.minX + safeInset
            : usableFrame.maxX - width - safeInset
        return NSRect(
            x: x,
            y: usableFrame.minY + safeInset,
            width: width,
            height: max(1, usableFrame.height - (safeInset * 2))
        )
    }

    static func hiddenFrame(
        from visibleFrame: NSRect,
        screenFrame: NSRect,
        edge: SidebarEdge
    ) -> NSRect {
        var frame = visibleFrame
        switch edge {
        case .left:
            frame.origin.x = screenFrame.minX - visibleFrame.width - hiddenOvershoot
        case .right:
            frame.origin.x = screenFrame.maxX + hiddenOvershoot
        }
        return frame
    }

    static func screen(containing point: NSPoint, from screens: [NSScreen]) -> NSScreen? {
        if let containingScreen = screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return containingScreen
        }

        return screens.min { lhs, rhs in
            squaredDistance(from: point, to: lhs.frame)
                < squaredDistance(from: point, to: rhs.frame)
        }
    }

    static func isEdgeExposed(
        of screen: NSScreen,
        edge: SidebarEdge,
        atY y: CGFloat,
        among screens: [NSScreen]
    ) -> Bool {
        let sampleX = edge == .left ? screen.frame.minX - 1 : screen.frame.maxX + 1
        let sample = NSPoint(x: sampleX, y: y)
        return !screens.contains { candidate in
            candidate !== screen && NSMouseInRect(sample, candidate.frame, false)
        }
    }

    private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private static func constrainedInset(_ requestedInset: CGFloat, in usableFrame: NSRect) -> CGFloat {
        guard requestedInset.isFinite else { return 0 }
        let maximum = max(0, (min(usableFrame.width, usableFrame.height) - 1) / 2)
        return min(max(requestedInset, 0), maximum)
    }
}
