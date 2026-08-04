import AppKit

extension UserDefaults {
    @objc dynamic var hideWhenNoSession: Bool {
        bool(forKey: SettingsKey.hideWhenNoSession)
    }
}

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var observation: NSKeyValueObservation?
    private lazy var menu: NSMenu = makeMenu()

    func startObserving() {
        syncVisibility()
        observation = UserDefaults.standard.observe(
            \.hideWhenNoSession, options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.syncVisibility() }
        }
    }

    private func syncVisibility() {
        if SettingsManager.shared.hideWhenNoSession {
            showStatusItem()
        } else {
            hideStatusItem()
        }
    }

    private func showStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                let icon = SettingsWindowController.bundleAppIcon()
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
                button.imageScaling = .scaleProportionallyDown
                button.toolTip = "CodeIsland"
            }
            item.menu = menu
            statusItem = item
        }
    }

    private func hideStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: L10n.shared["settings_ellipsis"],
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.shared["quit"],
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettings() {
        Task { @MainActor in
            SettingsWindowController.shared.show()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
