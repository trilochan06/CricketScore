# Store submission guide

Both stores accept the website as-is, wrapped by [PWABuilder](https://www.pwabuilder.com) (free, made by Microsoft). Updates to the website show up in the store apps automatically, so you won't need to resubmit for most changes.

## Google Play

**Cost:** $25 one-time developer fee.
**Catch:** new *personal* developer accounts must run a **closed test with at least 12 testers for 14 days** before the app can go public. Line up 12 friends with Android phones first (a WhatsApp group works).

### 1. Generate the Android package
1. Go to <https://www.pwabuilder.com>, enter `https://cricketscore-server.vercel.app`, then click **Start**.
2. It should show the manifest, service worker and security as green. Click **Package for stores → Android → Generate package**.
3. Options:
   - Package ID: `app.vercel.cricketscore_server.twa` (or your own, e.g. `com.trilochan.cricketlive`. It can never change after upload.)
   - App name: `Cricket Live`. Launcher name: `Cricket Live`.
   - Display mode: `Standalone`. Notifications: **on** (enables alerts on Android).
   - Signing key: **Create new**. PWABuilder generates it.
4. Download the zip. **Back up `signing.keystore` and `signing-key-info.txt` somewhere safe** (password manager or cloud drive). If you lose them, you can never update the app.

### 2. Prove you own the website
The zip contains `assetlinks.json`. Copy it into the repo and deploy:
```bash
mkdir -p server/public/.well-known
cp ~/Downloads/<pwabuilder-zip>/assetlinks.json server/public/.well-known/assetlinks.json
```
Commit and push. Check that `https://cricketscore-server.vercel.app/.well-known/assetlinks.json` loads. Without it, the app shows a browser address bar at the top.

> After your first upload, Play may re-sign the app. In **Play Console → Setup → App signing**, copy the **SHA-256** of the *app signing key*, add it as a second fingerprint in `assetlinks.json`, and redeploy.

### 3. Play Console
1. Sign up at <https://play.google.com/console> (Personal account, $25, ID verification).
2. **Create app:** name `Cricket Live`, App, Free.
3. **Store listing:** paste the copy from [listing.md](listing.md), then upload:
   - App icon: `launch/assets/icon.png` (512×512).
   - Feature graphic: `launch/assets/feature-graphic-1024x500.png`.
   - Phone screenshots: `launch/screenshots/phone-*.png` (1080×1920), at least 2.
4. **App content** answers:
   - Privacy policy: `https://cricketscore-server.vercel.app/privacy`
   - Ads: **No**
   - Data safety: **No data collected or shared.** Team picks and settings stay on the device.
   - Target audience: 13+. Category: **Sports**.
   - Content rating questionnaire: no violence or gambling (unless you add betting odds, don't).
5. **Testing → Closed testing:** upload the `.aab` from the zip and add your 12+ testers' Gmail addresses. Run it for 14 days.
6. After 14 days, apply for **Production** access, then roll out.

## Microsoft Store

**Cost:** free for individual developers.

1. Sign up at <https://partner.microsoft.com/dashboard> → **Apps and games** (Individual account).
2. **New product → MSIX or PWA app** → reserve the name `Cricket Live`.
3. Open **Product identity** and copy *Package/Identity/Name*, *Publisher*, and *Publisher display name*.
4. On PWABuilder: **Package for stores → Windows**, paste those three values, then generate. You get a `.msixbundle` and a `.classic.appxbundle`.
5. In Partner Center:
   - **Packages:** upload both files.
   - **Store listing:** use the Microsoft Store copy in [listing.md](listing.md). For screenshots, use `launch/screenshots/desktop-*.png` (1366×768).
   - **Properties:** category Sports. Privacy policy URL as above.
   - **Age ratings:** complete the IARC questionnaire.
6. Submit. Certification usually takes 1–3 days.

## Google Search Console

Helps the site show up when people search "live cricket score widget" and similar.
1. <https://search.google.com/search-console> → **Add property → URL prefix** → `https://cricketscore-server.vercel.app/`.
2. Verify with the **HTML tag** method: copy the `<meta name="google-site-verification" …>` tag into `server/public/index.html` `<head>`, push, then click **Verify**.
3. **Sitemaps** → submit `sitemap.xml`.
4. Bing: <https://www.bing.com/webmasters> → **Import from Google Search Console** (one click).

A custom domain (e.g. `cricketlive.app`, about $10–15/yr) ranks and shares better than `*.vercel.app`. If you buy one, add it in Vercel → Project → Domains, and update the canonical URL, `og:url`, `og:image`, `sitemap.xml` and `robots.txt`.
