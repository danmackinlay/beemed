# Beeminder Minimal Logger - Remaining Work

## Completed
- UI skeleton (iOS + macOS)
- OAuth + Keychain
- Goals fetch + caching
- Datapoint logging with +1 button
- Offline queue with auto-flush
- Urgency display (time-to-derailment)
- Queue status indicators

## Remaining: watchOS Support (Optional)

Quick "+1" logging from watch without re-implementing auth/queue on watch.

### Architecture
- iPhone app remains source of truth: token + queue + Beeminder API
- Watch sends "log event" to iPhone using WatchConnectivity
- Use `transferUserInfo(_:)` from watch → phone (queued delivery)
- Phone receives via `WCSessionDelegate.didReceiveUserInfo` and enqueues

### Pinned Goals on Watch
- Show first ~20 pinned goals
- Sync pinned list from phone → watch using `updateApplicationContext(_:)`

### Watch UI (minimal)
- List of goals (from last application context)
- Tap goal = "+1"
- Optional: "Other…" row for custom value

### Implementation Steps
1. Add watchOS target in Xcode
2. Set up WCSession on both sides
3. Implement phone → watch `updateApplicationContext` for pinned goals
4. Implement watch → phone `transferUserInfo` for "+1" events
5. Phone receives and enqueues using existing offline queue

### Docs
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [transferUserInfo](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))
- [updateApplicationContext](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:))
- [SwiftUI watchOS tutorial](https://developer.apple.com/tutorials/swiftui/creating-a-watchos-app)
