# Next Steps — Things Only You Can Do

This file lists the **manual** tasks — the ones that need browser OAuth, Firebase console clicks, billing, a physical device, or Apple/Google developer accounts. None of these can be scripted from a Claude session. The actual app/Cloud-Function **code** is written for you (Phase 1 + Phase 2 are done; Phase 3 code is produced by the `pictionary-phase3` workflow).

Run terminal steps from a **fresh PowerShell window** (so the PATH / `ANDROID_HOME` env vars are picked up):

```powershell
cd "C:\Projects\Pictionary Widget"
```

## Manual checklist at a glance

**Before anything runs (one-time foundation — NOT yet done):**
- [ ] §1 `firebase login` + create project (Blaze plan) + enable Auth/Firestore/Storage/Functions/Messaging
- [ ] §1 `firebase use --add`
- [ ] §2 `flutterfire configure` (replaces the placeholder `lib/firebase_options.dart`)
- [ ] §3 `firebase deploy` (rules, indexes, functions)
- [ ] §4 Seed `daily/{today}` once
- [ ] §5 Connect a Samsung (USB debugging) or create an emulator
- [ ] §6 `flutter run` and smoke-test the Phase 1 + Phase 2 game loop

**After the Phase 3 code is written (see §Phase 3 at the bottom):**
- [ ] `cd functions; npm install` (pulls any new function deps), then `firebase deploy --only functions`
- [ ] `flutter pub get` (picks up the new `cloud_functions` package)
- [ ] Test friend invites end-to-end with a second account
- [ ] Test the 3 push-notification triggers on a real device (emulators are unreliable for FCM)

---

---

## 1. Firebase project + login

```powershell
firebase login
```

Opens a browser → sign in with the Google account that will own the project (`arvin.aryanpour.aa@gmail.com`).

Then create the Firebase project in the console (if you haven't already):
<https://console.firebase.google.com>

- Project name: anything (e.g. `pictionary-daily`)
- **Upgrade to the Blaze plan** — required for Cloud Functions. You won't actually be charged until you exceed the free tier.

In the new project, enable:
- **Authentication** → Sign-in providers → Google → Enable
- **Firestore Database** → Create database → Start in **production mode** (rules from this repo will lock it down)
- **Storage** → Get started → production mode
- **Cloud Messaging** (no setup needed, just confirm it's listed)
- **Functions** (enabled automatically once you deploy)

Then back in the terminal:

```powershell
firebase use --add        # pick the project, alias it "default"
```

This updates `.firebaserc` for you.

---

## 2. Wire Firebase into the Flutter app

```powershell
dart pub global activate flutterfire_cli
flutterfire configure
```

Interactive prompts:
- Pick the Firebase project you just created
- Pick platforms → **android** (and **ios** if you want to be ready for Phase 5)
- Accept the default Android application ID `com.pictionary.pictionary_app`

This will:
- Overwrite `lib/firebase_options.dart` with real keys
- Drop `android/app/google-services.json` (already in `.gitignore`)
- Drop `ios/Runner/GoogleService-Info.plist`

---

## 3. Deploy backend

```powershell
firebase deploy --only firestore:rules,storage:rules,firestore:indexes
firebase deploy --only functions
```

The `functions` deploy will compile TypeScript first (`npm run build` is wired into the predeploy hook).

---

## 4. Seed today's words (one-time)

The Cloud Function only fires at 00:00 UTC, so on the very first day after deploying you need a manual seed. Either:

**Option A — Firebase Console:**

Firestore → Start collection → `daily` → Document ID `YYYY-MM-DD` (today, UTC) with fields:

```
wordChoices  array  ["bicycle", "volcano", "saxophone"]
generatedAt  timestamp  (now)
```

**Option B — Trigger the function manually:**

Firebase Console → Functions → click `dailyWordReset` → Testing tab → "Run test"

---

## 5. Get an Android target ready

**Physical Samsung (preferred):**
1. Phone → Settings → About phone → tap "Build number" 7 times → "You are now a developer"
2. Settings → Developer options → enable "USB debugging"
3. Plug into PC via USB → accept the RSA fingerprint prompt on the phone

**Or emulator:**
- Open Android Studio → More Actions → Virtual Device Manager → Create Device
- Pick any modern Pixel + API 34 system image

Verify:

```powershell
flutter devices
```

You should see the Samsung (or emulator) listed alongside the desktop/web targets.

---

## 6. Run the app

```powershell
flutter run
```

You should see the sign-in screen → tap "Sign in with Google" → land on the word-selection screen showing the 3 words you seeded in step 4.

---

## Verification checklist (foundation + Phase 2 game loop)

- [ ] `firebase login:list` shows your account
- [ ] `cat .firebaserc` shows a real project ID under `default`
- [ ] `lib/firebase_options.dart` no longer throws `UnsupportedError` (open it; you should see real API keys)
- [ ] `android/app/google-services.json` exists
- [ ] Firestore console shows the `daily/{today}` doc
- [ ] `flutter devices` shows your phone or an emulator
- [ ] `flutter run` boots into the app, you sign in, and you can see today's 3 words
- [ ] **Phase 2:** pick a word → draw → submit → land on the feed → (with a 2nd account that also drew) tap a friend's drawing → guess up to 3 times → results screen shows your streak

Phase 1 + Phase 2 are already implemented in `lib/` — once the above passes, the full draw/guess loop works on device.

---

# Phase 3 — Social & Notifications (deploy + test after the code is written)

The `pictionary-phase3` workflow writes all the Phase 3 **code** (callable friend-invite function, FCM trigger functions, streak function, friends screen, FCM client handling). After it runs, do these **manual** steps:

## 3.1 Pull deps & deploy

```powershell
flutter pub get                       # picks up the new cloud_functions package
cd functions; npm install; cd ..      # in case any function dep was added
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes   # if rules/indexes changed
```

> New callable/triggered functions appear in Firebase Console → Functions after deploy. The first deploy of a v2 function can take a few minutes and may prompt to enable additional Google Cloud APIs (Cloud Build, Artifact Registry, Eventarc, Cloud Run) — accept.

## 3.2 Friend invites — test with two accounts

1. Sign in on your device (account A); note your invite code on the Profile screen.
2. Sign in on a second device/emulator (or the same device after sign-out) as account B.
3. On B's Friends screen, enter A's invite code → both should now show each other in their friend lists.
4. Confirm in Firestore that both `users/{A}.friendIds` and `users/{B}.friendIds` were updated (the callable function does this with admin privileges).

## 3.3 Push notifications — test on a REAL device

FCM delivery is unreliable on emulators; use a physical phone.

1. **Friend drew:** with A and B as friends, have A submit a drawing → B should get a "A submitted a drawing!" notification.
2. **Correct guess:** have B guess A's drawing correctly → A should get a "B guessed your drawing!" notification.
3. **Daily reset:** the scheduled function broadcasts to a topic at 00:00 UTC. To test without waiting, run `dailyWordReset` from the console (Functions → Testing) and confirm subscribed devices receive "Today's words are ready."
4. Tapping a notification should open the app to the relevant screen (feed/guess).

## 3.4 Streak — verify

- Submit a drawing on consecutive UTC days (or temporarily adjust `lastPlayedDate` in Firestore to simulate) → `streakCount` should increment by the streak function on submit, and reset to 1 after a missed day.

## Verification checklist — Phase 3

- [ ] `flutter analyze` clean and `cd functions; npm run build` compiles (the workflow gates these, but re-check after deploy edits)
- [ ] Functions Console lists `addFriendByCode` + the notification/streak triggers alongside `dailyWordReset`
- [ ] Friend invite mutually links two accounts
- [ ] All 3 notification triggers fire on a real device
- [ ] Tapping a notification deep-links to the right screen
- [ ] `streakCount` increments/resets correctly

Once that all works, we're ready to test **Phase 4 — Home-Screen Widget**.

---

# Phase 4 — Home-Screen Widget (build + on-device test)

The `pictionary-phase4` workflow already wrote the native Android widget (`PictionaryWidgetProvider.kt`, 3 layouts, widget-info, manifest receiver, resources) and the Flutter sync/deep-link code. `flutter analyze` is clean, but the **APK was never built here** (it needs `google-services.json` from §2). These steps are all **manual** — they need a real build and a physical device.

## 4.1 Build & install

```powershell
flutter pub get
flutter run            # on a connected Samsung/emulator (debug build is fine)
```

> If the Android build fails, it's almost always a missing/!mismatched resource or `google-services.json` — read the Gradle error. The widget code uses only RemoteViews-supported views, so failures here are environment/config, not widget structure.

## 4.2 Add the widget to the home screen

1. Long-press the home screen → **Widgets** → find **pictionary_app** → drag the widget out.
2. It should render **State 1** (today's 3 word choices) once you've signed in and the app has pushed data at least once. (The widget is seeded on sign-in and on app resume; open the app once after install.)

## 4.3 Verify the 3 states

- **State 1 (haven't drawn):** widget shows the 3 words. **Tap a word** → app opens straight to the drawing canvas for that word.
- **State 2 (drew; friends to guess):** after you submit a drawing (and a friend has too), the widget shows friend rows. **Tap a friend** → app opens that friend's guessing screen. Friends who haven't drawn show "waiting". Tapping elsewhere → feed.
- **State 3 (drew + guessed everyone):** after you've guessed every available friend, the widget shows your **streak**, day, and "You guessed X/Y correctly". Tapping → results.

## 4.4 Verify deep links (cold + warm)

- **Warm:** app already running in background → tap a widget cell → it navigates to the right screen.
- **Cold:** fully close the app → tap a widget cell → app launches directly to that screen (handled via `initiallyLaunchedFromHomeWidget`).

## 4.5 Verify refresh

- Submit a drawing in the app → the widget should flip from State 1 to State 2 (it refreshes on resume and right after submit/guess).
- (Optional, ties into Phase 3) when a friend submits, the FCM push lands; opening/resuming the app refreshes the widget.

## Verification checklist — Phase 4

- [ ] App builds and installs on a real device
- [ ] Widget can be added to the home screen and renders State 1
- [ ] Tapping a word opens the canvas for that word
- [ ] After submitting, the widget shows State 2 with friend rows; tapping a friend opens their guess screen
- [ ] After guessing everyone, the widget shows State 3 (streak + X/Y correct)
- [ ] Cold-start and warm deep links both navigate correctly

### Known Phase 4 followups (not blockers)
- **Friend thumbnails**: state 2 currently shows initials + name, not the actual drawing thumbnails (loading remote images into a RemoteViews widget needs async bitmap fetching — deferred). Add later if desired.
- Confirm the **state-3 tap route** (`/results`) is where you want the widget to take the user.

Once Phase 4 checks out on device, the v1.0 MVP feature set is complete — remaining work is **Phase 5 (polish & iOS)**.
