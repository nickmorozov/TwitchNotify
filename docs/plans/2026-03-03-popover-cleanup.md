# Popover Cleanup, Right-Click Menu, and Sync Follows — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the broken storyboard UI with a clean programmatic popover, add right-click quit menu, and let users sync their followed Twitch channels.

**Architecture:** Fully programmatic NSViewController (drop storyboard outlets), NSTableView for streamer list, batch Helix API calls for status checks, UserDefaults for persisting the channel list.

**Tech Stack:** Swift 5, AppKit, Helix API, macOS Keychain, BSD sockets (existing auth server)

**No test target exists.** Verification is build + manual launch.

---

### Task 1: Add OAuth Scope and API Constants

**Files:**
- Modify: `Quotes/TwitchAuthManager.swift:21` — add `user:read:follows` scope
- Modify: `Quotes/Quote.swift` — add Helix URLs for users and followed channels

**Step 1: Add scope to OAuth URL**

In `Quotes/TwitchAuthManager.swift`, change line 21 from:
```swift
            + "&scope="
```
to:
```swift
            + "&scope=user:read:follows"
```

**Step 2: Add Helix endpoint constants**

In `Quotes/Quote.swift`, add to the `TwitchConstants` struct:
```swift
    static let helixUsersURL = "https://api.twitch.tv/helix/users"
    static let helixFollowedURL = "https://api.twitch.tv/helix/channels/followed"
```

**Step 3: Build to verify**

```bash
xcodebuild build -project /Users/nick/Projects/Repos/TwitchNotify/TwitchNotify.xcodeproj -target TwitchNotify -configuration Release 2>&1 | grep -E "BUILD|error:"
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Quotes/TwitchAuthManager.swift Quotes/Quote.swift
git commit -m "feat: add user:read:follows scope and Helix endpoint constants"
```

---

### Task 2: Add Batch Stream Check and Fetch Followed Channels to API Client

**Files:**
- Modify: `Quotes/TwitchAPIClient.swift` — add `checkStreams(usernames:)`, `fetchFollowedChannels(completion:)`

**Step 1: Add batch stream check method**

Add to `TwitchAPIClient` after the existing `checkStream` method. This method takes an array of usernames and returns a dictionary mapping username → StreamStatus. Helix supports up to 100 `user_login` params in one request:

```swift
    func checkStreams(usernames: [String], completion: @escaping ([String: StreamStatus]) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion([:]) }
            return
        }
        guard !usernames.isEmpty else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        let queryItems = usernames.map { "user_login=\($0)" }.joined(separator: "&")
        let urlString = "\(TwitchConstants.helixStreamsURL)?\(queryItems)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([:]) }
                return
            }

            var results: [String: StreamStatus] = [:]
            // Mark all as offline first
            for name in usernames {
                results[name.lowercased()] = .offline
            }
            // Overwrite with live status for those streaming
            for stream in dataArray {
                if let login = stream["user_login"] as? String,
                   let title = stream["title"] as? String {
                    results[login.lowercased()] = .live(title: title)
                }
            }
            DispatchQueue.main.async { completion(results) }
        }.resume()
    }
```

**Step 2: Add fetch followed channels method**

This is a two-step API call: first get the user's own ID, then fetch their followed channels with pagination.

```swift
    func fetchFollowedChannels(completion: @escaping ([String]) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        // Step 1: Get own user ID
        guard let usersURL = URL(string: TwitchConstants.helixUsersURL) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        var userReq = URLRequest(url: usersURL)
        userReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        userReq.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: userReq) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let users = json["data"] as? [[String: Any]],
                  let userId = users.first?["id"] as? String else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            self?.fetchAllFollowed(userId: userId, clientId: clientId, token: token,
                                   accumulated: [], cursor: nil, completion: completion)
        }.resume()
    }

    private func fetchAllFollowed(userId: String, clientId: String, token: String,
                                  accumulated: [String], cursor: String?,
                                  completion: @escaping ([String]) -> Void) {
        var urlString = "\(TwitchConstants.helixFollowedURL)?user_id=\(userId)&first=100"
        if let cursor = cursor {
            urlString += "&after=\(cursor)"
        }
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(accumulated) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion(accumulated) }
                return
            }

            let names = dataArray.compactMap { $0["broadcaster_login"] as? String }
            let all = accumulated + names

            // Check for pagination
            if let pagination = json["pagination"] as? [String: Any],
               let nextCursor = pagination["cursor"] as? String,
               !names.isEmpty {
                self?.fetchAllFollowed(userId: userId, clientId: clientId, token: token,
                                      accumulated: all, cursor: nextCursor, completion: completion)
            } else {
                DispatchQueue.main.async { completion(all) }
            }
        }.resume()
    }
```

**Step 3: Build to verify**

```bash
xcodebuild build -project /Users/nick/Projects/Repos/TwitchNotify/TwitchNotify.xcodeproj -target TwitchNotify -configuration Release 2>&1 | grep -E "BUILD|error:"
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Quotes/TwitchAPIClient.swift
git commit -m "feat: add batch stream check and fetch followed channels API methods"
```

---

### Task 3: Rewrite AppDelegate — Right-Click Menu + Cleanup

**Files:**
- Modify: `Quotes/AppDelegate.swift` — full rewrite

**Step 1: Replace AppDelegate.swift entirely**

The key changes:
- Left-click → popover (existing)
- Right-click → NSMenu with "Quit Twitch Notify"
- Remove dead `printQuote`, `constructMenu` methods
- Use `button.sendAction(on:)` to receive both left and right click events, then check `NSApp.currentEvent` to decide behavior

Replace `Quotes/AppDelegate.swift` with:
```swift
import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let popover = NSPopover()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let button = statusItem.button {
            if let img = NSImage(named: NSImage.Name("StatusBarButtonImage")) {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "TN"
            }
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.contentViewController = QuotesViewController.freshController()
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
        menu.addItem(NSMenuItem(title: "Quit Twitch Notify",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // Reset so left-click works again
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project /Users/nick/Projects/Repos/TwitchNotify/TwitchNotify.xcodeproj -target TwitchNotify -configuration Release 2>&1 | grep -E "BUILD|error:"
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Quotes/AppDelegate.swift
git commit -m "feat: add right-click context menu with Quit, clean up AppDelegate"
```

---

### Task 4: Rewrite QuotesViewController — Fully Programmatic UI

**Files:**
- Modify: `Quotes/QuotesViewController.swift` — complete rewrite

**Step 1: Replace QuotesViewController.swift entirely**

This is the largest change. Key points:
- Override `loadView()` to create view without storyboard
- All UI is programmatic: auth section, sync button, NSTableView for streamers, bottom bar
- `NSTableViewDataSource`/`NSTableViewDelegate` for the streamer list
- Batch polling with transition detection (offline→live triggers notification)
- UserDefaults persistence for the channel list
- `freshController()` no longer uses storyboard

Replace `Quotes/QuotesViewController.swift` with:
```swift
import Cocoa

class QuotesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // UI elements
    private var clientIdField: NSTextField!
    private var connectButton: NSButton!
    private var statusLabel: NSTextField!
    private var syncButton: NSButton!
    private var channelCountLabel: NSTextField!
    private var tableView: NSTableView!
    private var autoUpdateCheckbox: NSButton!
    private var quitButton: NSButton!

    // State
    private var streamers: [String] = []
    private var streamerStatus: [String: StreamStatus] = [:]
    private var pollTimer: Timer?
    private let defaults = UserDefaults.standard
    private let streamersKey = "monitoredStreamers"

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 380))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 320, height: 380)
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
        let idLabel = NSTextField(labelWithString: "Client ID:")
        idLabel.font = .systemFont(ofSize: 11)
        idLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(idLabel)

        clientIdField = NSTextField()
        clientIdField.placeholderString = "Twitch Client ID"
        clientIdField.font = .systemFont(ofSize: 11)
        clientIdField.translatesAutoresizingMaskIntoConstraints = false
        if let savedId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id") {
            clientIdField.stringValue = savedId
        }
        view.addSubview(clientIdField)

        connectButton = NSButton(title: "Connect", target: self,
                                 action: #selector(connectToTwitch(_:)))
        connectButton.bezelStyle = .rounded
        connectButton.font = .systemFont(ofSize: 11)
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectButton)

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
            idLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            idLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            clientIdField.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 4),
            clientIdField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            clientIdField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            connectButton.topAnchor.constraint(equalTo: clientIdField.bottomAnchor, constant: 6),
            connectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            statusLabel.centerYAnchor.constraint(equalTo: connectButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: connectButton.trailingAnchor, constant: 8),

            sep1.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 8),
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
        return streamers.isEmpty ? "No channels" : "\(streamers.count) channels"
    }

    // MARK: - Actions

    @objc private func connectToTwitch(_ sender: NSButton) {
        let clientId = clientIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty else {
            statusLabel.stringValue = "Enter Client ID"
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
        TwitchAuthManager.shared.startAuth(clientId: clientId)
    }

    @objc private func syncFollows(_ sender: NSButton) {
        guard TwitchAuthManager.shared.isAuthenticated else {
            channelCountLabel.stringValue = "Connect first"
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
            connectButton.title = "Reconnect"
        } else {
            statusLabel.stringValue = "Not connected"
            statusLabel.textColor = .secondaryLabelColor
            connectButton.title = "Connect"
        }
    }

    // MARK: - Polling

    private func refreshAllStatuses() {
        guard !streamers.isEmpty else { return }
        TwitchAPIClient.shared.checkStreams(usernames: streamers) { [weak self] results in
            guard let self = self else { return }
            let previousStatus = self.streamerStatus
            self.streamerStatus = results

            // Notify on offline → live transitions
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

        let statusText: String
        let statusColor: NSColor
        if case .live(let title) = streamerStatus[name.lowercased()] {
            statusText = "LIVE"
            statusColor = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            nameLabel.toolTip = title
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
            nameLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
        return cell
    }

    // MARK: - Factory

    static func freshController() -> QuotesViewController {
        return QuotesViewController()
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project /Users/nick/Projects/Repos/TwitchNotify/TwitchNotify.xcodeproj -target TwitchNotify -configuration Release 2>&1 | grep -E "BUILD|error:"
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Quotes/QuotesViewController.swift
git commit -m "feat: fully programmatic popover with streamer list, sync follows, and quit button"
```

---

### Task 5: Install and Verify

**Step 1: Kill existing app, copy, launch**

```bash
kill $(pgrep -f "Quotes\|TwitchNotify") 2>/dev/null
sleep 1
rm -rf ~/Applications/"Twitch Notify.app"
cp -R build/Release/TwitchNotify.app ~/Applications/"Twitch Notify.app"
open ~/Applications/"Twitch Notify.app"
```

**Step 2: Manual verification checklist**

- [ ] Icon appears in menu bar
- [ ] Left-click opens popover with clean layout
- [ ] Client ID field + Connect button visible at top
- [ ] Sync Follows button visible
- [ ] Scrollable streamer list area visible
- [ ] Auto-update checkbox + Quit button at bottom
- [ ] Right-click on menu bar icon shows "Quit Twitch Notify" menu
- [ ] Quit button in popover terminates app
- [ ] Entering Client ID and clicking Connect opens browser auth
- [ ] After auth, clicking Sync Follows populates the streamer list
- [ ] Live streamers show red "LIVE" badge
- [ ] Auto-update checkbox starts polling

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: build verification complete"
```
