Beeminder Minimal Logger (iOS 26 + macOS Tahoe 26, optional watchOS 26)

Design decisions from your answers:
    •    Goals: support any number of “pinned” goals. Keep UI usable by (a) always showing pinned only on the main screen, (b) providing search in the “Add/Remove pinned goals” screen, and (c) optionally showing only the first ~20 pinned on watch (watch screen constraints).
    •    Logging: default action is +1 with one tap.
    •    Back-compat: target the 26.x SDKs and don’t spend time on older OS shims.
    •    watchOS: “easy mode” = watch app does not talk to Beeminder. It sends “log +1” intents to the iPhone via WatchConnectivity; the iPhone app owns auth + offline queue + Beeminder API calls.

1) Tech stack (minimal, offline-first)

Core:
    •    SwiftUI for UI (multiplatform iOS + macOS, plus watchOS target later).
    •    URLSession (async/await) for networking.
    •    Auth: ASWebAuthenticationSession for Beeminder OAuth.  ￼
    •    Token storage: Keychain.  ￼
    •    Offline queue: a small JSON file (Codable) in Application Support (simple, robust).
    •    Network detection: NWPathMonitor to trigger background flush when connectivity returns.  ￼

Beeminder API requirements that shape architecture:
    •    Use canonical API base URL exactly https://www.beeminder.com/api/v1/ (HTTPS + www) or POSTs may “break opaquely” due to redirect behavior.  ￼
    •    Always include requestid for datapoints; it’s an idempotency key (safe retries; upsert semantics).  ￼

2) Minimal product spec

Main screen (iOS + macOS)
    •    Search bar (filters pinned goals only).
    •    List of pinned goals (any number; scrolling list).
    •    Each goal row:
    •    Title + slug (small)
    •    Big button: “+1”
    •    Secondary action: “…” (sheet) for custom value + optional comment (still minimal)
    •    Status strip:
    •    “Queued: N” (pending offline submissions)
    •    “Sync: Online/Offline” (optional)

Settings screen
    •    “Pinned goals” management:
    •    Shows all Beeminder goals (active) with a toggle “Pinned”.
    •    Search field to handle lots of goals without fancy pagination UI. (SwiftUI search modifiers.)  ￼
    •    “Sign out” (clears token + local cached goal list; queue behavior is your choice—see below).

Defaults
    •    Logging default is +1 with timestamp = now.
    •    Sorting:
    •    When showing “All goals” in settings, keep Beeminder’s default ordering (API returns goals sorted by urgency / time-to-derailment).  ￼

3) Beeminder API integration plan

3.1 Auth (OAuth, plus a fallback)

Use the Beeminder “Client OAuth” flow described in their API reference: register app, send user to /apps/authorize?client_id=…&redirect_uri=…&response_type=token, receive access_token + username, then call API with token (query param or Authorization: Bearer).  ￼

In-app implementation:
    •    Use ASWebAuthenticationSession to open the authorize URL and capture the callback URL.  ￼
    •    Redirect URI should be a custom URL scheme owned by your app (e.g. beemed://oauth-callback).
    •    Store:
    •    access_token in Keychain.  ￼
    •    username + other lightweight settings in UserDefaults / @AppStorage.  ￼

Fallback (optional but practical):
    •    Allow manual entry of personal token from Beeminder’s auth_token.json endpoint; Beeminder warns not to confuse auth_token vs access_token.  ￼

3.2 Fetch goals

Endpoint:
    •    GET /users/me/goals.json (with OAuth token) or /users/<username>/goals.json (with personal auth_token).  ￼

Performance tweak for “many goals”:
    •    Use emaciated=true to strip bulky road data.  ￼

Cache:
    •    Persist a lightweight cached goal list locally ([slug, title]) so pinned goals render even when offline.

3.3 Create datapoint (single)

Endpoint:
    •    POST /users/u/goals/g/datapoints.json with:
    •    value (number)
    •    timestamp (unix seconds) — pass it explicitly so offline logs keep correct time  ￼
    •    comment (optional)
    •    requestid (UUID string) — idempotency key / upsert  ￼

Offline safety:
    •    Generate UUID once at log time and reuse on retries; Beeminder describes duplicate handling and “upsert endpoint” semantics.  ￼

Optional later:
    •    Batch flush using create_all.json once you’re confident the queue is correct.  ￼

4) Offline-first behavior (core “heterodox” requirement)

Queue model (Codable)

Each queued item:
    •    requestID: String (UUID; used as Beeminder requestid)
    •    goalSlug: String
    •    value: Double
    •    timestamp: Int (when you logged it)
    •    comment: String?
    •    createdAt: Int
    •    attemptCount: Int
    •    lastAttemptAt: Int?
    •    lastError: String?

Persistence:
    •    JSON file in Application Support (atomic writes).

Write-path:
    1.    Tap “+1”
    2.    Create queued item immediately, write to disk.
    3.    Attempt immediate upload (best effort).
    4.    On success: remove from queue.
    5.    On failure: keep queue; UI shows “Queued: N”.

Flush triggers:
    •    App launch
    •    App becomes active/foreground
    •    When NWPathMonitor changes to satisfied (network available).  ￼

Important nuance:
    •    Network “available” isn’t the same as Beeminder reachable. Your retry loop should treat timeouts / 5xx / no-internet as “keep queued”.

5) watchOS support (optional, “only if easy”)

Goal: quick “+1” logging from watch without re-implementing Beeminder auth/queue on watch.

Approach (recommended easy mode)
    •    iPhone app remains the “source of truth”: token + queue + Beeminder API.
    •    Watch app sends “log event” to iPhone using WatchConnectivity background transfer.
    •    Use transferUserInfo(_:) from watch → phone. Apple documents this as queued delivery (“ensure that it’s delivered”).  ￼
    •    Phone receives via WCSessionDelegate (didReceiveUserInfo) and enqueues the datapoint locally, then runs the normal flush logic.

Pinned goals on watch:
    •    Keep watch UI minimal: show (a) first ~20 pinned goals, (b) recently used pinned goals at top.
    •    Sync pinned list from phone → watch using updateApplicationContext(_:) (state snapshot; delivered “when the opportunity arises”).  ￼

Docs you’ll use:
    •    WCSession overview  ￼
    •    transferUserInfo(_:)  ￼
    •    updateApplicationContext(_:)  ￼
    •    Apple tutorial: add a watchOS target in Xcode  ￼

watch UI (minimal)
    •    List of goals (from last application context)
    •    Tap goal = “+1”
    •    Optional: one “Other…” row that opens a small picker/search (skip if you want ultra-minimal)

This gives you offline-in-the-airplane behavior as long as your watch can reach your phone; the phone can queue while offline and later flush to Beeminder.

6) Dev environment speedrun (Xcode 26 + OS 26.x)

You’re on “26.x everywhere”, which aligns with Apple’s current SDK naming (iOS 26, macOS Tahoe 26, watchOS 26). Xcode 26 includes these SDKs.  ￼

Steps:
    1.    Install Xcode 26 (Mac App Store or Apple Developer downloads; whichever you prefer).  ￼
    2.    Launch Xcode once; install components.
    3.    Xcode → Settings → Accounts → sign in with Apple ID.
    4.    Create a new “App” project:
    •    Interface: SwiftUI
    •    Add macOS + iOS destinations (multiplatform)
    5.    Set deployment targets to 26.x (since you don’t care about back-compat).
    6.    Run:
    •    iOS simulator
    •    “My Mac”
    •    (Optional) real device

Apple dev program:
    •    You can start building and testing on your personal devices without membership.  ￼
    •    Paid Apple Developer Program is $99/year and primarily matters for distribution and smoother provisioning.  ￼

7) Build order (milestones)

Milestone A — UI skeleton
    •    Main screen with pinned list (local dummy data)
    •    Settings screen with pin toggles (dummy)

Milestone B — OAuth + Keychain
    •    Register Beeminder app; implement ASWebAuthenticationSession
    •    Store token in Keychain; show “Connected as …”
Beeminder OAuth steps (register + authorize URL + token handling) are explicitly documented.  ￼

Milestone C — Goals fetch + caching
    •    Fetch /users/me/goals.json?emaciated=true  ￼
    •    Cache [slug,title]
    •    Settings: pin/unpin with search

Milestone D — Log +1 (online only)
    •    POST .../datapoints.json with value=1, timestamp=now, requestid=uuid  ￼

Milestone E — Offline queue + auto-flush
    •    Persist queue JSON
    •    Flush on launch/foreground + NWPathMonitor callback  ￼
    •    Ensure requestid is stable across retries (no dupes)  ￼

Milestone F — watchOS (optional)
    •    Add watchOS target  ￼
    •    Implement watch → phone transferUserInfo for “log +1”  ￼
    •    Implement phone → watch updateApplicationContext to keep pinned goals list in sync  ￼

8) Claude “vibe code” prompt set (updated)
    1.    Project skeleton

    •    “Generate a SwiftUI multiplatform project layout (iOS + macOS). Main screen shows a searchable list of pinned goals; each row has a big +1 button and an optional ‘…’ sheet for custom value/comment.”

    2.    Auth

    •    “Implement Beeminder OAuth using ASWebAuthenticationSession. Build authorize URL per Beeminder docs, handle callback URL, parse access_token + username, store token in Keychain and username in AppStorage.”

    3.    Beeminder client

    •    “Implement BeeminderClient with base URL https://www.beeminder.com/api/v1/ and correct token handling (auth_token vs access_token; prefer Authorization: Bearer when using access_token). Include getGoals(emaciated=true) and createDatapoint(value,timestamp,comment,requestid).”

    4.    Offline queue

    •    “Implement a persistent JSON queue (Codable) stored in Application Support. On log: enqueue then attempt upload. On failure: keep. Add SyncManager that flushes when NWPathMonitor reports network available.”

    5.    Goal pinning UX

    •    “Implement Settings screen that loads all goals, supports search, and lets me toggle pinned. Persist pinned slugs in AppStorage. Cache last-known goal titles so pinned list renders offline.”

    6.    watchOS (optional)

    •    “Add watchOS target with a simple list of pinned goals. Sync pinned list from iPhone to watch using WCSession.updateApplicationContext. When user taps a goal, send a ‘log +1’ event to iPhone using WCSession.transferUserInfo. iPhone receives and enqueues/syncs using the same offline queue.”

9) Doc links (copy/paste)

Beeminder API Reference: https://api.beeminder.com/
Beeminder app registration: https://www.beeminder.com/apps/new
Beeminder authorize endpoint: https://www.beeminder.com/apps/authorize
Beeminder personal token endpoint: https://www.beeminder.com/api/v1/auth_token.json

ASWebAuthenticationSession: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
Keychain Services: https://developer.apple.com/documentation/security/keychain-services
NWPathMonitor: https://developer.apple.com/documentation/network/nwpathmonitor

WCSession: https://developer.apple.com/documentation/watchconnectivity/wcsession
WatchConnectivity data transfer guide: https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity
WCSession.transferUserInfo: https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)
WCSession.updateApplicationContext: https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)

SwiftUI search modifiers: https://developer.apple.com/documentation/swiftui/view-search
SwiftUI AppStorage: https://developer.apple.com/documentation/swiftui/appstorage
SwiftUI tutorial (add watchOS target): https://developer.apple.com/tutorials/swiftui/creating-a-watchos-app

Apple Developer Program overview: https://developer.apple.com/help/account/membership/programs-overview/
Compare memberships: https://developer.apple.com/support/compare-memberships/

If you want one additional simplification: start with iOS only until auth + offline queue are solid, then add macOS target (mostly free once the core is clean), then watchOS last.
