import SwiftUI
import WebKit

@MainActor
struct DiscordWebView: NSViewRepresentable {
    @ObservedObject var controller: DiscordWebController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // The controller owns and updates the persistent WKWebView. SwiftUI only
        // hosts the AppKit view so hiding the panel never tears down Discord.
    }
}
