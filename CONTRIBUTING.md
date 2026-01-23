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

## QA FAQ: Intentional Design Choices

These items frequently come up in code review but are deliberate decisions, not bugs.

### OAuth URL construction uses string interpolation
The redirect URI `beemed://oauth-callback/` contains no characters requiring URL encoding.
ASWebAuthenticationSession matches by scheme, not full URL. Using URLComponents would add
complexity without benefit.

### parseCallback requires username
Beeminder always returns username in OAuth responses. Requiring it simplifies the code and
makes failures obvious. If Beeminder changes this behavior, we'll notice immediately.

### createDatapoint uses JSON body
Beeminder accepts JSON for all endpoints despite docs showing form-encoded examples.
The Encodable pattern is idiomatic Swift and cleaner than manual form encoding.

### No scheduled retry timer
For a minimal +1 logger, retrying on scene activation and network status changes is sufficient.
Users aren't staring at the app waiting for background retries. Adding BGTasks or scheduled
timers would be over-engineering.

### Token required before enqueueing
This is a design choice: if you're not signed in, you can't queue data. The user knows they
need to sign in. We're not building for "disconnected for weeks" scenarios.

### AppModel is a "god object"
For a ~500-line model in a minimal app, keeping state unified is appropriate. Extracting
SyncEngine, GoalsRepository, AuthController etc. would add indirection without benefit.

### Side effects in views (watch sync)
For a simple app, configuring WatchConnectivity via `.onChange` in MainView is fine. The view
is always present when pinned goals change. Using UIApplicationDelegateAdaptor is the legacy pattern.

### AuthService static state
`currentSession` is only accessed from MainActor context (ASWebAuthenticationSession requires it).
There's no concurrency hazard in practice.

### WatchConnectivity configured in view
The session is configured immediately when MainView appears, which happens at app launch.
This is equivalent to configuring in the app delegate but with modern SwiftUI patterns.

### WatchConnectivity on macOS
WatchSessionManager uses `#if canImport(WatchConnectivity)` to compile on macOS (where the
framework doesn't exist). The macOS build excludes watch sync functionality entirely.
