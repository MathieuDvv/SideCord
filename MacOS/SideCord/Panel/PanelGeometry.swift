import AppKit

enum PanelGeometry {
    static let minimumWidth: CGFloat = 320
    static let maximumDisplayFraction: CGFloat = 0.8
    static let hiddenOvershoot: CGFloat = 4
    static let railWidth: CGFloat = 76
    static let railGap: CGFloat = 12
    static let railVerticalInset: CGFloat = 12
    static let attentionGlowWidth: CGFloat = 72
    static let incomingCallCardSize = NSSize(width: 292, height: 92)
    static let incomingCallCardInset: CGFloat = 14
    static let onboardingCompanionSize = NSSize(width: 430, height: 650)
    static let onboardingCompanionGap: CGFloat = 18

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

    static func railFrame(
        adjacentTo sidebarFrame: NSRect,
        in usableFrame: NSRect,
        edge: SidebarEdge,
        requestedWidth: CGFloat = railWidth,
        gap: CGFloat = railGap,
        verticalInset: CGFloat = railVerticalInset
    ) -> NSRect? {
        guard !sidebarFrame.isEmpty,
              requestedWidth.isFinite,
              gap.isFinite,
              verticalInset.isFinite
        else { return nil }

        let safeGap = max(0, gap)
        let availableWidth: CGFloat
        let x: CGFloat
        switch edge {
        case .right:
            availableWidth = sidebarFrame.minX - safeGap - usableFrame.minX
            let width = min(max(0, requestedWidth), max(0, availableWidth))
            guard width >= 1 else { return nil }
            x = sidebarFrame.minX - safeGap - width
        case .left:
            availableWidth = usableFrame.maxX - sidebarFrame.maxX - safeGap
            let width = min(max(0, requestedWidth), max(0, availableWidth))
            guard width >= 1 else { return nil }
            x = sidebarFrame.maxX + safeGap
        }

        let width = min(max(0, requestedWidth), max(0, availableWidth))
        let safeVerticalInset = min(
            max(0, verticalInset),
            max(0, (sidebarFrame.height - 1) / 2)
        )
        let minY = max(usableFrame.minY, sidebarFrame.minY + safeVerticalInset)
        let maxY = min(usableFrame.maxY, sidebarFrame.maxY - safeVerticalInset)
        guard maxY > minY else { return nil }

        return NSRect(x: x, y: minY, width: width, height: maxY - minY)
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

    static func attentionGlowFrame(
        in screenFrame: NSRect,
        edge: SidebarEdge,
        requestedWidth: CGFloat = attentionGlowWidth
    ) -> NSRect {
        let safeWidth = requestedWidth.isFinite
            ? min(max(1, requestedWidth), max(1, screenFrame.width))
            : min(attentionGlowWidth, max(1, screenFrame.width))
        return NSRect(
            x: edge == .left ? screenFrame.minX : screenFrame.maxX - safeWidth,
            y: screenFrame.minY,
            width: safeWidth,
            height: max(1, screenFrame.height)
        )
    }

    static func incomingCallCardFrame(
        in screenFrame: NSRect,
        edge: SidebarEdge,
        size: NSSize = incomingCallCardSize,
        inset: CGFloat = incomingCallCardInset
    ) -> NSRect {
        let width = min(max(1, size.width), max(1, screenFrame.width))
        let height = min(max(1, size.height), max(1, screenFrame.height))
        let safeInset = min(max(0, inset), max(0, screenFrame.width - width))
        return NSRect(
            x: edge == .left
                ? screenFrame.minX + safeInset
                : screenFrame.maxX - width - safeInset,
            y: screenFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }

    static func onboardingCompanionFrame(
        adjacentTo sidebarFrame: NSRect,
        in usableFrame: NSRect,
        edge: SidebarEdge,
        requestedSize: NSSize = onboardingCompanionSize
    ) -> NSRect {
        let availableWidth = max(1, usableFrame.width - 24)
        let availableHeight = max(1, usableFrame.height - 24)
        let requestedWidth = requestedSize.width.isFinite
            ? requestedSize.width
            : onboardingCompanionSize.width
        let requestedHeight = requestedSize.height.isFinite
            ? requestedSize.height
            : onboardingCompanionSize.height
        let width = min(max(1, requestedWidth), availableWidth)
        let height = min(max(1, requestedHeight), availableHeight)
        let preferredX = edge == .right
            ? sidebarFrame.minX - onboardingCompanionGap - width
            : sidebarFrame.maxX + onboardingCompanionGap
        let fallbackX = edge == .right
            ? sidebarFrame.minX - (width * 0.72)
            : sidebarFrame.maxX - (width * 0.28)
        let x = min(
            max(preferredX, usableFrame.minX + 12),
            usableFrame.maxX - width - 12
        )
        let resolvedX = sidebarFrame.intersects(
            NSRect(x: x, y: sidebarFrame.midY - height / 2, width: width, height: height)
        ) ? min(max(fallbackX, usableFrame.minX + 12), usableFrame.maxX - width - 12) : x
        return NSRect(
            x: resolvedX,
            y: min(
                max(sidebarFrame.midY - height / 2, usableFrame.minY + 12),
                usableFrame.maxY - height - 12
            ),
            width: width,
            height: height
        )
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
