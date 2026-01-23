# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Beeminder Minimal Logger - a SwiftUI multiplatform app (iOS 26 + macOS 26, optional watchOS 26) for quick +1 logging to Beeminder goals with offline-first architecture.

## Build Commands

```bash
# Build for iOS simulator
xcodebuild -project beemed.xcodeproj -scheme beemed -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for macOS
xcodebuild -project beemed.xcodeproj -scheme beemed -destination 'platform=macOS' build

# Build for watchOS simulator
xcodebuild -project beemed.xcodeproj -scheme beemedWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build

# Run tests (when added)
xcodebuild -project beemed.xcodeproj -scheme beemed -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Architecture

**Target:** iOS 26 / macOS 26 minimum (no backwards compatibility needed)

**Tech Stack:**
- SwiftUI for UI (multiplatform)
- URLSession (async/await) for networking
- ASWebAuthenticationSession for Beeminder OAuth
- Keychain for token storage
- JSON file in Application Support for offline queue
- NWPathMonitor for network detection

**Beeminder API:**
- Base URL: `https://www.beeminder.com/api/v1/` (must use www, HTTPS)
- Always include `requestid` for datapoints (idempotency key for safe retries)
- Use `emaciated=true` when fetching goals to strip bulky road data

**Offline-First Pattern:**
1. User taps +1 → create queued item with UUID, write to disk
2. Attempt immediate upload
3. On success: remove from queue
4. On failure: keep in queue, show "Queued: N" in UI
5. Flush triggers: app launch, foreground, NWPathMonitor satisfied

## Key Files

- `beemed/beemedApp.swift` - App entry point
- `beemed/Views/MainView.swift` - Main UI
- `beemed/Services/WatchSessionManager.swift` - WatchConnectivity handling (iOS side)
- `beemedWatch/beemedWatchApp.swift` - Watch app entry point
- `beemedWatch/ContentView.swift` - Watch UI
- `plans/master_plan.md` - Detailed implementation plan with milestones

## Development Milestones

See `plans/master_plan.md` for full details. Build order:
A. UI skeleton → B. OAuth + Keychain → C. Goals fetch + caching → D. Log +1 → E. Offline queue → F. watchOS (optional)
