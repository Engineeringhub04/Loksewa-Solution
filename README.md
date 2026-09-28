# Loksewa Solution — Flutter

Flutter rewrite of the Loksewa Solution app. **Same Firebase backend as the
Expo app** — same package name (`com.loksewasolutionnp.hub`), same
`google-services.json`, no backend changes needed. The app talks to Firebase
over the REST API (same approach as the Expo app's hand-rolled clients).

## Status

- [x] Phase 1 — Project scaffold (theme, router, splash placeholder, CI)
- [ ] Phase 2 — Screen-by-screen rewrite (splash → onboarding → auth → home → …)
- [ ] Phase 3 — Release polish, Play Store prep

## Getting the APK (no PC needed)

Every push to `main` triggers the **Build APK** GitHub Action, which builds
per-ABI release APKs (`--split-per-abi`, ~5–10 MB each). Download them from
the workflow run's **Artifacts** section (`loksewa-solution-apks`) and install
the `arm64-v8a` one on the itel Vision 3.

## Local build (needs Flutter SDK)

```sh
flutter pub get
flutter build apk --release --split-per-abi \
  --dart-define=FIREBASE_API_KEY=xxx \
  --dart-define=FIREBASE_PROJECT_ID=xxx \
  --dart-define=FIREBASE_AUTH_DOMAIN=xxx \
  --dart-define=FIREBASE_STORAGE_BUCKET=xxx \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxx \
  --dart-define=FIREBASE_APP_ID=xxx \
  --dart-define=GOOGLE_WEB_CLIENT_ID=xxx
```

For CI, these values live in the repo's **Settings → Secrets → Actions**.

## Project layout

```
lib/
  main.dart            # Firebase init + app entry
  theme/app_theme.dart # Brand colors (#03145C navy etc.)
  router/app_router.dart
  screens/             # One file per screen (Phase 2 fills these in)
  services/app_config.dart  # Backend config via --dart-define
android/               # package com.loksewasolutionnp.hub
.github/workflows/     # CI: build APK on every push
```
