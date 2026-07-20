import Foundation

/// The result of applying SideCord's top-level navigation policy to a URL.
enum DiscordURLPolicyDecision: Equatable {
    case allow
    case openExternally
    case cancel
}

enum DiscordDownloadPolicyDecision: Equatable {
    case allow
    case download
    case cancel
}

enum DiscordDownloadPolicy {
    static func decision(
        isForMainFrame: Bool,
        canShowMIMEType: Bool,
        userInitiated: Bool
    ) -> DiscordDownloadPolicyDecision {
        guard isForMainFrame else { return .allow }
        if canShowMIMEType { return .allow }
        return userInitiated ? .download : .cancel
    }
}

enum DiscordJavaScriptDialogPolicy {
    static func allowsConfirmation(
        scheme: String,
        host: String,
        isMainFrame: Bool
    ) -> Bool {
        isMainFrame
            && scheme.lowercased() == "https"
            && DiscordURLPolicy.isDiscordHost(host)
    }
}

/// Pure URL classification used by the WebKit delegates and unit tests.
enum DiscordURLPolicy {
    private static let allowedDomains = ["discord.com", "discordapp.com"]

    static func decision(for url: URL?) -> DiscordURLPolicyDecision {
        guard let url else {
            return .cancel
        }

        if isDiscordURL(url) {
            return .allow
        }

        if url.scheme?.lowercased() == "https" {
            return .openExternally
        }

        return .cancel
    }

    static func isDiscordURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              var host = url.host(percentEncoded: false)?.lowercased()
        else {
            return false
        }

        // A fully-qualified host with a trailing dot is equivalent to the same
        // host without it, and is still safe to classify by label boundaries.
        while host.hasSuffix(".") {
            host.removeLast()
        }

        return isDiscordHost(host)
    }

    static func isDiscordHost(_ candidate: String) -> Bool {
        var host = candidate.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return allowedDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }
}
