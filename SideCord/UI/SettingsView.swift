import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let webController: DiscordWebController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    let onShortcutChanged: (ShortcutDefinition) throws -> Void

    @State private var showingResetConfirmation = false
    @State private var shortcutDraft: ShortcutDefinition
    @State private var presentedError: PresentedSettingsError?

    init(
        settings: AppSettings,
        webController: DiscordWebController,
        launchAtLoginController: LaunchAtLoginController,
        onShortcutChanged: @escaping (ShortcutDefinition) throws -> Void
    ) {
        self.settings = settings
        self.webController = webController
        self.launchAtLoginController = launchAtLoginController
        self.onShortcutChanged = onShortcutChanged
        _shortcutDraft = State(initialValue: settings.shortcut)
    }

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }

            appearanceSettings
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            aboutView
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 620)
        .onAppear {
            launchAtLoginController.refresh()
            settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
        }
        .confirmationDialog(
            "Reset every SideCord preference?",
            isPresented: $showingResetConfirmation
        ) {
            Button("Reset Settings", role: .destructive) {
                resetSettings()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Sidebar") {
                Picker("Screen edge", selection: $settings.sidebarEdge) {
                    Label("Left", systemImage: "sidebar.left")
                        .tag(SidebarEdge.left)
                    Label("Right", systemImage: "sidebar.right")
                        .tag(SidebarEdge.right)
                }
                .pickerStyle(.segmented)

                Toggle("Reveal when the pointer rests at the edge", isOn: $settings.edgeHoverEnabled)

                LabeledContent("Hover dwell") {
                    HStack(spacing: 12) {
                        Slider(value: $settings.hoverDwellDelay, in: 0.1...1.0, step: 0.05)
                            .frame(width: 190)
                        Text(settings.hoverDwellDelay, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.edgeHoverEnabled)

                LabeledContent("Retraction delay") {
                    HStack(spacing: 12) {
                        Slider(value: $settings.retractionDelay, in: 0.2...3.0, step: 0.1)
                            .frame(width: 190)
                        Text(settings.retractionDelay, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Default width") {
                    HStack(spacing: 12) {
                        Slider(value: sidebarWidthBinding, in: 320...900, step: 20)
                            .frame(width: 190)
                        Text("\(Int(settings.sidebarWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                Text("Changing this value resets widths previously remembered for individual displays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Floating inset") {
                    HStack(spacing: 12) {
                        Slider(
                            value: $settings.sidebarInset,
                            in: AppSettings.sidebarInsetRange,
                            step: 4
                        )
                        .frame(width: 190)
                        Text("\(Int(settings.sidebarInset)) pt")
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                Text("Adds breathing room around the panel. Edge hover still begins at the screen edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                LabeledContent("Show or hide SideCord") {
                    ShortcutRecorderView(shortcut: shortcutBinding)
                }
                Text("Click the shortcut, then type a key together with at least one modifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch SideCord when I log in", isOn: launchAtLoginBinding)
                if launchAtLoginController.requiresApproval {
                    Label("Waiting for approval in Login Items", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("macOS may require approval in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var appearanceSettings: some View {
        Form {
            Section("Discord layout") {
                Picker("Density", selection: $settings.cssPreset) {
                    Text("Discord default").tag(CSSPreset.standard)
                    Text("Compact").tag(CSSPreset.compact)
                }
                .pickerStyle(.segmented)

                Picker("Quick mode", selection: $settings.discordLayoutMode) {
                    ForEach(DiscordLayoutMode.quickModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                    if settings.discordLayoutMode == .custom {
                        Text(DiscordLayoutMode.custom.title).tag(DiscordLayoutMode.custom)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.discordLayoutMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fine tuning") {
                Toggle(
                    "Hide server list",
                    isOn: discordLayoutOptionBinding(\.hideServerRail)
                )
                Toggle(
                    "Hide channels and DMs",
                    isOn: discordLayoutOptionBinding(\.hideChannelList)
                )
                Toggle(
                    "Hide member list",
                    isOn: discordLayoutOptionBinding(\.hideMemberList)
                )
                Toggle(
                    "Hide account and voice dock",
                    isOn: discordLayoutOptionBinding(\.hideAccountDock)
                )
                Toggle(
                    "Simplify channel header",
                    isOn: discordLayoutOptionBinding(\.simplifyHeader)
                )
                Toggle(
                    "Simplify message composer",
                    isOn: discordLayoutOptionBinding(\.simplifyComposer)
                )
                Toggle(
                    "Hide message composer (Reader)",
                    isOn: discordLayoutOptionBinding(\.hideComposer)
                )

                Text("Changing any individual option creates a Custom mode. Hidden Discord controls are only visual; no account permissions change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reading comfort") {
                Toggle(
                    "Limit tall message media",
                    isOn: discordLayoutOptionBinding(\.compactMedia)
                )
                Toggle(
                    "Reduce Discord interface motion",
                    isOn: discordLayoutOptionBinding(\.reduceMotion)
                )
            }

            Section("Custom CSS") {
                Toggle("Use custom CSS on Discord pages", isOn: $settings.customCSSEnabled)

                TextEditor(text: $settings.customCSS)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 170)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator, lineWidth: 1)
                    }
                    .disabled(!settings.customCSSEnabled)

                if let validationError = DiscordCSSComposer.validationError(for: settings.customCSS),
                   settings.customCSSEnabled {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("Stored locally, applied automatically, and injected only into Discord.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Custom CSS") {
                        settings.customCSS = ""
                    }
                    .disabled(settings.customCSS.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var aboutView: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.blue.gradient)
                    .frame(width: 72, height: 72)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("SideCord")
                    .font(.title.bold())
                Text("Version 1.0.0")
                    .foregroundStyle(.secondary)
            }

            Text("A focused Discord sidebar for macOS. SideCord is independent software and is not affiliated with Discord Inc.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 390)

            Button("Reset All Settings", role: .destructive) {
                showingResetConfirmation = true
            }
        }
        .padding(40)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                launchAtLoginController.isEnabled || launchAtLoginController.requiresApproval
            },
            set: { shouldEnable in
                do {
                    try launchAtLoginController.setEnabled(shouldEnable)
                    settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                        || launchAtLoginController.requiresApproval
                } catch {
                    launchAtLoginController.refresh()
                    settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                        || launchAtLoginController.requiresApproval
                    presentedError = PresentedSettingsError(
                        title: "Couldn’t update Launch at Login",
                        message: error.localizedDescription
                    )
                }
            }
        )
    }

    private var shortcutBinding: Binding<ShortcutDefinition> {
        Binding(
            get: { shortcutDraft },
            set: { candidate in
                do {
                    try onShortcutChanged(candidate)
                    settings.shortcut = candidate
                    shortcutDraft = candidate
                } catch {
                    shortcutDraft = settings.shortcut
                    presentedError = PresentedSettingsError(
                        title: "Couldn’t use that shortcut",
                        message: error.localizedDescription
                    )
                }
            }
        )
    }

    private var sidebarWidthBinding: Binding<CGFloat> {
        Binding(
            get: { settings.sidebarWidth },
            set: { width in
                settings.resetAllDisplayWidths()
                settings.sidebarWidth = width
            }
        )
    }

    private func discordLayoutOptionBinding(
        _ keyPath: WritableKeyPath<DiscordLayoutOptions, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings.discordLayoutOptions[keyPath: keyPath] },
            set: { settings.setDiscordLayoutOption(keyPath, enabled: $0) }
        )
    }

    private func resetSettings() {
        let previousShortcut = settings.shortcut
        settings.resetToDefaults()

        do {
            try onShortcutChanged(settings.shortcut)
            shortcutDraft = settings.shortcut
        } catch {
            settings.shortcut = previousShortcut
            shortcutDraft = previousShortcut
            presentedError = PresentedSettingsError(
                title: "Some settings were reset",
                message: "The default shortcut was unavailable, so SideCord kept your previous shortcut. \(error.localizedDescription)"
            )
        }

        do {
            try launchAtLoginController.setEnabled(false)
        } catch {
            presentedError = PresentedSettingsError(
                title: "Some settings were reset",
                message: "Launch at Login could not be disabled. \(error.localizedDescription)"
            )
        }
        settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
            || launchAtLoginController.requiresApproval
        webController.refreshCSS()
    }
}

private struct PresentedSettingsError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
