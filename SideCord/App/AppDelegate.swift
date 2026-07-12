import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private lazy var launchAtLoginController = LaunchAtLoginController()
    private lazy var webController = DiscordWebController(settings: settings)
    private lazy var panelController = PanelController(settings: settings)
    private lazy var shortcutManager = GlobalShortcutManager()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var shortcutError: Error?

    private let onboardingCompletedKey = "onboarding.completed"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        synchronizeLaunchAtLoginState()
        installSidebarContent()
        configureStatusItem()
        do {
            try registerShortcut(settings.shortcut)
        } catch {
            shortcutError = error
        }
        panelController.start()

        if !UserDefaults.standard.bool(forKey: onboardingCompletedKey) {
            showOnboarding()
        } else if shouldRevealForDevelopmentLaunch {
            panelController.revealForDevelopment()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController.stop()
        shortcutManager.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panelController.reveal(activate: true)
        return true
    }

    private var shouldRevealForDevelopmentLaunch: Bool {
#if DEBUG
        true
#else
        ProcessInfo.processInfo.arguments.contains("--show-sidebar")
#endif
    }

    private func installSidebarContent() {
        let rootView = SidebarRootView(
            settings: settings,
            webController: webController,
            panelController: panelController
        )
        panelController.setContentView(NSHostingView(rootView: rootView))
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "bubble.left.and.bubble.right.fill",
                accessibilityDescription: "SideCord"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SideCord"
        }

        let menu = NSMenu(title: "SideCord")
        menu.delegate = self
        item.menu = menu
        statusItem = item
        statusMenu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(actionItem(
            title: panelController.isVisible ? "Hide SideCord" : "Show SideCord",
            action: #selector(toggleSidebar)
        ))

        let shortcutItem = NSMenuItem(
            title: "Shortcut: \(settings.shortcut.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        if let shortcutError {
            let item = NSMenuItem(
                title: shortcutError.localizedDescription,
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let pinItem = actionItem(
            title: settings.isPinned ? "Unpin Sidebar" : "Pin Sidebar",
            action: #selector(togglePin)
        )
        pinItem.state = settings.isPinned ? .on : .off
        menu.addItem(pinItem)

        menu.addItem(actionItem(
            title: panelController.isMaximized ? "Restore Sidebar" : "Maximize Sidebar",
            action: #selector(toggleMaximize)
        ))
        menu.addItem(actionItem(title: "Reload Discord", action: #selector(reloadDiscord)))

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Settings…", action: #selector(showSettings)))
        menu.addItem(actionItem(title: "Welcome to SideCord…", action: #selector(showOnboarding)))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit SideCord", action: #selector(quit)))
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleSidebar() {
        panelController.toggle()
    }

    @objc private func togglePin() {
        panelController.togglePin()
        if settings.isPinned, !panelController.isVisible {
            panelController.reveal(activate: true)
        }
    }

    @objc private func toggleMaximize() {
        panelController.toggleMaximize()
    }

    @objc private func reloadDiscord() {
        webController.reload()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let settingsView = SettingsView(
                settings: settings,
                webController: webController,
                launchAtLoginController: launchAtLoginController,
                onShortcutChanged: { [weak self] shortcut in
                    guard let self else { return }
                    try self.registerShortcut(shortcut)
                }
            )
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "SideCord Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        activate(windowController: settingsWindowController)
    }

    @objc private func showOnboarding() {
        if onboardingWindowController == nil {
            let onboardingView = OnboardingView(
                settings: settings,
                launchAtLoginController: launchAtLoginController,
                onFinish: { [weak self] in
                    guard let self else { return }
                    UserDefaults.standard.set(true, forKey: self.onboardingCompletedKey)
                    self.onboardingWindowController?.close()
                    self.panelController.reveal(activate: true)
                }
            )
            let hostingController = NSHostingController(rootView: onboardingView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Welcome to SideCord"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindowController = NSWindowController(window: window)
        }

        activate(windowController: onboardingWindowController)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func activate(windowController: NSWindowController?) {
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func synchronizeLaunchAtLoginState() {
        launchAtLoginController.refresh()
        settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
            || launchAtLoginController.requiresApproval
    }

    private func registerShortcut(_ shortcut: ShortcutDefinition) throws {
        do {
            try shortcutManager.register(shortcut) { [weak self] in
                self?.panelController.toggle()
            }
            shortcutError = nil
        } catch {
            shortcutError = error
            throw error
        }
    }
}
