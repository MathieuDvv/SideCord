import Combine
import CryptoKit
import Foundation
import WebKit

struct PluginWebPanelLayout: Equatable, Sendable {
    static let gap = 12.0
    static let hostMinimumHeight = 120.0
    static let hostMaximumHeight = 320.0
    static let maximumTotalHeightFraction = 0.40
    static let minimumDiscordHeight = 300.0

    let panelHeight: Double
    let discordHeight: Double
    let gap: Double

    static func heightBounds(
        manifestMinimum: Double?,
        manifestMaximum: Double?
    ) -> ClosedRange<Double> {
        let upperBound = min(
            hostMaximumHeight,
            max(hostMinimumHeight, manifestMaximum ?? hostMaximumHeight)
        )
        let lowerBound = min(
            upperBound,
            max(hostMinimumHeight, manifestMinimum ?? hostMinimumHeight)
        )
        return lowerBound ... upperBound
    }

    static func clampedRequestedHeight(
        _ requestedHeight: Double,
        manifestMinimum: Double?,
        manifestMaximum: Double?
    ) -> Double {
        let bounds = heightBounds(
            manifestMinimum: manifestMinimum,
            manifestMaximum: manifestMaximum
        )
        let safeRequest = requestedHeight.isFinite ? requestedHeight : bounds.lowerBound
        return min(max(safeRequest, bounds.lowerBound), bounds.upperBound)
    }

    static func resolve(
        totalHeight: Double,
        requestedHeight: Double,
        manifestMinimum: Double?,
        manifestMaximum: Double?
    ) -> Self? {
        guard totalHeight.isFinite, totalHeight > 0 else { return nil }
        let availableForPanel = totalHeight - gap - minimumDiscordHeight
        let bounds = heightBounds(
            manifestMinimum: manifestMinimum,
            manifestMaximum: manifestMaximum
        )
        let upperBound = min(
            bounds.upperBound,
            totalHeight * maximumTotalHeightFraction,
            availableForPanel
        )
        guard upperBound >= hostMinimumHeight else { return nil }
        let lowerBound = min(upperBound, bounds.lowerBound)
        let safeRequest = requestedHeight.isFinite ? requestedHeight : lowerBound
        let panelHeight = min(max(safeRequest, lowerBound), upperBound)
        return Self(
            panelHeight: panelHeight,
            discordHeight: totalHeight - gap - panelHeight,
            gap: gap
        )
    }
}

@MainActor
final class PluginWebPanelRuntime: ObservableObject {
    typealias ControllerFactory = @MainActor (
        String,
        SideCordPluginWebPanel,
        SideCordPluginPermissions
    ) -> PluginWebPanelController

    @Published private(set) var activeBottomPanel: PluginWebPanelController?
    @Published private(set) var preferenceRevision = 0

    private let pluginManager: SideCordPluginManager
    private let defaults: UserDefaults
    private let controllerFactory: ControllerFactory
    private var controllers: [String: PluginWebPanelController] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var sidebarIsVisible = false

    init(
        pluginManager: SideCordPluginManager,
        defaults: UserDefaults = .standard,
        controllerFactory: @escaping ControllerFactory = { identifier, panel, permissions in
            PluginWebPanelController(
                pluginIdentifier: identifier,
                panel: panel,
                permissions: permissions
            )
        }
    ) {
        self.pluginManager = pluginManager
        self.defaults = defaults
        self.controllerFactory = controllerFactory
        observePlugins()
        reconcile()
    }

    var activeControllerCount: Int { controllers.count }

    func isVisible(pluginIdentifier: String, contributionIdentifier: String) -> Bool {
        let key = preferenceKey(
            "visible",
            pluginIdentifier: pluginIdentifier,
            contributionIdentifier: contributionIdentifier
        )
        return defaults.object(forKey: key) as? Bool ?? true
    }

    func setVisible(
        _ visible: Bool,
        pluginIdentifier: String,
        contributionIdentifier: String
    ) {
        defaults.set(
            visible,
            forKey: preferenceKey(
                "visible",
                pluginIdentifier: pluginIdentifier,
                contributionIdentifier: contributionIdentifier
            )
        )
        if !visible,
           !isBackgroundAudioAllowed(
               pluginIdentifier: pluginIdentifier,
               contributionIdentifier: contributionIdentifier
           ) {
            controllers[controllerKey(pluginIdentifier, contributionIdentifier)]?
                .pausePlayback()
        }
        reconcileActivePanel()
        preferenceRevision &+= 1
    }

    func requestedHeight(
        pluginIdentifier: String,
        panel: SideCordPluginWebPanel
    ) -> Double {
        let value = defaults.object(
            forKey: preferenceKey(
                "height",
                pluginIdentifier: pluginIdentifier,
                contributionIdentifier: panel.id
            )
        ) as? Double
        return PluginWebPanelLayout.clampedRequestedHeight(
            value?.isFinite == true ? value! : panel.preferredHeight,
            manifestMinimum: panel.minimumHeight,
            manifestMaximum: panel.maximumHeight
        )
    }

    func setRequestedHeight(
        _ height: Double,
        pluginIdentifier: String,
        panel: SideCordPluginWebPanel
    ) {
        guard height.isFinite else { return }
        let clampedHeight = PluginWebPanelLayout.clampedRequestedHeight(
            height,
            manifestMinimum: panel.minimumHeight,
            manifestMaximum: panel.maximumHeight
        )
        defaults.set(
            clampedHeight,
            forKey: preferenceKey(
                "height",
                pluginIdentifier: pluginIdentifier,
                contributionIdentifier: panel.id
            )
        )
        preferenceRevision &+= 1
    }

    func resolvedLayout(totalHeight: Double) -> PluginWebPanelLayout? {
        guard let controller = activeBottomPanel else { return nil }
        return PluginWebPanelLayout.resolve(
            totalHeight: totalHeight,
            requestedHeight: requestedHeight(
                pluginIdentifier: controller.pluginIdentifier,
                panel: controller.panel
            ),
            manifestMinimum: controller.panel.minimumHeight,
            manifestMaximum: controller.panel.maximumHeight
        )
    }

    func isBackgroundAudioAllowed(
        pluginIdentifier: String,
        contributionIdentifier: String
    ) -> Bool {
        defaults.bool(
            forKey: preferenceKey(
                "backgroundAudio",
                pluginIdentifier: pluginIdentifier,
                contributionIdentifier: contributionIdentifier
            )
        )
    }

    func setBackgroundAudioAllowed(
        _ allowed: Bool,
        pluginIdentifier: String,
        contributionIdentifier: String
    ) {
        let requested = pluginManager.installed.first { $0.id == pluginIdentifier }?
            .manifest.permissions.backgroundAudio == true
        let approved = allowed && requested
        defaults.set(
            approved,
            forKey: preferenceKey(
                "backgroundAudio",
                pluginIdentifier: pluginIdentifier,
                contributionIdentifier: contributionIdentifier
            )
        )
        if !approved,
           (!sidebarIsVisible || !isVisible(
               pluginIdentifier: pluginIdentifier,
               contributionIdentifier: contributionIdentifier
           )) {
            controllers[controllerKey(pluginIdentifier, contributionIdentifier)]?
                .pausePlayback()
        }
        preferenceRevision &+= 1
    }

    func approveRequestedPermissions(identifier: String) {
        guard let plugin = pluginManager.installed.first(where: { $0.id == identifier }),
              let panel = plugin.manifest.contributions.webPanels.first
        else { return }
        setBackgroundAudioAllowed(
            plugin.manifest.permissions.backgroundAudio,
            pluginIdentifier: identifier,
            contributionIdentifier: panel.id
        )
    }

    func reload(pluginIdentifier: String, contributionIdentifier: String) {
        controllers[controllerKey(pluginIdentifier, contributionIdentifier)]?.reload()
    }

    func openInBrowser(pluginIdentifier: String, contributionIdentifier: String) {
        controllers[controllerKey(pluginIdentifier, contributionIdentifier)]?.openInBrowser()
    }

    func clearWebsiteData(pluginIdentifier: String, contributionIdentifier: String) async {
        await controllers[controllerKey(pluginIdentifier, contributionIdentifier)]?
            .clearWebsiteData()
    }

    func sidebarDidRetract() {
        sidebarIsVisible = false
        for controller in controllers.values where !isBackgroundAudioAllowed(
            pluginIdentifier: controller.pluginIdentifier,
            contributionIdentifier: controller.panel.id
        ) {
            controller.pausePlayback()
        }
    }

    func sidebarDidReveal() {
        sidebarIsVisible = true
        // The persistent controller remains attached; revealing must not reload it.
    }

    func prepareForUninstall(identifier: String) {
        let keys = controllers.keys.filter { $0.hasPrefix("\(identifier)\u{0}") }
        for key in keys {
            controllers.removeValue(forKey: key)?.shutdown()
        }
        reconcileActivePanel()
    }

    func removeWebsiteData(pluginIdentifier: String, contributionIdentifier: String) async throws {
        prepareForUninstall(identifier: pluginIdentifier)
        let identifier = PluginWebPanelController.stableDataStoreIdentifier(
            pluginIdentifier: pluginIdentifier,
            contributionIdentifier: contributionIdentifier
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func shutdown() {
        cancellables.removeAll()
        for controller in controllers.values {
            controller.shutdown()
        }
        controllers.removeAll()
        activeBottomPanel = nil
    }

    private func observePlugins() {
        Publishers.Merge(
            pluginManager.$installed.map { _ in () },
            pluginManager.$enabledIdentifiers.map { _ in () }
        )
        .debounce(for: .milliseconds(20), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.reconcile() }
        .store(in: &cancellables)
    }

    private func reconcile() {
        let descriptors = pluginManager.installed
            .filter { pluginManager.enabledIdentifiers.contains($0.id) }
            .compactMap { plugin -> (String, SideCordPluginWebPanel, SideCordPluginPermissions)? in
                guard let panel = plugin.manifest.contributions.webPanels.first else { return nil }
                return (plugin.id, panel, plugin.manifest.permissions)
            }
            .sorted { $0.0 < $1.0 }

        let activeDescriptors = Array(descriptors.prefix(1))
        let desiredKeys = Set(activeDescriptors.map { controllerKey($0.0, $0.1.id) })
        for key in controllers.keys where !desiredKeys.contains(key) {
            controllers.removeValue(forKey: key)?.shutdown()
        }

        for (pluginIdentifier, panel, permissions) in activeDescriptors {
            let key = controllerKey(pluginIdentifier, panel.id)
            if let existing = controllers[key],
               existing.panel == panel,
               existing.permissions == permissions {
                continue
            }
            controllers.removeValue(forKey: key)?.shutdown()
            controllers[key] = controllerFactory(pluginIdentifier, panel, permissions)
        }
        reconcileActivePanel()
    }

    private func reconcileActivePanel() {
        activeBottomPanel = controllers.values
            .filter {
                $0.panel.placement == .bottom && isVisible(
                    pluginIdentifier: $0.pluginIdentifier,
                    contributionIdentifier: $0.panel.id
                )
            }
            .sorted {
                controllerKey($0.pluginIdentifier, $0.panel.id)
                    < controllerKey($1.pluginIdentifier, $1.panel.id)
            }
            .first
    }

    private func controllerKey(_ pluginIdentifier: String, _ contributionIdentifier: String) -> String {
        "\(pluginIdentifier)\u{0}\(contributionIdentifier)"
    }

    private func preferenceKey(
        _ name: String,
        pluginIdentifier: String,
        contributionIdentifier: String
    ) -> String {
        "plugins.webPanel.\(pluginIdentifier).\(contributionIdentifier).\(name)"
    }
}
