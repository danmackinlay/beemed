# Beeminder Minimal Logger (beemed)

A SwiftUI app for quick +1 logging to [Beeminder](https://www.beeminder.com) goals with offline-first architecture.

> **Warning**: This project is 100% vibe-coded with AI assistance. It works for the author's use case but has not been extensively tested. Use at your own risk, and please don't blame the bees if your datapoints go missing.

## Features

- **OAuth login** - Secure authentication with Beeminder
- **Goal pinning** - Pin your most-used goals for quick access
- **Offline queue** - Log datapoints even without internet; syncs when back online
- **Urgency display** - See which goals need attention first

## Platforms

- iOS 26
- macOS 26
- watchOS 26 (optional)

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

# Build for macOS
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

## License

MIT License - see [LICENSE](LICENSE) for details.
