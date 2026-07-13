import AppKit
import SwiftUI

@MainActor
enum ApplicationMenuFactory {
    static func make(
        appName: String = applicationName,
        settingsTarget: AnyObject? = nil
    ) -> NSMenu {
        let mainMenu = NSMenu(title: "Main")

        let applicationMenuItem = NSMenuItem(
            title: appName,
            action: nil,
            keyEquivalent: ""
        )
        let applicationMenu = NSMenu(title: appName)
        applicationMenu.addItem(command(
            "About \(appName)",
            action: "orderFrontStandardAboutPanel:"
        ))
        applicationMenu.addItem(.separator())
        let settingsItem = command(
            "Settings…",
            action: "showSettings:",
            key: ","
        )
        settingsItem.target = settingsTarget
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu(title: "Services")
        applicationMenu.addItem(servicesItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(command(
            "Hide \(appName)",
            action: "hide:",
            key: "h"
        ))
        applicationMenu.addItem(command(
            "Hide Others",
            action: "hideOtherApplications:",
            key: "h",
            modifiers: [.command, .option]
        ))
        applicationMenu.addItem(command(
            "Show All",
            action: "unhideAllApplications:"
        ))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(command(
            "Quit \(appName)",
            action: "terminate:",
            key: "q"
        ))
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(command("Undo", action: "undo:", key: "z"))
        editMenu.addItem(command(
            "Redo",
            action: "redo:",
            key: "z",
            modifiers: [.command, .shift]
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(command("Cut", action: "cut:", key: "x"))
        editMenu.addItem(command("Copy", action: "copy:", key: "c"))
        editMenu.addItem(command("Paste", action: "paste:", key: "v"))
        editMenu.addItem(command(
            "Paste and Match Style",
            action: "pasteAsPlainText:",
            key: "v",
            modifiers: [.command, .option, .shift]
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(command("Select All", action: "selectAll:", key: "a"))

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(command("Close", action: "performClose:", key: "w"))
        windowMenu.addItem(command("Minimize", action: "performMiniaturize:", key: "m"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        return mainMenu
    }

    static func connectSystemMenus(in mainMenu: NSMenu, to application: NSApplication) {
        application.servicesMenu = mainMenu.items.first?
            .submenu?
            .items
            .first { $0.title == "Services" }?
            .submenu
        application.windowsMenu = mainMenu.items
            .first { $0.submenu?.title == "Window" }?
            .submenu
    }

    private static var applicationName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    private static func command(
        _ title: String,
        action: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: Selector((action)),
            keyEquivalent: key
        )
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = nil
        return item
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private lazy var launchAtLoginController = LaunchAtLoginController()
    private lazy var webController = DiscordWebController(settings: settings)
    private lazy var panelController = PanelController(
        settings: settings,
        webController: webController,
        railModel: webController.railModel
    )
    private lazy var shortcutManager = GlobalShortcutManager(identifier: 1)
    private lazy var navigationShortcutManager = GlobalShortcutManager(identifier: 2)

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var shortcutError: Error?
    private var navigationShortcutError: Error?

    private let onboardingCompletedKey = "onboarding.completed"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = ApplicationMenuFactory.make(settingsTarget: self)
        NSApp.mainMenu = mainMenu
        ApplicationMenuFactory.connectSystemMenus(in: mainMenu, to: NSApp)
        NSApp.setActivationPolicy(.accessory)

        synchronizeLaunchAtLoginState()
        installSidebarContent()
        configureStatusItem()
        do {
            try registerShortcut(settings.shortcut)
        } catch {
            shortcutError = error
        }
        do {
            try registerNavigationShortcut(settings.navigationShortcut)
        } catch {
            navigationShortcutError = error
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
        webController.shutdown()
        shortcutManager.shutdown()
        navigationShortcutManager.shutdown()
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
            panelController: panelController,
            onOpenSettings: { [weak self] in
                self?.showSettings(nil)
            }
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

        let navigationShortcutItem = NSMenuItem(
            title: "Navigation: \(settings.navigationShortcut.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        navigationShortcutItem.isEnabled = false
        menu.addItem(navigationShortcutItem)

        if let navigationShortcutError {
            let item = NSMenuItem(
                title: navigationShortcutError.localizedDescription,
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

        let railItem = actionItem(
            title: "Floating Server Rail",
            action: #selector(toggleFloatingRail)
        )
        railItem.state = settings.floatingRailEnabled ? .on : .off
        railItem.isEnabled = settings.discordLayoutOptions.navigationPresentation != .docked
        menu.addItem(railItem)

        menu.addItem(actionItem(
            title: panelController.isMaximized ? "Restore Sidebar" : "Maximize Sidebar",
            action: #selector(toggleMaximize)
        ))
        menu.addItem(actionItem(title: "Reload Discord", action: #selector(reloadDiscord)))

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Settings…", action: #selector(showSettings(_:))))
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

    @objc private func toggleFloatingRail() {
        settings.floatingRailEnabled.toggle()
    }

    @objc private func toggleMaximize() {
        panelController.toggleMaximize()
    }

    @objc private func reloadDiscord() {
        webController.reload()
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            let settingsView = SettingsView(
                settings: settings,
                webController: webController,
                launchAtLoginController: launchAtLoginController,
                onShortcutChanged: { [weak self] shortcut in
                    guard let self else { return }
                    try self.registerShortcut(shortcut)
                },
                onNavigationShortcutChanged: { [weak self] shortcut in
                    guard let self else { return }
                    try self.registerNavigationShortcut(shortcut)
                },
                onShortcutsReset: { [weak self] in
                    guard let self else { return }
                    try self.resetShortcutsToDefaults()
                }
            )
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "SideCord Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 980, height: 720))
            window.contentMinSize = NSSize(width: 820, height: 620)
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        activate(windowController: settingsWindowController)
    }

    @objc private func showOnboarding() {
        if onboardingWindowController?.window?.isVisible == true {
            activate(windowController: onboardingWindowController)
            return
        }

        launchAtLoginController.refresh()
        let onboardingView = OnboardingView(
            settings: settings,
            launchAtLoginController: launchAtLoginController,
            onPreviewGlow: { [weak self] edge, accent in
                self?.panelController.previewNotificationGlow(edge: edge, accent: accent)
            },
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
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindowController = NSWindowController(window: window)

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

    private func registerNavigationShortcut(_ shortcut: ShortcutDefinition) throws {
        do {
            try navigationShortcutManager.register(shortcut) { [weak self] in
                guard let self else { return }
                if self.panelController.isVisible {
                    self.webController.toggleNavigationDrawer()
                } else {
                    self.webController.openNavigationDrawer()
                    self.panelController.reveal(activate: true)
                }
            }
            navigationShortcutError = nil
        } catch {
            navigationShortcutError = error
            throw error
        }
    }

    private func resetShortcutsToDefaults() throws {
        let previousSidebarShortcut = shortcutManager.registeredShortcut
        let previousNavigationShortcut = navigationShortcutManager.registeredShortcut

        shortcutManager.unregister()
        navigationShortcutManager.unregister()

        do {
            try registerShortcut(.optionD)
            try registerNavigationShortcut(.optionShiftD)
        } catch let resetError {
            shortcutManager.unregister()
            navigationShortcutManager.unregister()

            do {
                if let previousSidebarShortcut {
                    try registerShortcut(previousSidebarShortcut)
                }
                if let previousNavigationShortcut {
                    try registerNavigationShortcut(previousNavigationShortcut)
                }
            } catch let recoveryError {
                throw ShortcutPairResetError(
                    resetError: resetError,
                    recoveryError: recoveryError
                )
            }
            throw resetError
        }
    }
}

private struct ShortcutPairResetError: LocalizedError {
    let resetError: Error
    let recoveryError: Error

    var errorDescription: String? {
        "SideCord could not reset the shortcuts (\(resetError.localizedDescription)) or restore the previous pair (\(recoveryError.localizedDescription)). Choose new shortcuts or restart SideCord."
    }
}
