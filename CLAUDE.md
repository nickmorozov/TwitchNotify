# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TwitchNotifier is a **macOS status bar (menu bar) application** that monitors Twitch streamers and shows notifications when they go live. Built with Swift 4.0 and Cocoa/AppKit, targeting macOS 10.13+.

The Xcode project is named "Quotes" (the original working name) — the target, bundle ID (`nwapp.Quotes`), and scheme all use this name.

## Build Commands

```bash
# Build (Release)
xcodebuild build -project Quotes.xcodeproj -scheme Quotes -configuration Release

# Build (Debug)
xcodebuild build -project Quotes.xcodeproj -scheme Quotes -configuration Debug

# Clean build
xcodebuild clean build -project Quotes.xcodeproj -scheme Quotes

# Install CocoaPods dependencies (if using the workspace)
pod install
```

**Note:** No test target exists. There is no test suite.

## Architecture

This is a status bar app (`LSUIElement = true` in Info.plist — no Dock icon). The flow is:

1. **AppDelegate** creates an `NSStatusItem` in the system menu bar and an `NSPopover`
2. Clicking the status bar icon toggles the popover via `togglePopover()`
3. **EventMonitor** listens for global mouse clicks to auto-close the popover when clicking outside
4. **QuotesViewController** is the popover's content — handles streamer name input, status checking, and auto-update polling

### Key Files

| File | Role |
|------|------|
| `Quotes/AppDelegate.swift` | Entry point, status bar item + popover management |
| `Quotes/QuotesViewController.swift` | Main UI logic, Twitch API polling, `checkstreamer()` function |
| `Quotes/EventMonitor.swift` | Global event monitor for click-outside-to-close |
| `Quotes/Quote.swift` | Global constants for Twitch API URLs |
| `Quotes/Base.lproj/Main.storyboard` | UI layout (all IBOutlets/IBActions wired here) |

### State Management

Global variables (module-level in `QuotesViewController.swift`) control app state:
- `changeSegueId` — "0"/"1" string flag indicating if stream is live
- `autoopt` — "0"/"1" toggle for auto-update polling
- `lowprior` — "0"/"1" toggle for low-priority polling (90s vs 17s interval)
- `timetowait` — polling interval base

### Twitch API

Uses the **deprecated Kraken v5 API**: `https://api.twitch.tv/kraken/streams/{name}?client_id=...`

The `checkstreamer()` function (free function in `QuotesViewController.swift`) makes a URLSession request and checks for `"stream_type":"live"` in the serialized JSON string.

## Dependencies

- **CocoaPods** `Just` (HTTP library) declared in Podfile but not imported — URLSession is used directly instead
- **Cocoa/AppKit** (system framework)
