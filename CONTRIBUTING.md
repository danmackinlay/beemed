# Contributing to Beemed

## Building

Requires Xcode 26 (beta) with iOS 26 / macOS 26 / watchOS 26 SDKs.

### Quick Start

```bash
# Clone the repo
git clone https://github.com/danmackinlay/beemed.git
cd beemed

# Open in Xcode
open beemed.xcodeproj
```

### Command Line Builds

```bash
# Build for iOS Simulator
xcodebuild -project beemed.xcodeproj -scheme beemed \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for macOS (see Known Issues below)
xcodebuild -project beemed.xcodeproj -scheme beemed \
  -destination 'platform=macOS' build

# Build watchOS companion app
xcodebuild -project beemed.xcodeproj -scheme beemedWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build
```

### Running Tests

```bash
xcodebuild -project beemed.xcodeproj -scheme beemed \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Troubleshooting

- **Simulator not found**: Run `xcrun simctl list devices` to see available simulators and adjust the destination name accordingly.
- **Xcode version mismatch**: This project targets iOS/macOS/watchOS 26 which requires Xcode 26 beta.

## Known Issues

### macOS Build Fails with WatchConnectivity Error

**Symptom:**
```
beemed/Services/WatchSessionManager.swift:8:8: error: Unable to find module dependency: 'WatchConnectivity'
import WatchConnectivity
```

**Cause:** `WatchConnectivity` framework is only available on iOS, not macOS. The `WatchSessionManager.swift` file imports it unconditionally.

**Workaround:** The macOS target isn't actively supported. Use iOS Simulator for development and testing:
```bash
xcodebuild -scheme beemed -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**Proper Fix (if macOS support needed):** Wrap the entire `WatchSessionManager.swift` contents in `#if os(iOS)` or exclude the file from the macOS target in Xcode project settings.

## Design Decisions

### OAuth Callback Parsing
Beeminder's OAuth uses **query parameters** (`?access_token=...`), not URL fragments (`#access_token=...`).
The code intentionally parses only `url.query`. If you're adapting this for another OAuth provider that uses
implicit grant with fragments, you'll need to also check `url.fragment`.

### Offline-First Queue Semantics
- Datapoints are **always** persisted to disk before attempting upload
- Queue items are **never** deleted on transient errors (network, 5xx, 401)
- Items are only removed after successful upload or permanent validation errors (422)
- After reauth, the queue flushes automatically

### Why No "Stuck" Item UI?
We chose to retry forever with exponential backoff rather than surface "stuck" items requiring user intervention.
For a simple +1 logger, silent retry is better UX than error management screens.

### Protocol-Based DI Without Tests
Protocols exist for `BeeminderAPI` and `TokenStore` to enable future testing at the network boundary.
Store protocols (`QueueStoreProtocol`, `GoalsStoreProtocol`) exist for consistency but aren't heavily exercised.
This is intentional pragmatism - add tests when the complexity warrants it.

### @Observable vs @StateObject
This app uses the iOS 17+ `@Observable` macro exclusively. No `ObservableObject` or `@Published`.

### Sendable Conformance
`KeychainTokenStore` and `LiveBeeminderAPI` are `Sendable` because they're immutable (only `let` properties).

## Code Style

- Minimize abstraction layers - prefer direct code over indirection
- Delete unused code rather than commenting it out
- No backwards-compatibility shims - just change the code
- Avoid over-engineering for hypothetical future requirements
