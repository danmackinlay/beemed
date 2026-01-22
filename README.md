# Beeminder Minimal Logger (beemed)

A SwiftUI app for quick +1 logging to [Beeminder](https://www.beeminder.com) goals with offline-first architecture.

## Features

- **OAuth login** - Secure authentication with Beeminder
- **Goal pinning** - Pin your most-used goals for quick access
- **Offline queue** - Log datapoints even without internet; syncs when back online
- **Urgency display** - See which goals need attention first

## Platforms

- iOS 26
- macOS 26
- watchOS 26 (optional)

## Development

Requires Xcode 26.

```bash
# Clone the repo
git clone https://github.com/yourusername/beemed.git
cd beemed

# Open in Xcode
open beemed.xcodeproj

# Or build from command line
xcodebuild -project beemed.xcodeproj -scheme beemed -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## License

MIT License - see [LICENSE](LICENSE) for details.
