import Foundation

enum PluginWebNavigationDecision: Equatable, Sendable {
    case allow
    case openExternally
    case cancel
}

struct PluginWebNavigationPolicy: Equatable, Sendable {
    let allowedHosts: Set<String>

    init(allowedHosts: [String]) {
        self.allowedHosts = Set(allowedHosts)
    }

    func decision(for url: URL?, userInitiated: Bool) -> PluginWebNavigationDecision {
        guard let url,
              SideCordPluginManager.isSafeWebPanelURL(url),
              let host = SideCordPluginManager.normalizedExactHost(url)
        else { return .cancel }

        if allowedHosts.contains(host) {
            return .allow
        }
        return userInitiated ? .openExternally : .cancel
    }
}
