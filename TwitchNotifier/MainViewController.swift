import Cocoa
import UserNotifications

class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // UI elements
    private var tableView: NSTableView!
    private var gearButton: NSButton!

    // State
    private var streamers: [String] = []
    private var streamerStatus: [String: StreamStatus] = [:]
    private var subscribedChannels: Set<String> = []
    private var lastSeen: [String: Date] = [:]
    private var pollTimer: Timer?
    private let defaults = UserDefaults.standard
    private let streamersKey = "monitoredStreamers"
    private let lastSeenKey = "lastSeenLive"

    // Profile pictures
    private var profileImageURLs: [String: String] = [:]
    private var profileImageCache: [String: NSImage] = [:]

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 320, height: 360)
        streamers = defaults.stringArray(forKey: streamersKey) ?? []
        if let saved = defaults.dictionary(forKey: lastSeenKey) as? [String: Date] {
            lastSeen = saved
        }
        setupUI()
        var authOptions: UNAuthorizationOptions = [.alert, .sound]
        if #available(macOS 12.0, *) { authOptions.insert(.timeSensitive) }
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in }
        if !streamers.isEmpty && TwitchAuthManager.shared.isAuthenticated {
            refreshAllStatuses()
            refreshSubscriptions()
        }
        if defaults.bool(forKey: "autoUpdate") {
            startPolling()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: .preferencesDidChange, object: nil)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  event.keyCode == 36,
                  self.view.window?.firstResponder === self.tableView else {
                return event
            }
            self.openSelectedChannel()
            return nil
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // --- Table View ---
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("StreamerColumn"))
        column.title = "Streamer"

        tableView = NSTableView()
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.target = self
        tableView.doubleAction = #selector(openChannel(_:))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 32
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false

        let tableMenu = NSMenu()
        tableMenu.addItem(NSMenuItem(title: "Remove", action: #selector(removeSelectedChannel(_:)),
                                     keyEquivalent: ""))
        tableView.menu = tableMenu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // --- Gear Button ---
        gearButton = NSButton(image: NSImage(named: NSImage.actionTemplateName)!,
                              target: self, action: #selector(openPreferences(_:)))
        gearButton.bezelStyle = .rounded
        gearButton.isBordered = false
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gearButton)

        // --- Constraints ---
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: gearButton.topAnchor, constant: -4),

            gearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            gearButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            gearButton.widthAnchor.constraint(equalToConstant: 24),
            gearButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    // MARK: - Actions

    @objc private func openPreferences(_ sender: Any) {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openChannel(_ sender: Any) {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        openChannelAtRow(row)
    }

    private func openSelectedChannel() {
        openChannelAtRow(tableView.selectedRow)
    }

    private func openChannelAtRow(_ row: Int) {
        guard row >= 0, row < streamers.count else { return }
        if let url = URL(string: "https://twitch.tv/\(streamers[row])") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func removeSelectedChannel(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0, row < streamers.count else { return }
        streamers.remove(at: row)
        defaults.set(streamers, forKey: streamersKey)
        tableView.reloadData()
    }

    @objc private func preferencesChanged() {
        streamers = defaults.stringArray(forKey: streamersKey) ?? []
        tableView.reloadData()
        if defaults.bool(forKey: "autoUpdate") {
            startPolling()
        } else {
            stopPolling()
        }
        if !streamers.isEmpty && TwitchAuthManager.shared.isAuthenticated {
            refreshAllStatuses()
            refreshSubscriptions()
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
                let wasLive: Bool
                if case .live = previousStatus[name] { wasLive = true } else { wasLive = false }

                if case .live(let title) = status {
                    self.lastSeen[name] = Date()
                    if !wasLive && !previousStatus.isEmpty {
                        self.deliverNotification(streamer: name, title: title)
                    }
                } else if wasLive {
                    // Stream went offline — remove its notification
                    UNUserNotificationCenter.current()
                        .removeDeliveredNotifications(withIdentifiers: ["live-\(name)"])
                }
            }

            let liveCount = results.values.filter {
                if case .live = $0 { return true }; return false
            }.count
            (NSApp.delegate as? AppDelegate)?.updateLiveCount(liveCount)

            self.defaults.set(self.lastSeen, forKey: self.lastSeenKey)
            self.sortStreamers()
            self.tableView.reloadData()
        }
    }

    private func sortStreamers() {
        streamers.sort { a, b in
            let aKey = a.lowercased()
            let bKey = b.lowercased()
            let aLive = { if case .live = self.streamerStatus[aKey] { return true }; return false }()
            let bLive = { if case .live = self.streamerStatus[bKey] { return true }; return false }()
            let aSub = subscribedChannels.contains(aKey)
            let bSub = subscribedChannels.contains(bKey)

            let aPriority = aLive ? (aSub ? 0 : 1) : 2
            let bPriority = bLive ? (bSub ? 0 : 1) : 2
            if aPriority != bPriority { return aPriority < bPriority }

            if !aLive && !bLive {
                let aDate = lastSeen[aKey] ?? .distantPast
                let bDate = lastSeen[bKey] ?? .distantPast
                if aDate != bDate { return aDate > bDate }
            }
            return a.lowercased() < b.lowercased()
        }
    }

    private func refreshSubscriptions() {
        guard !streamers.isEmpty else { return }
        let batches = stride(from: 0, to: streamers.count, by: 100).map {
            Array(streamers[$0..<min($0 + 100, streamers.count)])
        }
        var allIds: [String: String] = [:]
        let group = DispatchGroup()

        for batch in batches {
            group.enter()
            TwitchAPIClient.shared.fetchUserIds(logins: batch) { [weak self] userInfoMap in
                for (login, info) in userInfoMap {
                    allIds[login] = info.id
                    if let url = info.profileImageURL {
                        self?.profileImageURLs[login] = url
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            for (login, urlString) in self.profileImageURLs where self.profileImageCache[login] == nil {
                self.loadProfileImage(for: login, urlString: urlString)
            }
            TwitchAPIClient.shared.checkSubscriptions(logins: self.streamers,
                                                       broadcasterIds: allIds) { subscribed in
                self.subscribedChannels = subscribed
                self.tableView.reloadData()
            }
        }
    }

    private func loadProfileImage(for login: String, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.profileImageCache[login] = image
                self?.tableView.reloadData()
            }
        }.resume()
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
        let content = UNMutableNotificationContent()
        content.title = "\(streamer) is live!"
        content.body = title
        content.sound = .default
        content.userInfo = ["streamer": streamer]
        if defaults.bool(forKey: "persistentNotifications") {
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .timeSensitive
            }
        }
        let request = UNNotificationRequest(identifier: "live-\(streamer)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return streamers.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = streamers[row]
        let key = name.lowercased()
        let isSub = subscribedChannels.contains(key)
        let cell = NSTableCellView()

        // Avatar
        let avatarView = StreamerAvatarView(frame: .zero)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.image = profileImageCache[key]
        avatarView.initials = String(name.prefix(2)).uppercased()
        if case .live = streamerStatus[key] {
            let liveRed = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            let twPurple = NSColor(calibratedRed: 0.569, green: 0.275, blue: 1.0, alpha: 1.0)
            avatarView.borderColor = isSub ? twPurple : liveRed
            avatarView.glowing = true
            avatarView.dimmed = false
        } else if isSub {
            avatarView.borderColor = NSColor(calibratedRed: 0.569, green: 0.275, blue: 1.0, alpha: 1.0)
            avatarView.glowing = false
            avatarView.dimmed = true
        } else {
            avatarView.borderColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
            avatarView.glowing = false
            avatarView.dimmed = true
        }
        cell.addSubview(avatarView)

        // Name label
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(nameLabel)

        // Status badge
        let statusText: String
        let statusColor: NSColor
        if case .live(let title) = streamerStatus[key] {
            statusText = isSub ? "SUB LIVE" : "LIVE"
            statusColor = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            nameLabel.toolTip = title
        } else if isSub {
            statusText = "SUB"
            statusColor = NSColor(calibratedRed: 0.56, green: 0.28, blue: 1.0, alpha: 1.0)
        } else if let seen = lastSeen[key] {
            statusText = relativeTime(since: seen)
            statusColor = .tertiaryLabelColor
        } else {
            statusText = "offline"
            statusColor = .tertiaryLabelColor
        }

        let badge = NSTextField(labelWithString: statusText)
        badge.font = .boldSystemFont(ofSize: 10)
        badge.textColor = statusColor
        badge.alignment = .right
        badge.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(badge)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            avatarView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 30),
            avatarView.heightAnchor.constraint(equalToConstant: 30),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 6),
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

// MARK: - StreamerAvatarView

private final class StreamerAvatarView: NSView {
    var image: NSImage?
    var borderColor: NSColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
    var glowing = false
    var dimmed = false
    var initials = ""

    override init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Leave 3px margin on each side so the glow shadow isn't clipped
        let circleRect = bounds.insetBy(dx: 3, dy: 3)

        // Glow pass — drawn before clipping so it extends into the margin
        if glowing {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = borderColor.withAlphaComponent(0.75)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            shadow.set()
            borderColor.setStroke()
            let glowPath = NSBezierPath(ovalIn: circleRect)
            glowPath.lineWidth = 2
            glowPath.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Clip to circle and draw image or initials
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(ovalIn: circleRect)
        clip.addClip()
        let alpha: CGFloat = dimmed ? 0.55 : 1.0
        if let img = image {
            img.draw(in: circleRect, from: .zero, operation: .sourceOver, fraction: alpha)
        } else {
            NSColor(calibratedWhite: 0.28, alpha: alpha).setFill()
            clip.fill()
            let font = NSFont.boldSystemFont(ofSize: circleRect.width * 0.32)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(alpha)
            ]
            let str = initials as NSString
            let sz = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: circleRect.midX - sz.width / 2,
                                 y: circleRect.midY - sz.height / 2),
                     withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Border ring drawn on top (not clipped, so it straddles the edge)
        borderColor.withAlphaComponent(dimmed ? 0.45 : 1.0).setStroke()
        let borderPath = NSBezierPath(ovalIn: circleRect)
        borderPath.lineWidth = 2
        borderPath.stroke()
    }
}
