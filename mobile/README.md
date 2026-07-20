# Amazing Church PH — Mobile app (Capacitor)

Native iOS + Android app wrapping the Next.js website via Capacitor.
The shell renders your live web app, and native plugins expose camera, push, status-bar, etc.

## The two ways it can point at your web app

Capacitor loads content from **one of two places**:

1. **Remote URL** (recommended for this app) — set `server.url` in
   `capacitor.config.json` to your deployed site. The app loads it like a
   browser tab. Auth, uploads, realtime, everything just works.

2. **Bundled `webDir`** — Capacitor serves a static build. Requires
   `output: 'export'` in `next.config.js`, which breaks server components,
   middleware, and API routes. Don't use this without a rewrite.

Because this project is dynamic, **use option 1**.

## First-time setup

```bash
# 1. Install everything (already done via npm install)

# 2. Set the URL the app should load.
#    Edit capacitor.config.json and set server.url:
#    - Local dev on Android emulator:  http://10.0.2.2:3000
#    - Real device on same Wi-Fi:      http://<your-machine-lan-ip>:3000
#    - Production:                     https://your-deployed-domain
```

Add the URL to `capacitor.config.json` under `server`:

```json
"server": {
  "url": "https://your-deployed-domain",
  "androidScheme": "https",
  ...
}
```

Then sync:

```bash
npx cap sync
```

## Android (buildable on Windows)

Requires **Android Studio** — <https://developer.android.com/studio>

```bash
# Add the Android project (only needed once)
npx cap add android

# Copy the latest web assets + plugin manifests into the native project
npx cap sync android

# Open in Android Studio
npx cap open android
```

Inside Android Studio:
- Wait for Gradle sync
- Click **Run ▶** to install on an emulator or attached device
- To build a signed release AAB for the Play Store: **Build → Generate Signed Bundle / APK → Android App Bundle**

**Play Store submission** — <https://play.google.com/console> ($25 one-time developer fee)

## iOS (requires macOS + Xcode)

You cannot build iOS from Windows. You have three paths:

- **A Mac** — cheapest if you have one. Install Xcode from the Mac App Store, clone this repo, run `npx cap add ios && npx cap open ios`.
- **Mac in the cloud** — MacinCloud, AWS EC2 Mac, MacStadium. Pay per hour.
- **Cloud CI build service** — [Ionic Appflow](https://ionic.io/appflow), [Codemagic](https://codemagic.io), or GitHub Actions with a macOS runner. Codemagic has a free tier that fits small projects.

Once on macOS:

```bash
npx cap add ios
npx cap sync ios
npx cap open ios
```

Inside Xcode:
- Set the Team + Signing (needs an Apple Developer account, $99/yr)
- Click **Run ▶** to deploy to a device or simulator
- Archive and upload to App Store Connect for review

## Generating icons + splash

Uses `@capacitor/assets`:

```bash
# Put a 1024x1024 icon at resources/icon.png
# Put a splash image at resources/splash.png (2732x2732 recommended)
npx @capacitor/assets generate --iconBackgroundColor '#FBFAF7' --splashBackgroundColor '#FBFAF7'
```

I've placed `resources/icon.png` for you (from the church logo). Add a `splash.png` of your choice and run the command.

## Native features already wired

- **@capacitor/status-bar** — status bar tinted brand crimson on both platforms
- **@capacitor/splash-screen** — logo splash for 1.5 s on cold start
- **@capacitor/camera** — available to the web layer if we later swap the upload flow
- **@capacitor/push-notifications** — plugin installed. To activate: register with Firebase Cloud Messaging (Android) + Apple Push Notifications (iOS), and add a backend endpoint that sends pushes on notification INSERT (Supabase Edge Function is the cleanest place). Not wired yet — say the word.

## Publishing checklist

- [ ] Deploy the Next.js site to a real HTTPS domain (Vercel etc.)
- [ ] Update `server.url` in `capacitor.config.json` to that domain
- [ ] Bump `versionName` / `versionCode` for Android; `CFBundleShortVersionString` for iOS
- [ ] Generate proper 1024×1024 icon + splash, run `npx @capacitor/assets generate`
- [ ] Apple: create an App ID + provisioning profile, upload via Xcode / Transporter
- [ ] Google: fill in Play Console listing (description, screenshots, privacy policy URL), upload the signed AAB
- [ ] Both stores require a privacy-policy URL — draft one at `/privacy` (I can scaffold if you want)
