import Cocoa
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    let popover = NSPopover()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if let button = statusItem.button {
            if let img = NSImage(named: NSImage.Name("StatusBarButtonImage")) {
                img.isTemplate = true
                button.image = img
            }
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.contentViewController = MainViewController.freshController()
        popover.animates = true
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self = self, self.popover.isShown {
                self.closePopover(sender: event)
            }
        }
    }

    @objc func statusBarClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    func showPopover(sender: Any?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        eventMonitor?.start()
    }

    func closePopover(sender: Any?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Twitch Notifier",
                                action: #selector(showAbout(_:)),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences...",
                                action: #selector(showPreferences(_:)),
                                keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Twitch Notifier",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout(_ sender: Any?) {
        let year = Calendar.current.component(.year, from: Date())
        let copyright = NSAttributedString(
            string: "Copyright © \(year) Enum Solutions Inc.\nAll rights reserved.",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: copyright
        ])
    }

    @objc private func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "twitchnotifier" {
            TwitchAuthManager.shared.handleCallback(url: url)
        }
    }

    // MARK: - Live Count

    func updateLiveCount(_ count: Int) {
        guard let button = statusItem.button else { return }
        if count == 0 {
            if let img = NSImage(named: NSImage.Name("StatusBarButtonImage")) {
                img.isTemplate = true
                button.image = img
            }
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.image = purpleTintedIcon()
            let purple = NSColor(calibratedRed: 0.569, green: 0.275, blue: 1.0, alpha: 1.0)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: purple,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ]
            button.attributedTitle = NSAttributedString(string: " \(count)", attributes: attrs)
        }
    }

    private func purpleTintedIcon() -> NSImage {
        guard let source = NSImage(named: NSImage.Name("StatusBarButtonImage")) else { return NSImage() }
        return source.tinted(with: NSColor(calibratedRed: 0.569, green: 0.275, blue: 1.0, alpha: 1.0))
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let login = response.notification.request.content.userInfo["streamer"] as? String,
           let url = URL(string: "https://twitch.tv/\(login)") {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}

// MARK: - NSImage Tinting

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
