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


## How to watchos

Below is a current (2025/2026) summary of what you need to know to configure, validate, and, if needed, rebuild an iOS + WatchOS companion app setup in modern Xcode — based on the latest Apple documentation and practical guidance.

This covers where the tooling actually expresses the relationship, what keys/settings matter, how builds/install behave, and how to repair it if things go bad.

⸻

1. What makes an iOS app + Watch app a companion pair

The intent

A companion watchOS app is one that is delivered, installed, and associated with an iOS app. Users expect:
	•	The watch app to be installed when the iOS app is installed,
	•	Both apps to be recognized as parts of a single product,
	•	WatchConnectivity to work reliably.

Xcode does not pair them by name prefix or by similar bundle IDs alone; the relationship has to be present in the project’s build metadata + Info.plist.

⸻

2. What Xcode uses as the source of truth

In modern Xcode, the pairing relationship is controlled by Info.plist keys and target embedding metadata, not old UI checkboxes like “Host Application.”
When you added your watch target using the Add Target → Watch App for iOS App template, Xcode should have:
	1.	Created two targets:
	•	Watch App
	•	Watch App Extension (the code that runs on the watch)
	2.	Configured the Info.plist of the watch app with a key:

WKCompanionAppBundleIdentifier = YOUR_IOS_APP_BUNDLE_ID

This key is the definitive signal that the watch app is the companion of your iOS app.

Note: You might not see this file explicitly in the project navigator. To find it, look at Build Settings for the watch app target and inspect the Info.plist file path, or view it in the “Info” tab in Xcode.

⸻

3. What you must check for a valid companion setup

These are the concrete things your project must have:

A. Correct Info.plist keys

Verify the watch app’s Info.plist contains:

WKCompanionAppBundleIdentifier = com.yourcompany.youriOSApp

If this is missing, the watch app will be treated as independent or standalone instead of companion.

Most templates create it for you, but it’s easy to lose if you copied/renamed targets.

B. Matching bundle identifier structure

Typical modern conventions:

iOS app bundle ID:       com.example.beemed
WatchApp bundle ID:      com.example.beemed.watchapp
Watch Extension bundle:  com.example.beemed.watchapp.extension

The exact suffixes aren’t enforced but must be consistent and unique per target.

C. “Supports Running Without iOS App Installation”

This option in the watch target’s deployment settings now signifies independent watch app behavior when checked.
If your intent is a companion app, this should generally be off so the system treats the watch app as dependent on the iOS host.

In current Xcode the old UI field “Host Application” no longer appears; this behavior is now inferred from the above key instead.  

⸻

4. How the build & install system actually works

Simulator
	•	Paired Simulator Required
You must launch a paired iPhone simulator and the corresponding watch simulator to test WatchConnectivity. The act of running the watch app on the paired watch simulator makes WCSession.default.isWatchAppInstalled == true because the watch process is running.
	•	Xcode won’t auto-launch the watch app when running the phone app — you must run both builds.

Real devices
	•	If the watch app is configured as dependent (correct key and bundle IDs), installing the iOS app will install the watch app automatically on the paired Apple Watch.
	•	If pairing/installation fails, WKCompanionAppBundleIdentifier is the first thing to check. Missing or incorrect values are the usual cause.

⸻

5. Rebuilding the companion relationship (if corrupted)

If your project’s linkage appears broken (e.g., watch app installs standalone or doesn’t install with the iOS app), do the following reliably:

Step A — Fix the bundle identifiers

Set bundle IDs so that:
	•	iOS app: com.example.beemed
	•	Watch app: com.example.beemed.watchapp
	•	Watch extension: com.example.beemed.watchapp.extension

Consistency here reduces subtle install errors.

Step B — Add/verify WKCompanionAppBundleIdentifier
	1.	Open the watch app target’s Info.plist (or add one if missing).
	2.	Ensure the key:

WKCompanionAppBundleIdentifier

exists with the iOS app’s bundle ID as value.

If your project has no physical Info.plist for the watch target, create one and assign it in Build Settings → Info.plist File.

Step C — Turn off “Supports Running Without iOS App Installation”

Unless you intend a truly independent watch app, disable this in the watch target’s deployment settings.

Step D — Clean + Full Rebuild
	•	Clean build folder (Product → Clean Build Folder).
	•	Delete derived data.
	•	Rebuild both schemes.
	•	Launch paired simulators and confirm that the watch app runs.
	•	Check runtime:

print(WCSession.default.isWatchAppInstalled)

should be true after starting the watch app.

⸻

6. Final sanity checks
	•	WatchConnectivity will only work if:
	•	The watch app has been launched at least once on the paired simulator/device.
	•	The watch app’s WKCompanionAppBundleIdentifier is correct.
	•	The iOS app is running or can be launched on message receipt.
	•	If messages never arrive but sims are paired, the likely missing piece is correct companion wiring in Info.plist.

⸻

Summary (as a single checklist)
	1.	Two distinct targets: iOS app + watch app (+ watch extension)
	2.	Watch Info.plist has WKCompanionAppBundleIdentifier = <iOS bundle ID>
	3.	Watch bundle IDs consistent and correctly suffixed
	4.	“Supports Running Without iOS App Installation” off (for companion)
	5.	Launch both sides in paired simulator or device
	6.	Runtime checks for WCSession flags
