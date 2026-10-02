# Launch posts (drafts)

**When to post:** during or just before a big match (an India game, a World Cup or an IPL final). People search for scores then, and a live demo sells itself. Post from your own accounts, and stay around for an hour to reply to comments.

**Ground rules:**
- Say it's your project.
- Read each subreddit's self-promotion rules first. Many allow it only in a weekly thread or need account history. Don't post the same text everywhere on the same day.
- Don't buy upvotes or ask friends to brigade. Reddit and Product Hunt detect it and bury the post.

## Reddit: r/Cricket

Check the sidebar first. r/Cricket often routes self-promo into match threads or a weekly thread.

**Title:** I made a free live score that floats over your other apps, so you can follow the match while you work

**Body:**
```
Got tired of switching tabs every over, so I built this: https://cricketscore-server.vercel.app

- Ball-by-ball live scores with a big FOUR / SIX / WICKET pop when it happens
- "Pin score" on Android (and "Pop out" on Windows/Mac) puts a tiny score on top of everything else: WhatsApp, YouTube, Excel, whatever
- Star your teams: their matches open first, optional alerts for start/wicket/result
- Free, no ads, no account, nothing to download (you can "install" it from the browser)

It's a hobby project and open source. Happy to hear what's missing. Next on my list is [your idea].
```
Attach `screenshots/phone-1080x1920.png` and `screenshots/pinned-card-478x200.png`.

## Reddit: r/macapps

**Title:** [Free] CricketScore: live cricket next to your MacBook notch

**Body:**
```
Free, open-source menu bar + notch widget for live cricket.

- Sits beside the notch (or top of screen on external displays), click it for the full scorecard
- Flashes on boundaries/wickets, optional alerts for your teams
- Hides itself in full-screen video and when your camera is on (calls)
- Hidden from screen sharing if you want
- Universal binary, ~2.5 MB, no account

Download: https://cricketscore-server.vercel.app/download
Source: https://github.com/trilochan06/CricketScore

Heads up: it's not notarized (I'm not paying Apple $99/yr for a free app), so the first launch needs System Settings → Privacy & Security → Open Anyway. Source is all there if you'd rather build it yourself.
```

## Reddit: r/SideProject

**Title:** Live cricket scores that stay on screen: a PWA with Picture-in-Picture as a "widget"

**Body:**
```
Built a cricket score site where the main trick is Picture-in-Picture:
- Desktop Chrome/Edge: Document PiP → a real always-on-top mini window
- Android/iOS: draw the score onto a canvas, captureStream() it into a <video>, put *that* in PiP → floats over other apps
- No backend: the browser fetches a public JSON feed directly, so it's a static site on Vercel's free tier and scales for free
- Followed teams, local notifications, Web Share with a generated score image

https://cricketscore-server.vercel.app · code: https://github.com/trilochan06/CricketScore
Feedback welcome, especially from iPhone users (PiP behaviour there is the least tested).
```

## Show HN

**Title** (80 max): `Show HN: Live cricket scores that float over your other apps (PWA + PiP)`
**URL:** `https://cricketscore-server.vercel.app`
**First comment:**
```
Hi HN. I follow cricket while working and wanted the score visible without a tab switch.

The interesting part is getting a "widget" out of a web page:
- On desktop it uses the Document Picture-in-Picture API for a small always-on-top window.
- On phones there's no Document PiP, so it renders the score to a <canvas>, pipes canvas.captureStream() into a <video> element, and requests PiP on that. Android then floats it over any app, and it redraws on every ball.

There's no backend. Browsers fetch a public JSON feed directly, so it's static files on a free tier. There's also a native macOS notch widget (SwiftUI + NSPanel) in the same repo.

Source: https://github.com/trilochan06/CricketScore
```

## Product Hunt

- **Name:** Cricket Live
- **Tagline** (60 max): `Ball-by-ball cricket that floats over your other apps`
- **Topics:** Sports, Productivity, Web App
- **Gallery:** feature graphic, `desktop-1366x768`, `phone-1080x1920`, `desktop-mac-app-1366x768`, pinned card
- **Description:** `Follow every ball while you work. Pin a tiny live score over any app on Android, Windows or Mac, star your teams, and get alerts for wickets and results. Free, no ads, no sign-up.`
- **Maker comment:** reuse the r/Cricket body, adding one line on why you built it.
- Launch at 12:01 am Pacific (about 12:31 pm IST) on a Tuesday–Thursday.

## X / Twitter

```
Watching the match at work? 👀

I built a free live cricket score that floats over your other apps.
Ball by ball, with FOUR/SIX/WICKET pops 🏏

Pin it on Android, pop it out on Windows/Mac.
No ads. No sign-up.

cricketscore-server.vercel.app
```
Attach a screen recording: start the match, tap Pin, switch to another app, and catch a boundary. The video does more than the text.

## WhatsApp (friends and cricket groups)

```
Made a thing 🏏 Live score that stays on your screen while you use other apps (WhatsApp, YouTube, anything).

Open → tap "Pin score" → done. Free, no ads, no sign-up:
https://cricketscore-server.vercel.app

Tell me if anything's broken 🙏
```
Also ask 12 of them to be Play Store testers (see stores.md).
