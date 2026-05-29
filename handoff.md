# Session Handoff

Read this first when resuming. It captures what's done, what's pending, and where to pick up.

---

## What this project is

A daily Pictionary app — Flutter (Android-first), Firebase backend, with an Android home-screen widget. See [`pictionary-app-spec.md`](./pictionary-app-spec.md) for the full product spec.

---

## What was done last session

### Phase 1 — Foundation: scaffolded ✅

All of these are written and committed to disk (not yet to git):

**Project config**
- `pubspec.yaml` (Firebase + Riverpod + GoRouter + home_widget + intl)
- `analysis_options.yaml`
- `.gitignore` (Flutter + Firebase secrets)
- `firebase.json`, `.firebaserc` (empty — populated by `firebase use --add`)
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`
- `assets/words.json` (offline-fallback word list)

**Dart code (`lib/`)**
- `main.dart` + `app.dart` — Firebase init, `MaterialApp.router`, M3 theme
- `firebase_options.dart` — **placeholder, throws until `flutterfire configure` regenerates it**
- `core/providers.dart` — Riverpod providers for FirebaseAuth, Firestore, Storage, services
- `core/auth/auth_service.dart` — Google Sign-In + auto-creates `users/{uid}` doc with a 6-char invite code
- `core/firebase/firestore_service.dart` — watch user / daily words / player rounds / friend feed; write word choice / drawing / guess
- `core/firebase/storage_service.dart` — PNG upload to `rounds/{date}/{uid}.png`
- `core/notifications/fcm_service.dart` — persists FCM token to user doc
- `core/routing/app_router.dart` — GoRouter with auth-gated redirect
- `core/util/today.dart` — UTC `YYYY-MM-DD` key
- `models/` — `AppUser`, `DailyWords`, `PlayerRound`, `Guess` (all with Firestore (de)serialization; `Guess.idFor()` matches the `{guesserId}_{drawerId}` doc-ID pattern)
- `features/auth/sign_in_screen.dart` — working Google Sign-In screen
- `features/word_selection/word_selection_screen.dart` — **wired end-to-end** (reads `daily/{date}`, writes `chosenWord`, navigates to canvas)
- `features/profile/profile_screen.dart` — shows display name / invite code / streak / sign-out
- `features/canvas|feed|guessing|results|friends/` — stub screens (real impls in Phase 2+)

**Cloud Functions (`functions/`)**
- `package.json`, `tsconfig.json`, `.gitignore`
- `src/index.ts` + `src/dailyReset.ts` — scheduled `0 0 * * *` UTC, picks 3 random words from `wordList/master` doc (or built-in fallback) → writes `daily/{YYYY-MM-DD}`

### Toolchain set up ✅

- **Flutter SDK 3.44.0** installed to `C:\Users\arvin\flutter`, added to User PATH
- **Android cmdline-tools** installed to the existing SDK at `C:\Users\arvin\AppData\Local\Android\Sdk\cmdline-tools\latest`
- `ANDROID_HOME` set as a User env var
- **All Android SDK licenses accepted**
- `flutter create .` ran — `android/` and `ios/` platform folders generated alongside the pre-existing `lib/`
- `flutter pub get` — 135 deps resolved
- `npm install` in `functions/` — done
- `flutter analyze` — **No issues found**
- `flutter doctor` — green for Android dev (Visual Studio is the only ✗, only needed for Windows desktop, not Android)

### Gotchas hit and fixed

- `custom_lint ^0.6.7` + `riverpod_lint ^2.3.13` pinned to a removed `_macros` package → both dropped from `pubspec.yaml` dev_dependencies
- `flutter create` left a default `test/widget_test.dart` referencing `MyApp` (template counter app) → replaced with a trivial smoke test so `flutter analyze` stays clean
- `.firebaserc` original placeholder string `REPLACE_WITH_FIREBASE_PROJECT_ID` made every `firebase ...` command error out → emptied to `{"projects":{}}` to be filled by `firebase use --add`

---

### Phase 2 — Core Game: implemented ✅ (latest session)

Built by the `pictionary-phase2` workflow (4 parallel implementers → `flutter analyze` gate → 3-dimension review), then the review's blockers were fixed by hand. `flutter analyze` is **clean**. All on disk, **not yet committed**.

**Screens (all real now, replacing the Phase 1 stubs):**
- `lib/features/canvas/canvas_screen.dart` — `CustomPainter` drawing: `DrawingStroke{points,color,strokeWidth}`, 8-color palette, brush-size slider, undo/clear, submit. Submit = `RepaintBoundary.toImage(pixelRatio:3)` → PNG → `StorageService.uploadDrawing()` → `FirestoreService.submitDrawing()` → `context.go('/feed')`.
- `lib/features/feed/feed_screen.dart` — anti-cheat-gated 2-col grid; only renders friends' drawings once your own `PlayerRound.hasSubmittedDrawing == true`; submitted friends show a `CachedNetworkImage`, others a "waiting" placeholder; tap → `/guess/:drawerId`.
- `lib/features/guessing/guessing_screen.dart` — anti-cheat gate + drawer image + 3-attempt free-text (normalized compare to `chosenWord`); seeds from any existing `Guess` so the 3-try cap survives re-entry; writes via `recordGuess()`.
- `lib/features/results/results_screen.dart` — daily summary (streak, your word/submission, friends-drew count); friend read is gated behind your own submission.

**Service-layer changes (`lib/core/firebase/firestore_service.dart`):**
- `watchFriendDrawings()` now **chunks `friendIds` into batches of 30** (Firestore `whereIn` cap) and merges the streams via an internal `_combineLatest`.
- Added `watchGuess({date, guesserId, drawerId})` → `Stream<Guess?>` (used by the guessing screen to enforce the cap across navigations).

**Review findings fixed:** (1) results screen no longer issues a forbidden pre-submission friend read; (2) guessing screen can't re-enter to reset/clobber a recorded guess; (3) `watchFriendDrawings` no longer throws for >30 friends.

---

## What's still pending — manual setup (NEVER COMPLETED)

⚠️ The interactive Firebase/device setup from the original plan has **not** been done — `lib/firebase_options.dart` is still the placeholder that throws, and there's no `google-services.json`. **The app cannot run until these are completed.** They all need browser OAuth / console clicks / a physical device, so they can't be scripted from a Claude session.

See [`next_steps.md`](./next_steps.md) for the full ordered, copy-pasteable checklist. High level:

1. `firebase login` + create the Firebase project (Blaze plan) + enable Auth/Firestore/Storage/Functions/Messaging
2. `firebase use --add`
3. `flutterfire configure` (overwrites placeholder `lib/firebase_options.dart`, drops `google-services.json`)
4. `firebase deploy --only firestore:rules,storage:rules,firestore:indexes,functions`
5. Seed `daily/{today}` doc (or run `dailyWordReset` once from the console)
6. Connect a Samsung (USB debugging) or create an emulator
7. `flutter run`

---

## Where to pick up next session

Open this file plus `next_steps.md`.

### Phase 3 — Social & Notifications: implemented ✅ (latest session)

Built by the `pictionary-phase3` workflow (backend ‖ flutter implementers → analyze+tsc gate → 3-dimension review), then the review's blockers were fixed by hand. `flutter analyze` is **clean** and `cd functions; npm run build` (tsc) **compiles**. On disk, **not yet committed**, and **not yet deployed** (deploy is manual — see `next_steps.md` §Phase 3).

**Backend (`functions/src/`):**
- `friendInvite.ts` — `addFriendByCode` onCall callable: auth-gated, normalizes/validates the code, rejects self-add, idempotent if already friends, links both directions via `arrayUnion` (admin SDK, bypasses rules).
- `notifications.ts` — `onDrawingSubmitted` (friend drew → notify friends, `route:/feed`) and `onGuessCorrect` (correct guess → notify drawer, `route:/results`). Both only fire on the real field transition.
- `streak.ts` — `onDrawingStreak`: transaction updating `streakCount`/`lastPlayedDate` on submit (idempotent; +1 if yesterday, else reset to 1).
- `dailyReset.ts` — now also broadcasts a `topic:'daily'` push after writing the words.
- `index.ts` — exports all four new functions.

**Flutter (`lib/`):**
- Added `cloud_functions: ^5.1.3` to `pubspec.yaml`; new `FunctionsService` + `functionsServiceProvider`.
- `friends_screen.dart` — real: shows your invite code (copy button), add-by-code field calling the callable, friends list resolving ids → names.
- `fcm_service.dart` — subscribes to the `daily` topic, foreground listener, `wireNotificationTaps(onOpen)` for deep links.
- `app.dart` — now a `ConsumerStatefulWidget` that **registers the FCM token on every sign-in** (`fcmServiceProvider.registerForUser`) and wires `wireNotificationTaps(router.go)` once; `fcmServiceProvider` added to `providers.dart`; the old TODO in `main.dart` is gone.

**Review blockers fixed:**
- ⚠️ **Security:** `onGuessCorrect` no longer trusts the client-set `correct`/`drawerId`. It now re-verifies server-side (doc id == `guesserId_drawerId`, drawer has a submitted round, an attempt actually matches `chosenWord`) before sending — closes a push-spam/forgery vector against arbitrary users.
- **`firestore.rules` CHANGED** (guesses): doc id must equal `<guesserId>_<drawerId>`, you can't guess your own drawing, and guesser/drawer are immutable on update. **This means the next deploy must include `--only firestore:rules`** (already noted in `next_steps.md` §3.1).
- Fixed the correct-guess deep link (was the composite guess id → a non-existent route).

**Followups resolved this session:** FCM token registration is now wired post-auth in `app.dart`, and tap-to-navigate is wired with the router — both previously-open gaps are closed.

---

### Phase 4 — Home-Screen Widget: implemented ✅ (latest session)

Built by the `pictionary-phase4` workflow (native ‖ flutter implementers → analyze+static gate → review). `flutter analyze` is **clean**. The Android APK **cannot be built here** (needs `google-services.json` from the manual Firebase setup), so the native side was verified by **static inspection** only — a real build + on-device test is a manual step (see `next_steps.md` §Phase 4). On disk, **not committed**.

> Workflow note: 3 subagents (the Android *implementer* and 2 of 3 reviewers) finished their work but failed to emit their final structured summary. The Android files were written and independently confirmed by the verify agent; the two missing reviews (Flutter-sync + cross-side contract) and the one bug they'd have caught were done/fixed by hand afterward.

**Native Android (`android/app/src/main/`):**
- `kotlin/.../PictionaryWidgetProvider.kt` — extends `home_widget`'s `HomeWidgetProvider`; picks one of 3 layouts by `w_state`, parses `w_words`/`w_friends` via `org.json`, sets per-cell deep-link `PendingIntent`s via `HomeWidgetLaunchIntent`.
- `res/layout/pictionary_widget_state{1,2,3}.xml` — RemoteViews-only layouts (state1: 3 word cells; state2: 3 friend rows + "see all"; state3: streak/day/summary).
- `res/xml/pictionary_widget_info.xml`, plus `res/values/` colors/dimens/strings and widget background drawables.
- `AndroidManifest.xml` — added the `<receiver>` (exported, `APPWIDGET_UPDATE` + provider meta-data); existing activity untouched.

**Flutter (`lib/`):**
- `services/widget_service.dart` — `WidgetService.sync(...)` (jsonEncodes words/friends, `saveWidgetData` the 7 keys, `updateWidget`) and `refresh({firestore, uid})` that computes the 3-state from Firestore (anti-cheat: state 2/3 only after own submission) — fully error-swallowing so it never crashes startup.
- `core/providers.dart` — `widgetServiceProvider`.
- `app.dart` — wires `HomeWidget.widgetClicked` + `initiallyLaunchedFromHomeWidget` → `router.go(route)`; refreshes the widget on resume (via `WidgetsBindingObserver`) and after sign-in; FCM wiring preserved.
- `canvas_screen.dart` / `guessing_screen.dart` — best-effort widget refresh after submit / after recording a guess.

**Cross-side contract (verified consistent by hand):** provider class `com.pictionary.pictionary_app.PictionaryWidgetProvider`; keys `w_state`(int), `w_words`/`w_friends`(String JSON), `w_streak`/`w_day`/`w_solved`/`w_total`(int); deep-link `pictionary://open?route=<URL-encoded location>`.

**Fixed by hand:** `refresh()` was using one "guessed" count for both the state-2→3 transition *and* the "guessed X/Y correctly" summary — split into `completed` (drives the transition) vs `correct` (shown in the summary).

**Known followups (not blockers):** friend **thumbnails** aren't rendered yet — state 2 shows initials/placeholder + name (loading remote images into RemoteViews needs async bitmap fetching, deferred); confirm the state-3 tap route (`/results`) is the desired destination.

### If the manual setup is NOT done

Walk through `next_steps.md` §1–7 together first — the app can't boot otherwise. Likely sticking points:
- Blaze plan upgrade (needs a credit card on Google Cloud Billing)
- Samsung USB debugging not enabled / driver issue → check `adb devices` from `%LOCALAPPDATA%\Android\Sdk\platform-tools`

---

## Roadmap (remaining phases)

| Phase | Scope | Codeable by workflow? | Manual parts |
|---|---|---|---|
| **3 — Social & Notifications** | Friend invites, FCM (3 triggers), streak logic | ✅ **DONE** (`pictionary-phase3`) | deploy functions **+ rules**; test invites & push on a real device |
| **4 — Home-Screen Widget** | Android `AppWidgetProvider`, 3 states, `home_widget` sync, deep links, refresh on FCM | ✅ **DONE** (`pictionary-phase4`) — code written + statically verified | build APK; add widget to home screen; verify 3 states + deep-link taps on device; (later) friend thumbnails |
| **5 — Polish & iOS** | Animations, empty/error states, iOS build, TestFlight, APNs key | ⚠️ Dart polish yes; iOS/APNs no | Apple Developer acct, APNs key upload, TestFlight |

### Friendly reminders for next session

- Working dir: `C:\Projects\Pictionary Widget`
- Open a **fresh PowerShell** each new session — env vars from this session won't be active in old terminals
- `flutter` is at `C:\Users\arvin\flutter\bin\flutter.bat` (on PATH)
- Firebase CLI 15.18.0 is global via npm
- Today's UTC date key for testing: use `(Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')`
- The user is on Windows 11, PowerShell — chain commands with `;` not `&&`

---

## Files worth re-reading next session

| File | Why |
|---|---|
| `pictionary-app-spec.md` | Full product spec — phases, data model, widget design |
| `lib/core/firebase/firestore_service.dart` | All Firestore read/write surface (now incl. chunked `watchFriendDrawings` + `watchGuess`) |
| `firestore.rules` / `storage.rules` | Anti-cheat invariants you must not break |
| `lib/features/feed/feed_screen.dart` | Reference for the anti-cheat gate pattern (replicate it anywhere you read friend data) |
| `lib/features/word_selection/word_selection_screen.dart` | Original fully-wired screen — the Riverpod/`.when()`/`todayKey()` style all screens follow |
| `lib/core/auth/auth_service.dart` | Invite-code generation + `users/{uid}` doc shape — Phase 3 friend invites build on this |
| `functions/src/index.ts` / `dailyReset.ts` | Cloud Functions entrypoint + the v2 scheduled-function pattern Phase 3 follows |
| `lib/core/routing/app_router.dart` | All routes + their path params |

---

## Open decisions deferred from spec

Still unresolved (from spec lines 369–376) — surface when relevant:
- Scoring system (skipped for MVP)
- Word difficulty tiers
- Local vs UTC midnight for daily reset (currently UTC)
- Drawing time limit
- When the chosen word is revealed to wrong-guessers
- Multi-group support
