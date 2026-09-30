# Cricket Score

A tiny native macOS utility that keeps the live cricket score at the top of your screen. It lives in the menu bar and shows a floating widget. On a MacBook with a notch, the widget grows out of the camera housing. It's written in Swift, SwiftUI and AppKit, and doesn't use any browser or web view.

```
Collapsed, notched MacBook             ● IND 184/4  [  camera  ]  32.2 ov
Collapsed, no notch / Below Notch      ( ● LIVE  IND 184/4 32.2 · AUS 241/8  ⌄ )
Click the widget  →  score, need X from Y, CRR/RRR, batters, bowler, recent balls, match info
```

It runs straight away on simulated demo matches, so you don't need an API key to try it.

---

## Requirements

- macOS 14 Sonoma or later (built and tested on macOS 26).
- Xcode 16+ **or** just the Xcode Command Line Tools (`xcode-select --install`).

## Run it

### Option A: Xcode
1. Open `CricketScore.xcodeproj`.
2. Pick the **CricketScore** scheme and **My Mac**, then press **⌘R**.
3. A cricket-ball icon appears in the menu bar and the widget appears at the top of the screen.

If Xcode asks about signing, choose your team under *Signing & Capabilities*. Otherwise leave it as *Sign to Run Locally*. You can also open `Package.swift` in Xcode.

### Option B: Command Line Tools only (no Xcode needed)
```bash
./Scripts/build-app.sh
open build/CricketScore.app
```
For quick iteration there's also `swift build && .build/debug/CricketScore`. That runs unbundled, so Launch at Login is unavailable.

## Create the `.app`

```bash
./Scripts/build-app.sh             # → build/CricketScore.app (release, ad-hoc signed)
./Scripts/build-app.sh --install   # also copies it to /Applications
```
In Xcode: **Product → Archive → Distribute App → Copy App**.

The first launch of an ad-hoc-signed app copied to another Mac may be blocked by Gatekeeper. Right-click the app, choose **Open**, then confirm. To distribute more widely, sign it with a Developer ID and notarize it.

## Launch at Login

1. Run the app from a real bundle: `/Applications/CricketScore.app` is best. It won't work from `swift run`.
2. Go to **Menu bar icon → Settings… → General → Launch at login**.
3. If macOS asks for approval, click **Open Login Items…** and enable Cricket Score.

This uses `SMAppService.mainApp`. You can turn it off in the same place or in **System Settings → General → Login Items**.

---

## Using it

| Action | Result |
|---|---|
| Click the widget | Expands smoothly with details revealed in stages |
| Click anywhere else, or **×** | Collapses |
| **⋮** in the expanded widget | Switch match, refresh, pause overlay, open Settings |
| Match chips (expanded) / list (menu bar) | Switch between simultaneous matches |
| Menu bar icon | Selected score, live/upcoming/results lists, Pause/Show Overlay, Settings, Quit |
| Open the app again (Finder/Spotlight) | Opens Settings. Use this to get back if you've hidden both the widget and the menu bar icon. |

### Settings
- **General:** show overlay, launch at login, show menu bar icon, auto-show when a match starts, hide when nothing is live, remember selected match.
- **Display:** position (Top Center / Top Right / Below Notch), optional drag-to-move with a remembered position, appearance (System/Light/Dark).
- **Data:** update frequency (15/30/60 s), data source (Demo / CricketData.org), API key, and a **Simulate** picker (demo mode only).

With **Simulate** you can preview every state: live, innings break, rain delay, a match starting soon, match ended, no live matches, nothing scheduled, API error and offline.

---

## Live ball-by-ball data — no server, no API key

Scores come from **ESPNcricinfo's public, CORS-enabled JSON feed**, read directly by each user's device — exactly how ESPN's own website works:

```
ESPNcricinfo public feed ──▶ each visitor's browser   (website: server/public, a static site)
                         └─▶ each user's Mac app      (ESPNScoreProvider.swift)
```

- Nothing to host except static files, so there's nothing to rate-limit or block (ESPN refuses requests from cloud servers, but allows browsers and apps).
- Website data layer: `server/public/lib/` (`espn.js` adapter, `scorecard.js`, `data.js`) — plain ES modules shared by the browser and Node.
- Mac app: `CricketScore/Services/ESPN/ESPNScoreProvider.swift` (default data source). Polls only while a match is live.
- Polite polling: every 6 s per open website tab (60 s when the tab is hidden), and at the app's refresh interval.
- To use a licensed provider later, replace the adapter (`espn.js` / `ESPNScoreProvider.swift`); the UI doesn't change.
- `server/src/` still contains an optional always-on Node server (SSE push, `/api/*`) for self-hosting where it's allowed: `cd server && npm start`.

> The feed is unofficial and ESPN's terms don't grant reuse rights: keep the app free and non-commercial, credit ESPNcricinfo, and switch to a licensed feed before charging money or running ads.

## Shipping to the public (free)

### Website
Hosted on Vercel from this repo (**Root Directory `server`**, framework **Other**). Every `git push` to `main` redeploys. It's a static site and installable as an app (PWA): Safari → File → Add to Dock, Chrome → Install, or Add to Home Screen on phones.

### Mac app — free, no Apple Developer account
```bash
SERVER_URL="https://cricketscore-server.vercel.app" ./Scripts/release.sh 1.0.1 "What's new"
git add server/public/version.json && git commit -m "Release 1.0.1" && git push
```
This builds a universal (Apple Silicon + Intel) app with only the Command Line Tools, packages `CricketScore.dmg` (with a "How to open" note), uploads it as a **GitHub Release** (requires `gh auth login`), and updates `version.json` on the website. The permanent download link is https://github.com/trilochan06/CricketScore/releases/latest/download/CricketScore.dmg. The site's **Download for Mac** button and one-time "Open Anyway" instructions appear automatically, and installed apps show **"Update available"** within a day.

Because the app isn't notarized, each user approves it once: open it → **Done** → **System Settings → Privacy & Security → Open Anyway**.

### Optional: signed & notarized (no warning at all)
Requires the Apple Developer Program ($99/year) and Xcode. Create a *Developer ID Application* certificate, run
`xcrun notarytool store-credentials CricketScoreNotary --apple-id … --team-id … --password <app-specific>`, then add
`SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` to the release command. Credentials stay in your keychain.

## Using real data: where the API key goes

The app ships with a provider for **[CricketData.org](https://cricketdata.org)** (formerly CricAPI). It has a free tier.

1. Create a free account at cricketdata.org and copy your API key.
2. Go to **Settings → Data → Score provider**, choose **CricketData.org**, paste the key and click **Save**.

The key goes into your **macOS login Keychain** (service `CricketScore.CricketDataAPI`). It is never written to source code, `UserDefaults` or the app bundle.

For development you can instead set the environment variable `CRICKET_API_KEY`. In Xcode: **Product → Scheme → Edit Scheme → Run → Environment Variables**. The shared scheme already has a disabled `CRICKET_API_KEY` entry, so you just fill it in and tick it. The environment variable takes priority over the Keychain.

**Free-plan limits:** about 100 requests/day. The live provider re-fetches the match list at most every 5 minutes and otherwise fetches only the selected match's scorecard. Polling happens only while a match is live. Even so, choose **60 seconds** on the free plan. The free tier has no ball-by-ball feed, so *Recent balls* and the striker marker are hidden for real data.

## Replacing the mock data / adding another API

The data layer is built around one protocol:

```
CricketScoreProvider (protocol)      Services/CricketScoreProvider.swift
   ├─ MockCricketScoreProvider      Services/Mock/        simulated, offline, no key
   └─ LiveCricketScoreProvider      Services/CricketData/ CricketData.org REST API
LiveMatchService                    polling, backoff, offline & sleep handling
ScoreViewModel                      selection, highlights, display state, visibility
SwiftUI views
```

```swift
protocol CricketScoreProvider: Sendable {
    var displayName: String { get }
    func fetchLiveMatches() async throws -> [CricketMatch]
    func fetchScorecard(matchID: String) async throws -> Scorecard
    // optional: isMock, requiresNetwork, minimumListRefreshInterval
}
```

To plug in a different API (e.g. Cricbuzz via RapidAPI, SportMonks, or your own backend):
1. Write a type conforming to `CricketScoreProvider` that maps the API's JSON into `CricketMatch` / `Scorecard`. Use `LiveCricketScoreProvider` as a template. If there's no data for something (e.g. recent balls), leave it empty and the UI hides that section.
2. Add a case to `DataSource` and return your provider from **`ProviderFactory.make(for:)`**. This is the single switch point, in `Services/CricketData/LiveCricketScoreProvider.swift`.
3. Keep secrets in `APIKeyStore` (Keychain), not in code.

The default source is set in `AppSettings` (`Key.dataSource: DataSource.demo`).

---

## How it works

- **Floating widget:** a borderless `NSPanel` with `.nonactivatingPanel`, at `.statusBar` level. It uses `canJoinAllSpaces` + `fullScreenAuxiliary` + `ignoresCycle`, so it shows on every Space and over full-screen apps, and stays out of Cmd+Tab and Mission Control. `canBecomeKey` is `false`, so it never takes keyboard focus. The app is an `LSUIElement` (no Dock icon).
- **Doesn't block clicks:** the panel resizes to exactly the SwiftUI content size (measured with `onGeometryChange`), so there's no invisible area over other apps. Growing happens immediately; shrinking waits for the collapse animation.
- **Notch:** `NSScreen.safeAreaInsets` plus `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` locate the camera housing. In *Top Center* on a notched Mac, the widget is black and flush with the top edge. Its content sits in two equal "wings" either side of the camera, and it expands downward. On Macs without a notch, and in *Below Notch* / *Top Right*, it's a blurred floating pill. Changing displays or resolution repositions it live.
- **Performance:** it polls only while a match is live. Otherwise it checks every ≤5 min, or as the next match starts. Errors trigger exponential backoff, and polling pauses while offline (`NWPathMonitor`) or asleep. `@Observable` state is only assigned when values actually change, so views update only when their data does. There are no continuous animations. Relative timestamps tick every 5 s, and only while the widget is expanded. The measured idle footprint is about 66 MB RSS at 0% CPU.
- **Animations:** rolling digits on score changes, a FOUR/SIX/WICKET chip and outline glow, a pulse on the new ball, a spring expand/collapse, and staggered reveal. All of these respect **Reduce Motion**.

### Project layout
```
CricketScore/
├── App/            CricketScoreApp (MenuBarExtra), AppDelegate, SnapshotRenderer (debug only)
├── Models/         Team, CricketMatch, Scorecard, Batter, Bowler, Delivery
├── Services/       CricketScoreProvider, LiveMatchService, Mock/, CricketData/
├── Settings/       AppSettings (UserDefaults), APIKeyStore (Keychain), LaunchAtLogin
├── ViewModels/     ScoreViewModel
├── Views/          ScoreOverlay, Collapsed/Expanded views, PlayersTable, RecentBalls, MatchSelector, Settings, Components/
├── Window/         FloatingPanel, OverlayController, OverlayLayout, ScreenGeometry, SettingsWindowController
├── MenuBar/        MenuBarView
└── Resources/      Info.plist, AppIcon.icns
Scripts/            build-app.sh, make-icon.swift
```

### Development aids (Debug builds only)
```bash
swift build
CRICKETSCORE_SNAPSHOT_DIR=/tmp/shots .build/debug/CricketScore  # PNG of every state × style × light/dark
CRICKETSCORE_SELFTEST=1 .build/debug/CricketScore                # drives the real panel, logs window frames
```

### Note on `@ViewState`
Views use `@ViewState`, a four-line wrapper around `SwiftUI.State`, instead of `@State`. In the macOS 26 SDK, `@State` is a compiler macro whose plugin ships with Xcode but not with the standalone Command Line Tools. The wrapper behaves identically and lets the project build either way. With Xcode installed you can switch back to `@State` if you prefer.

---

## Test checklist

| Check | How it was verified |
|---|---|
| App launches; one floating window; menu bar icon | Launched `CricketScore.app`; window list shows exactly one panel |
| Widget at top, centred on the notch (notched MacBook Air, 1470×956) | Panel 391×32 pt at y=0, centred on the notch midpoint |
| Works without a notch / Top Right / Below Notch | Self-test: floating pill 6 pt under the menu bar; Top Right 10 pt from the edge |
| Collapsed ↔ expanded; window shrinks back afterwards | Self-test logs the frames (391×32 → 409×487 → 391×32) |
| Never steals keyboard focus | Self-test: app never active, panel never key |
| Innings break, rain, upcoming, ended, no matches, API error, offline | Rendered snapshots of every state in light and dark |
| Hide when nothing live; Pause/Show overlay | Self-test: panel hides and returns |
| Mock score updates, wickets, innings changes, results | Engine stress test: 90 full simulated matches, no invariant failures, no NaN/nil text |
| CricketData.org parsing | Decoded sample responses (numbers as strings, missing fields, all status types) |
| No warnings; low CPU/memory | Clean build; ~66 MB RSS, 0% CPU idle |
| **Please check by hand** | Real mouse clicks on the widget (automated clicks need Accessibility permission), dragging, the ⋮ menu, the Settings window, Launch at Login, and a live API key |

## License

The code is released under the [MIT License](LICENSE).

Cricket scores and commentary shown by the app and website come from ESPNcricinfo and are not covered by this license. This is an unofficial fan project, not affiliated with or endorsed by ESPN.
