# Launch kit

Everything needed to get Cricket Live in front of people. Nothing here has been posted or submitted. Each step needs your accounts.

| What | Where | Cost | Time |
|---|---|---|---|
| Google Play (Android) | [stores.md → Google Play](stores.md#google-play) | $25 once | ~1 h of work, then the 14-day closed test |
| Microsoft Store (Windows) | [stores.md → Microsoft Store](stores.md#microsoft-store) | Free | ~1 h, review in 1–3 days |
| Listing copy (both stores) | [listing.md](listing.md) | n/a | copy-paste |
| Launch posts | [posts.md](posts.md) | Free | post during a big match |
| Search (Google) | [stores.md → Google Search Console](stores.md#google-search-console) | Free | 10 min |

## Assets

| File | Use |
|---|---|
| `assets/feature-graphic-1024x500.png` | Google Play feature graphic |
| `assets/icon.png` | 512×512 app icon (Play, Microsoft Store) |
| `screenshots/phone-*.png` (1080×1920) | Play phone screenshots, Reddit/X posts |
| `screenshots/desktop-*.png` (1366×768) | Microsoft Store screenshots, Product Hunt gallery |
| `screenshots/pinned-card-478x200.png` | the floating score on its own, for posts |
| `assets/feature.html` | source of the feature graphic (edit and re-render) |

The site already has what the stores and Google read:
- `manifest.webmanifest` with id, categories, maskable icons, screenshots and a "My teams" shortcut.
- JSON-LD (WebApplication + FAQPage), a canonical URL, `sitemap.xml` and `robots.txt`.

Lighthouse on the live site (performance / accessibility / best practices / SEO): mobile 78 / 96 / 100 / 100, desktop 91 / 96 / 100 / 100. Mobile performance is mostly the wait for live score data on a simulated slow 4G connection; layout shift is near zero.

## Before you go big: the data source

Scores come from ESPN's public JSON feed, fetched by each visitor's browser. That keeps the app free and key-less, but:
- **It's unofficial.** ESPN can change or block it at any time. If they do, the app shows an error until it's moved to another source.
- **Store reviewers may ask about content rights.** The listing copy says nothing about ESPN and doesn't use their name or logos. That's deliberate: you have no licence to their brand. If Google or Microsoft asks where the data comes from, answer honestly ("publicly available score data"). Don't claim a partnership.
- **Stay free with no ads** while you rely on this feed. Making money from it is what usually draws a takedown.

More traffic doesn't add server load (each browser fetches its own data), so a Reddit spike costs you nothing on Vercel's free tier.
