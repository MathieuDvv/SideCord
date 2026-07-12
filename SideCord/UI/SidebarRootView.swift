import SwiftUI

struct SidebarRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var webController: DiscordWebController
    @ObservedObject var panelController: PanelController

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DiscordWebView(controller: webController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = webController.error {
                errorView(error)
            }

            if let downloadError = webController.downloadError {
                downloadErrorBanner(downloadError)
            }

            controlStrip
                .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controlStrip: some View {
        HStack(spacing: 2) {
            if webController.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 7)
                    .accessibilityLabel("Loading Discord")
            }

            Button {
                panelController.togglePin()
            } label: {
                Image(systemName: settings.isPinned ? "pin.fill" : "pin")
                    .frame(width: 24, height: 24)
            }
            .help(settings.isPinned ? "Unpin and resume auto-retraction" : "Keep SideCord open")
            .accessibilityLabel(settings.isPinned ? "Unpin SideCord" : "Pin SideCord")

            Button {
                panelController.toggleMaximize()
            } label: {
                Image(systemName: panelController.isMaximized
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 24, height: 24)
            }
            .help(panelController.isMaximized ? "Restore sidebar" : "Maximize on this display")
            .accessibilityLabel(panelController.isMaximized ? "Restore sidebar" : "Maximize SideCord")

            Menu {
                Button("Back", systemImage: "chevron.backward") {
                    webController.goBack()
                }
                .disabled(!webController.canGoBack)

                Button("Forward", systemImage: "chevron.forward") {
                    webController.goForward()
                }
                .disabled(!webController.canGoForward)

                Divider()

                Menu("Discord Layout", systemImage: "rectangle.3.group") {
                    ForEach(DiscordLayoutMode.quickModes) { mode in
                        Button {
                            settings.applyDiscordLayoutMode(mode)
                        } label: {
                            if settings.discordLayoutMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }

                    Divider()

                    Toggle("Hide servers", isOn: discordLayoutOptionBinding(\.hideServerRail))
                    Toggle("Hide channels and DMs", isOn: discordLayoutOptionBinding(\.hideChannelList))
                    Toggle("Hide members", isOn: discordLayoutOptionBinding(\.hideMemberList))
                    Toggle("Hide account and voice dock", isOn: discordLayoutOptionBinding(\.hideAccountDock))
                    Toggle("Simplify header", isOn: discordLayoutOptionBinding(\.simplifyHeader))
                    Toggle("Simplify composer", isOn: discordLayoutOptionBinding(\.simplifyComposer))
                    Toggle("Hide composer", isOn: discordLayoutOptionBinding(\.hideComposer))
                    Toggle("Limit tall message media", isOn: discordLayoutOptionBinding(\.compactMedia))
                    Toggle("Reduce Discord motion", isOn: discordLayoutOptionBinding(\.reduceMotion))
                }

                Divider()

                Button("Reload Discord", systemImage: "arrow.clockwise") {
                    webController.reload()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Browser actions")
            .accessibilityLabel("Browser actions")

            Button {
                panelController.retract()
            } label: {
                Image(systemName: settings.sidebarEdge == .right
                      ? "chevron.right"
                      : "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .help("Hide SideCord")
            .accessibilityLabel("Hide SideCord")
        }
        .buttonStyle(.plain)
        .padding(5)
        .glassEffect(.regular, in: .capsule)
    }

    private func discordLayoutOptionBinding(
        _ keyPath: WritableKeyPath<DiscordLayoutOptions, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings.discordLayoutOptions[keyPath: keyPath] },
            set: { settings.setDiscordLayoutOption(keyPath, enabled: $0) }
        )
    }

    private func errorView(_ error: DiscordWebError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text(error.title)
                .font(.headline)

            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button(error.canRetryByReloading ? "Try Again" : "Dismiss") {
                if error.canRetryByReloading {
                    webController.reload()
                } else {
                    webController.dismissError()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func downloadErrorBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download failed")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Dismiss") {
                    webController.dismissDownloadError()
                }
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
