# Popover Cleanup, Right-Click Menu, and Sync Follows

## Context

The TwitchNotify popover has storyboard UI remnants overlapping with programmatic auth UI. The app needs a Quit option, a right-click context menu, and the ability to import followed channels from Twitch.

## Right-Click Context Menu

AppDelegate handles left-click vs right-click on the status bar icon:
- **Left-click**: opens popover (current behavior)
- **Right-click**: shows an NSMenu with "Quit Twitch Notify" (Cmd+Q)

Intercept via `sendAction` + `NSApp.currentEvent` to detect right-click.

## Popover Layout (Fully Programmatic)

Drop all storyboard IBOutlet dependencies. Build entire UI programmatically:

```
┌─────────────────────────────────┐
│ Client ID: [_______________]    │
│ [Connect]  Connected            │
│─────────────────────────────────│
│ [Sync Follows]    12 channels   │
│─────────────────────────────────│
│   streamer1              LIVE   │
│   streamer2            offline  │
│   streamer3            offline  │
│   ... (scrollable NSTableView)  │
│─────────────────────────────────│
│ [Auto-update]            [Quit] │
└─────────────────────────────────┘
```

- **Top**: Client ID field + Connect button + status label
- **Middle**: "Sync Follows" button + channel count, scrollable NSTableView with live/offline per streamer
- **Bottom**: Auto-update checkbox + Quit button
- `preferredContentSize` ~320x380

## Sync Follows

- New `TwitchAPIClient.fetchFollowedChannels` method
  - `GET /helix/users` to get own user ID
  - `GET /helix/channels/followed?user_id={id}` with pagination
  - Requires `user:read:follows` scope in OAuth flow
- Stores followed channel names in UserDefaults
- On sync, replaces streamer list and checks status

## Polling Changes

- Poll all monitored streamers in one request (Helix supports up to 100 `user_login` params)
- Notifications fire for offline-to-live transitions only
- Single timer, configurable interval via auto-update checkbox

## Files Modified

- `Quotes/QuotesViewController.swift` — full UI rewrite, drop storyboard outlets
- `Quotes/AppDelegate.swift` — right-click menu, clean up dead code
- `Quotes/TwitchAPIClient.swift` — add fetchFollowedChannels, batch stream check
- `Quotes/TwitchAuthManager.swift` — add `user:read:follows` scope
- `Quotes/Base.lproj/Main.storyboard` — remove wired outlets (or leave as empty shell)
