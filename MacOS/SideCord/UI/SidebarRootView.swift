import SwiftUI

struct SidebarRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var webController: DiscordWebController
    @ObservedObject var panelController: PanelController
    @ObservedObject var pluginRuntime: PluginWebPanelRuntime
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let _ = pluginRuntime.preferenceRevision
            let layout = pluginRuntime.resolvedLayout(
                totalHeight: Double(geometry.size.height)
            )

            VStack(spacing: layout.map { CGFloat($0.gap) } ?? 0) {
                discordContent
                    .frame(
                        maxWidth: .infinity,
                        minHeight: layout.map { CGFloat($0.discordHeight) },
                        maxHeight: .infinity
                    )
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 9, y: 3)

                if let controller = pluginRuntime.activeBottomPanel,
                   let layout {
                    PluginWebPanelView(controller: controller)
                        .frame(height: CGFloat(layout.panelHeight))
                        .clipShape(.rect(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 9, y: 3)
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var discordContent: some View {
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
    }

    private var controlStrip: some View {
        HStack(spacing: 2) {
            if webController.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 7)
                    .accessibilityLabel("Loading Discord")
            }

            if settings.discordLayoutOptions.navigationPresentation == .floating {
                Button {
                    webController.toggleNavigationDrawer()
                } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 24, height: 24)
                }
                .help("Show or hide Discord channels")
                .accessibilityLabel("Toggle Discord navigation drawer")
            }

            if settings.discordLayoutOptions.navigationPresentation != .docked {
                Button {
                    settings.floatingRailEnabled.toggle()
                } label: {
                    Image(systemName: settings.floatingRailEnabled
                          ? "square.grid.2x2.fill"
                          : "square.grid.2x2")
                        .frame(width: 24, height: 24)
                }
                .help(settings.floatingRailEnabled
                      ? "Hide the floating server rail"
                      : "Show the floating server rail")
                .accessibilityLabel(settings.floatingRailEnabled
                                    ? "Hide floating server rail"
                                    : "Show floating server rail")
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

                    Menu("Navigation") {
                        ForEach(DiscordNavigationPresentation.allCases) { presentation in
                            Button {
                                setNavigationPresentation(presentation)
                            } label: {
                                if settings.discordLayoutOptions.navigationPresentation == presentation {
                                    Label(navigationTitle(presentation), systemImage: "checkmark")
                                } else {
                                    Text(navigationTitle(presentation))
                                }
                            }
                        }
                    }

                    Menu("Message composer") {
                        ForEach(DiscordComposerMode.allCases) { mode in
                            Button {
                                setComposerMode(mode)
                            } label: {
                                if settings.discordLayoutOptions.composerMode == mode {
                                    Label(composerTitle(mode), systemImage: "checkmark")
                                } else {
                                    Text(composerTitle(mode))
                                }
                            }
                        }
                    }

                    Toggle("Hide members", isOn: discordLayoutOptionBinding(\.hideMemberList))
                    Toggle("Hide account and voice dock", isOn: discordLayoutOptionBinding(\.hideAccountDock))
                    Toggle("Simplify header", isOn: discordLayoutOptionBinding(\.simplifyHeader))
                    Toggle("Limit tall message media", isOn: discordLayoutOptionBinding(\.compactMedia))
                    Toggle("Reduce Discord motion", isOn: discordLayoutOptionBinding(\.reduceMotion))
                }

                Menu("Visual Theme", systemImage: "paintpalette") {
                    ForEach(DiscordVisualTheme.allCases) { theme in
                        Button {
                            settings.visualTheme = theme
                        } label: {
                            if settings.visualTheme == theme {
                                Label(themeTitle(theme), systemImage: "checkmark")
                            } else {
                                Text(themeTitle(theme))
                            }
                        }
                    }
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
            .help("SideCord options")
            .accessibilityLabel("SideCord options")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 24, height: 24)
            }
            .help("Open SideCord Settings")
            .accessibilityLabel("Open SideCord Settings")

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
        .tint(nativeAccentColor)
        .padding(5)
        .background(nativeChromeColor, in: Capsule())
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

    private func setNavigationPresentation(_ presentation: DiscordNavigationPresentation) {
        var options = settings.discordLayoutOptions
        options.navigationPresentation = presentation
        settings.customDiscordLayoutOptions = options
        settings.discordLayoutMode = .custom
    }

    private func setComposerMode(_ mode: DiscordComposerMode) {
        var options = settings.discordLayoutOptions
        options.composerMode = mode
        settings.customDiscordLayoutOptions = options
        settings.discordLayoutMode = .custom
    }

    private func navigationTitle(_ presentation: DiscordNavigationPresentation) -> String {
        switch presentation {
        case .docked: "Docked"
        case .floating: "Floating rail and drawer"
        case .hidden: "Hidden"
        }
    }

    private func composerTitle(_ mode: DiscordComposerMode) -> String {
        switch mode {
        case .full: "Full"
        case .essential: "Essential controls"
        case .hidden: "Hidden"
        }
    }

    private func themeTitle(_ theme: DiscordVisualTheme) -> String {
        switch theme {
        case .systemGlass: "Mica"
        case .discord: "Discord"
        case .oled: "OLED"
        case .soft: "Soft"
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.themeColorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var nativeAccentColor: Color {
        let descriptor = settings.themeAccent.colorDescriptor
        return Color(
            red: descriptor.redUnit,
            green: descriptor.greenUnit,
            blue: descriptor.blueUnit
        )
    }

    private var nativeChromeColor: Color {
        let opacity = 0.08 + (0.16 * settings.themeIntensity)
        switch settings.visualTheme {
        case .systemGlass:
            return nativeAccentColor.opacity(opacity * 0.4)
        case .discord:
            return Color(red: 0.19, green: 0.20, blue: 0.22).opacity(opacity)
        case .oled:
            return .black.opacity(opacity * 1.4)
        case .soft:
            return nativeAccentColor.opacity(opacity * 0.65)
        }
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
