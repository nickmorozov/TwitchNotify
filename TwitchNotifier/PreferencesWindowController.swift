import Cocoa
import ServiceManagement

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("preferencesDidChange")
}

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var loginButton: NSButton!
    private var statusLabel: NSTextField!
    private var syncButton: NSButton!
    private var channelCountLabel: NSTextField!
    private var addChannelField: NSTextField!
    private var autoUpdateCheckbox: NSButton!
    private var persistentNotificationsCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!

    private let defaults = UserDefaults.standard
    private let streamersKey = "monitoredStreamers"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Twitch Notifier Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        updateConnectionStatus()
        updateChannelCount()
    }

    private func setupUI() {
        guard let v = window?.contentView else { return }

        // --- Auth ---
        loginButton = NSButton(title: "Login with Twitch", target: self,
                               action: #selector(loginToTwitch(_:)))
        loginButton.bezelStyle = .rounded
        loginButton.font = .systemFont(ofSize: 12)
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(loginButton)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(statusLabel)

        // --- Sync ---
        syncButton = NSButton(title: "Sync Follows", target: self,
                              action: #selector(syncFollows(_:)))
        syncButton.bezelStyle = .rounded
        syncButton.font = .systemFont(ofSize: 12)
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(syncButton)

        channelCountLabel = NSTextField(labelWithString: "")
        channelCountLabel.font = .systemFont(ofSize: 10)
        channelCountLabel.textColor = .secondaryLabelColor
        channelCountLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(channelCountLabel)

        // --- Add Channel ---
        addChannelField = NSTextField()
        addChannelField.placeholderString = "Add channel..."
        addChannelField.font = .systemFont(ofSize: 12)
        addChannelField.translatesAutoresizingMaskIntoConstraints = false
        addChannelField.target = self
        addChannelField.action = #selector(addChannel(_:))
        v.addSubview(addChannelField)

        let addButton = NSButton(title: "+", target: self,
                                 action: #selector(addChannel(_:)))
        addButton.bezelStyle = .rounded
        addButton.font = .systemFont(ofSize: 12)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(addButton)

        // --- Separator ---
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(sep)

        // --- Checkboxes ---
        autoUpdateCheckbox = NSButton(checkboxWithTitle: "Auto-update (30s polling)", target: self,
                                      action: #selector(autoUpdateToggled(_:)))
        autoUpdateCheckbox.font = .systemFont(ofSize: 12)
        autoUpdateCheckbox.state = defaults.bool(forKey: "autoUpdate") ? .on : .off
        autoUpdateCheckbox.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(autoUpdateCheckbox)

        persistentNotificationsCheckbox = NSButton(checkboxWithTitle: "Persistent notifications",
                                                    target: self,
                                                    action: #selector(persistentNotificationsToggled(_:)))
        persistentNotificationsCheckbox.font = .systemFont(ofSize: 12)
        persistentNotificationsCheckbox.state = defaults.bool(forKey: "persistentNotifications") ? .on : .off
        persistentNotificationsCheckbox.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(persistentNotificationsCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self,
                                         action: #selector(launchAtLoginToggled(_:)))
        launchAtLoginCheckbox.font = .systemFont(ofSize: 12)
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.0, *) {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginCheckbox.isHidden = true
        }
        v.addSubview(launchAtLoginCheckbox)

        // --- Constraints ---
        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: v.topAnchor, constant: 20),
            loginButton.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),

            statusLabel.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: 8),

            syncButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 10),
            syncButton.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),

            channelCountLabel.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            channelCountLabel.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 8),

            addChannelField.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 10),
            addChannelField.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            addChannelField.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),

            addButton.centerYAnchor.constraint(equalTo: addChannelField.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
            addButton.widthAnchor.constraint(equalToConstant: 30),

            sep.topAnchor.constraint(equalTo: addChannelField.bottomAnchor, constant: 12),
            sep.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            sep.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),

            autoUpdateCheckbox.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 12),
            autoUpdateCheckbox.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),

            persistentNotificationsCheckbox.topAnchor.constraint(equalTo: autoUpdateCheckbox.bottomAnchor, constant: 6),
            persistentNotificationsCheckbox.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),

            launchAtLoginCheckbox.topAnchor.constraint(equalTo: persistentNotificationsCheckbox.bottomAnchor, constant: 6),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
        ])
    }

    // MARK: - Actions

    @objc private func loginToTwitch(_ sender: NSButton) {
        guard !TwitchAuthManager.shared.clientId.isEmpty else {
            statusLabel.stringValue = "Configuration error"
            statusLabel.textColor = .systemRed
            return
        }
        statusLabel.stringValue = "Waiting for auth..."
        statusLabel.textColor = .systemOrange
        TwitchAuthManager.shared.onAuthComplete = { [weak self] success in
            if success {
                self?.updateConnectionStatus()
                NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
            } else {
                self?.statusLabel.stringValue = "Auth timed out"
                self?.statusLabel.textColor = .systemRed
            }
        }
        TwitchAuthManager.shared.startAuth()
    }

    @objc private func syncFollows(_ sender: NSButton) {
        guard TwitchAuthManager.shared.isAuthenticated else {
            channelCountLabel.stringValue = "Login first"
            channelCountLabel.textColor = .systemRed
            return
        }
        channelCountLabel.stringValue = "Syncing..."
        channelCountLabel.textColor = .secondaryLabelColor
        syncButton.isEnabled = false

        TwitchAPIClient.shared.fetchFollowedChannels { [weak self] channels in
            guard let self = self else { return }
            var streamers = self.defaults.stringArray(forKey: self.streamersKey) ?? []
            let existingSet = Set(streamers.map { $0.lowercased() })
            let newChannels = channels.filter { !existingSet.contains($0.lowercased()) }
            streamers = (streamers + newChannels).sorted()
            self.defaults.set(streamers, forKey: self.streamersKey)
            self.updateChannelCount()
            self.syncButton.isEnabled = true
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    @objc private func addChannel(_ sender: Any) {
        let name = addChannelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var streamers = defaults.stringArray(forKey: streamersKey) ?? []
        guard !streamers.contains(where: { $0.lowercased() == name.lowercased() }) else {
            addChannelField.stringValue = ""
            return
        }
        streamers.append(name)
        streamers.sort()
        defaults.set(streamers, forKey: streamersKey)
        addChannelField.stringValue = ""
        updateChannelCount()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func autoUpdateToggled(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: "autoUpdate")
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func persistentNotificationsToggled(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: "persistentNotifications")
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        if #available(macOS 13.0, *) {
            do {
                if sender.state == .on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                sender.state = sender.state == .on ? .off : .on
            }
        }
    }

    private func updateConnectionStatus() {
        if TwitchAuthManager.shared.isAuthenticated {
            statusLabel.stringValue = "Connected"
            statusLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
            loginButton.title = "Reconnect"
        } else {
            statusLabel.stringValue = "Not connected"
            statusLabel.textColor = .secondaryLabelColor
            loginButton.title = "Login with Twitch"
        }
    }

    private func updateChannelCount() {
        let count = (defaults.stringArray(forKey: streamersKey) ?? []).count
        channelCountLabel.stringValue = count == 0 ? "No channels" : "\(count) channels"
        channelCountLabel.textColor = .secondaryLabelColor
    }
}
