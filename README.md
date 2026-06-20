# Pictionary Daily

A daily Pictionary app for friends, with an Android home-screen widget.
Flutter (Android first, iOS to follow) + Firebase backend.

See [`pictionary-app-spec.md`](./pictionary-app-spec.md) for the full product spec.

---

## Status

**Phase 1 — Foundation** scaffolded:

- Flutter project (`pubspec.yaml`, `lib/`)
- Riverpod + GoRouter app shell with auth-gated routing
- Google Sign-In + user-doc bootstrap (`AuthService`)
- Firestore data model + security rules + Storage rules
- Cloud Function: daily word reset (00:00 UTC)
- Stubbed feature screens (canvas, feed, guessing, results, friends, profile)

Phases 2–5 (drawing canvas, guessing, friends, notifications, home-screen widget) are next.

---

## First-time setup

Run these once after cloning, in order.

### 1. Flutter SDK

Install Flutter (stable channel) and put `flutter` on your PATH. Verify:

```powershell
flutter --version
flutter doctor
```

If `flutter doctor` complains about missing Android toolchain pieces, finish those first.

### 2. Materialise platform folders

This repo only contains `lib/` and config. Generate the `android/` and `ios/` folders without touching the Dart code:

```powershell
flutter create --org com.pictionary --project-name pictionary_app .
flutter pub get
```

> `flutter create .` is non-destructive — it adds platform folders alongside the existing `lib/`, `pubspec.yaml`, etc.

### 3. Firebase project

```powershell
npm install -g firebase-tools
firebase login
firebase use --add        # pick or create the Firebase project
```

Update `.firebaserc` so the `default` alias points at your project ID.

Then enable in the Firebase console:

- **Authentication** → Google provider
- **Firestore** (production mode is fine; rules below will lock it down)
- **Storage**
- **Cloud Messaging**
- **Cloud Functions** (requires Blaze plan)

### 4. Wire Firebase into Flutter

```powershell
dart pub global activate flutterfire_cli
flutterfire configure
```

This generates `lib/firebase_options.dart` (replacing the placeholder) and drops `google-services.json` into `android/app/` and `GoogleService-Info.plist` into `ios/Runner/`.

### 5. Deploy backend

```powershell
firebase deploy --only firestore:rules,storage:rules,firestore:indexes
cd functions
npm install
npm run build
firebase deploy --only functions
cd ..
```

### 6. Seed the first day's words

The scheduler fires at 00:00 UTC, so on the very first day you'll want to seed manually:

```powershell
# in the Firebase console > Firestore, create:
#   daily/2026-05-25  { wordChoices: ["bicycle","volcano","saxophone"], generatedAt: <now> }
```

Or trigger the function once via the Cloud Functions console.

### 7. Run on Android

Connect your Samsung device with USB debugging on, then:

```powershell
flutter run
```

---

## Project layout

```
.
├── lib/
│   ├── main.dart                       # Firebase init + runApp
│   ├── app.dart                        # MaterialApp.router
│   ├── firebase_options.dart           # PLACEHOLDER — regenerate with flutterfire configure
│   ├── core/
│   │   ├── providers.dart              # Riverpod providers for services
│   │   ├── routing/app_router.dart     # GoRouter + auth redirect
│   │   ├── auth/auth_service.dart      # Google Sign-In + user doc bootstrap
│   │   ├── firebase/firestore_service.dart
│   │   ├── firebase/storage_service.dart
│   │   ├── notifications/fcm_service.dart
│   │   └── util/today.dart             # UTC YYYY-MM-DD key
│   ├── models/                         # AppUser, DailyWords, PlayerRound, Guess
│   └── features/                       # word_selection, canvas, feed, guessing, results, friends, profile, auth
├── functions/
│   └── src/
│       ├── index.ts
│       └── dailyReset.ts               # 00:00 UTC scheduler
├── assets/
│   └── words.json                      # offline fallback word list
├── firebase.json
├── firestore.rules
├── firestore.indexes.json
├── storage.rules
├── .firebaserc                         # set your project ID here
├── pubspec.yaml
├── analysis_options.yaml
└── pictionary-app-spec.md              # full product spec
```

---

## Local development

Run with emulators (no real Firebase project touched):

```powershell
firebase emulators:start
flutter run --dart-define=USE_EMULATORS=true
```

> Emulator wiring inside the app isn't in Phase 1 yet — for now `flutter run` hits the real project.

---

## Notes / next phases

- **Phase 2** — drawing canvas (`CustomPainter`), upload to Storage, friends feed reads, guessing screen with 3 attempts.
- **Phase 3** — friend invites by 6-char code, FCM triggers, streak logic.
- **Phase 4** — Android `home_widget` integration, three widget states, deep links.
- **Phase 5** — iOS, polish, error states.
