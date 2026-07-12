import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    let launchAtLoginController: LaunchAtLoginController
    let onFinish: () -> Void

    @State private var launchAtLogin = false
    @State private var launchErrorMessage: String?

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.blue.gradient)
                    .frame(width: 88, height: 88)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .blue.opacity(0.25), radius: 18, y: 8)

            VStack(spacing: 8) {
                Text("Discord, one edge away")
                    .font(.largeTitle.weight(.bold))

                Text("Move the pointer to the \(settings.sidebarEdge.title.lowercased()) edge of any display, or press \(settings.shortcut.displayName), to reveal SideCord.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)
            }

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(
                    symbol: "rectangle.on.rectangle.angled",
                    title: "Available on every Space",
                    detail: "The sidebar follows the display you are using and floats above ordinary windows."
                )
                FeatureRow(
                    symbol: "lock.shield",
                    title: "Your Discord session stays in WebKit",
                    detail: "SideCord never reads or exports credentials or authentication tokens."
                )
                FeatureRow(
                    symbol: "paintbrush",
                    title: "Comfortably compact",
                    detail: "Use the built-in compact style or add local CSS from Settings."
                )
            }
            .padding(.horizontal, 20)

            Toggle("Launch SideCord when I log in", isOn: $launchAtLogin)
                .toggleStyle(.switch)

            Button("Get Started") {
                do {
                    try launchAtLoginController.setEnabled(launchAtLogin)
                    settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                        || launchAtLoginController.requiresApproval
                    onFinish()
                } catch {
                    launchAtLoginController.refresh()
                    launchAtLogin = launchAtLoginController.isEnabled
                        || launchAtLoginController.requiresApproval
                    settings.launchAtLoginEnabled = launchAtLogin
                    launchErrorMessage = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(36)
        .frame(width: 600)
        .frame(minHeight: 630)
        .background(.background)
        .onAppear {
            launchAtLoginController.refresh()
            launchAtLogin = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
        }
        .alert("Couldn’t update Launch at Login", isPresented: Binding(
            get: { launchErrorMessage != nil },
            set: { if !$0 { launchErrorMessage = nil } }
        )) {
            Button("OK") { launchErrorMessage = nil }
        } message: {
            Text(launchErrorMessage ?? "Unknown error")
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
