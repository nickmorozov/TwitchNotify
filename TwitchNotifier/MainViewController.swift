import Cocoa

class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // UI elements
    private var loginButton: NSButton!
    private var statusLabel: NSTextField!
    private var syncButton: NSButton!
    private var channelCountLabel: NSTextField!
    private var tableView: NSTableView!
    private var autoUpdateCheckbox: NSButton!
    private var quitButton: NSButton!

    // State
    private var streamers: [String] = []
    private var streamerStatus: [String: StreamStatus] = [:]
    private var subscribedChannels: Set<String> = []
    private var pollTimer: Timer?
    private let defaults = UserDefaults.standard
    private let streamersKey = "monitoredStreamers"

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 320, height: 360)
        streamers = defaults.stringArray(forKey: streamersKey) ?? []
        setupUI()
        updateConnectionStatus()
        if !streamers.isEmpty && TwitchAuthManager.shared.isAuthenticated {
            refreshAllStatuses()
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // --- Auth Section ---
        loginButton = NSButton(title: "Login with Twitch", target: self,
                               action: #selector(loginToTwitch(_:)))
        loginButton.bezelStyle = .rounded
        loginButton.font = .systemFont(ofSize: 11)
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loginButton)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // --- Separator 1 ---
        let sep1 = NSBox()
        sep1.boxType = .separator
        sep1.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep1)

        // --- Sync Section ---
        syncButton = NSButton(title: "Sync Follows", target: self,
                              action: #selector(syncFollows(_:)))
        syncButton.bezelStyle = .rounded
        syncButton.font = .systemFont(ofSize: 11)
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(syncButton)

        channelCountLabel = NSTextField(labelWithString: channelCountText())
        channelCountLabel.font = .systemFont(ofSize: 10)
        channelCountLabel.textColor = .secondaryLabelColor
        channelCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(channelCountLabel)

        // --- Separator 2 ---
        let sep2 = NSBox()
        sep2.boxType = .separator
        sep2.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep2)

        // --- Table View ---
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("StreamerColumn"))
        column.title = "Streamer"

        tableView = NSTableView()
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // --- Separator 3 ---
        let sep3 = NSBox()
        sep3.boxType = .separator
        sep3.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep3)

        // --- Bottom Bar ---
        autoUpdateCheckbox = NSButton(checkboxWithTitle: "Auto-update", target: self,
                                      action: #selector(autoUpdateToggled(_:)))
        autoUpdateCheckbox.font = .systemFont(ofSize: 11)
        autoUpdateCheckbox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(autoUpdateCheckbox)

        quitButton = NSButton(title: "Quit", target: self,
                              action: #selector(quitApp(_:)))
        quitButton.bezelStyle = .rounded
        quitButton.font = .systemFont(ofSize: 11)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(quitButton)

        // --- Constraints ---
        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            loginButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            statusLabel.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: 8),

            sep1.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 8),
            sep1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            sep1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            syncButton.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 8),
            syncButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            channelCountLabel.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            channelCountLabel.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 8),

            sep2.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 8),
            sep2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            sep2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            sep3.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            sep3.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            sep3.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            autoUpdateCheckbox.topAnchor.constraint(equalTo: sep3.bottomAnchor, constant: 8),
            autoUpdateCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            autoUpdateCheckbox.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),

            quitButton.centerYAnchor.constraint(equalTo: autoUpdateCheckbox.centerYAnchor),
            quitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func channelCountText() -> String {
        let subCount = subscribedChannels.count
        if streamers.isEmpty { return "No channels" }
        if subCount > 0 {
            return "\(streamers.count) followed, \(subCount) subscribed"
        }
        return "\(streamers.count) channels"
    }

    // MARK: - Actions

    @objc private func loginToTwitch(_ sender: NSButton) {
        guard TwitchAuthManager.shared.clientId != nil else {
            statusLabel.stringValue = "No Client ID configured"
            statusLabel.textColor = .systemRed
            return
        }
        statusLabel.stringValue = "Waiting for auth..."
        statusLabel.textColor = .systemOrange
        TwitchAuthManager.shared.onAuthComplete = { [weak self] success in
            if success {
                self?.updateConnectionStatus()
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
            self.streamers = channels.sorted()
            self.defaults.set(self.streamers, forKey: self.streamersKey)
            self.channelCountLabel.stringValue = self.channelCountText()
            self.channelCountLabel.textColor = .secondaryLabelColor
            self.syncButton.isEnabled = true
            self.tableView.reloadData()
            self.refreshAllStatuses()
            self.refreshSubscriptions()
        }
    }

    @objc private func autoUpdateToggled(_ sender: NSButton) {
        if sender.state == .on {
            startPolling()
        } else {
            stopPolling()
        }
    }

    @objc private func quitApp(_ sender: NSButton) {
        NSApp.terminate(nil)
    }

    // MARK: - Connection Status

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

    // MARK: - Polling

    private func refreshAllStatuses() {
        guard !streamers.isEmpty else { return }
        TwitchAPIClient.shared.checkStreams(usernames: streamers) { [weak self] results in
            guard let self = self else { return }
            let previousStatus = self.streamerStatus
            self.streamerStatus = results

            for (name, status) in results {
                if case .live(let title) = status {
                    let wasLive: Bool
                    if case .live = previousStatus[name] { wasLive = true } else { wasLive = false }
                    if !wasLive && !previousStatus.isEmpty {
                        self.deliverNotification(streamer: name, title: title)
                    }
                }
            }
            self.tableView.reloadData()
        }
    }

    private func refreshSubscriptions() {
        guard !streamers.isEmpty else { return }
        // Fetch broadcaster IDs for all followed channels (batches of 100)
        let batches = stride(from: 0, to: streamers.count, by: 100).map {
            Array(streamers[$0..<min($0 + 100, streamers.count)])
        }
        var allIds: [String: String] = [:]
        let group = DispatchGroup()

        for batch in batches {
            group.enter()
            TwitchAPIClient.shared.fetchUserIds(logins: batch) { ids in
                for (k, v) in ids { allIds[k] = v }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            TwitchAPIClient.shared.checkSubscriptions(logins: self.streamers,
                                                       broadcasterIds: allIds) { subscribed in
                self.subscribedChannels = subscribed
                self.channelCountLabel.stringValue = self.channelCountText()
                self.tableView.reloadData()
            }
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshAllStatuses()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func deliverNotification(streamer: String, title: String) {
        let notification = NSUserNotification()
        notification.title = "\(streamer) is live!"
        notification.informativeText = title
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return streamers.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = streamers[row]
        let cell = NSTableCellView()

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(nameLabel)

        // Subscription badge
        let isSub = subscribedChannels.contains(name.lowercased())

        let statusText: String
        let statusColor: NSColor
        if case .live(let title) = streamerStatus[name.lowercased()] {
            statusText = isSub ? "SUB LIVE" : "LIVE"
            statusColor = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            nameLabel.toolTip = title
        } else {
            statusText = isSub ? "SUB" : "offline"
            statusColor = isSub ? NSColor(calibratedRed: 0.56, green: 0.28, blue: 1.0, alpha: 1.0)
                                : .tertiaryLabelColor
        }

        let badge = NSTextField(labelWithString: statusText)
        badge.font = .boldSystemFont(ofSize: 10)
        badge.textColor = statusColor
        badge.alignment = .right
        badge.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(badge)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
        return cell
    }

    // MARK: - Factory

    static func freshController() -> MainViewController {
        return MainViewController()
    }
}
