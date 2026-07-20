import SwiftUI
import WebKit

struct PluginWebPanelView: View {
    @ObservedObject var controller: PluginWebPanelController

    var body: some View {
        PluginWebView(controller: controller)
            .overlay(alignment: .center) {
                if let error = controller.errorMessage {
                    ContentUnavailableView(
                        "Web panel unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PluginWebView: NSViewRepresentable {
    let controller: PluginWebPanelController

    func makeNSView(context: Context) -> WKWebView {
        controller.startLoadingIfNeeded()
        return controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
