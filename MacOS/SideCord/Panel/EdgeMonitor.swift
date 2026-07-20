import AppKit

@MainActor
final class EdgeMonitor {
    typealias TriggerHandler = (NSScreen) -> Void

    private let settings: AppSettings
    private let isSuppressed: () -> Bool
    private let onTrigger: TriggerHandler
    private var timer: Timer?
    private var dwellCandidateID: String?
    private var dwellStart: TimeInterval?
    private var hasTriggeredForCurrentContact = false

    private let activationThickness: CGFloat = 3

    init(
        settings: AppSettings,
        isSuppressed: @escaping () -> Bool,
        onTrigger: @escaping TriggerHandler
    ) {
        self.settings = settings
        self.isSuppressed = isSuppressed
        self.onTrigger = onTrigger
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.samplePointer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetContact()
    }

    private func samplePointer() {
        guard settings.edgeHoverEnabled,
              !isSuppressed(),
              NSEvent.pressedMouseButtons == 0,
              let candidate = edgeCandidate(at: NSEvent.mouseLocation)
        else {
            resetContact()
            return
        }

        let candidateID = PanelGeometry.displayID(for: candidate)
        if dwellCandidateID != candidateID {
            dwellCandidateID = candidateID
            dwellStart = ProcessInfo.processInfo.systemUptime
            hasTriggeredForCurrentContact = false
            return
        }

        guard !hasTriggeredForCurrentContact,
              let dwellStart,
              ProcessInfo.processInfo.systemUptime - dwellStart >= settings.hoverDwellDelay
        else { return }

        hasTriggeredForCurrentContact = true
        onTrigger(candidate)
    }

    private func edgeCandidate(at point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return screens
            .filter { screen in
                let verticalRange = screen.visibleFrame.minY ... screen.visibleFrame.maxY
                guard verticalRange.contains(point.y) else { return false }

                let edgeX = settings.sidebarEdge == .left
                    ? screen.frame.minX
                    : screen.frame.maxX
                guard abs(point.x - edgeX) <= activationThickness else { return false }

                return PanelGeometry.isEdgeExposed(
                    of: screen,
                    edge: settings.sidebarEdge,
                    atY: point.y,
                    among: screens
                )
            }
            .min { lhs, rhs in
                let lhsX = settings.sidebarEdge == .left ? lhs.frame.minX : lhs.frame.maxX
                let rhsX = settings.sidebarEdge == .left ? rhs.frame.minX : rhs.frame.maxX
                return abs(point.x - lhsX) < abs(point.x - rhsX)
            }
    }

    private func resetContact() {
        dwellCandidateID = nil
        dwellStart = nil
        hasTriggeredForCurrentContact = false
    }
}
