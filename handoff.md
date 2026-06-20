# Session Handoff

Read this first when resuming. It captures what's done, what's pending, and where to pick up.

---

## What this project is

A daily Pictionary app — Flutter (Android-first), Firebase backend, with an Android home-screen widget. See [`pictionary-app-spec.md`](./pictionary-app-spec.md) for the full product spec.

---

## What was done last session

### Quality pass — all bugs fixed ✅ (latest session)

Full audit of all 25 Dart files + 5 TypeScript files. 9 issues found and fixed. `flutter analyze` clean (run locally to confirm — Flutter not in the CI sandbox). All on disk, **not committed**.

**Fixes applied:**

- **`lib/core/notifications/fcm_service.dart`** — Fixed memory leak: `onTokenRefresh` subscription now stored in `_tokenRefreshSub` and cancelled before reassigning on each sign-in. Removed dead `onMessage → debugPrint` no-op and its `flutter/foundation` import.

- **`lib/app.dart`** — Moved `wireNotificationTaps` + `_wireWidgetTaps` from `build()` into `didChangeDependencies()` (side-effects don't belong in build). Added `unawaited(...)` to both the `_refreshWidget()` helper and the `ref.listen` callback's widget refresh call.

- **`lib/features/word_selection/word_selection_screen.dart`** — "See friends' drawings" button changed from `context.push('/feed')` to `context.go('/feed')` so it switches tabs rather than stacking a duplicate route.

- **`lib/services/widget_service.dart`** — Replaced sequential per-friend `await` loops with `Future.wait` — all guess lookups and display-name fetches now run in parallel.

- **`lib/features/friends/friends_screen.dart`** — `_FriendTile` loading/error states now show "Loading…" / "Unknown" instead of raw Firestore UIDs.

- **`functions/src/notifications.ts`** — `onGuessCorrect` now uses `send({token})` instead of `sendEachForMulticast({tokens:[token]})` for a single-recipient push.

- **`pubspec.yaml`** — Removed unused `riverpod_annotation` (was in runtime deps), `build_runner`, and `riverpod_generator` (project uses hand-written providers; no code-gen).

**Offline banner:** still deferred — `connectivity_plus` not in pubspec. Add later if desired.

---

### Phase 5 — Polish: implemented ✅

Built by 4 parallel Sonnet agents overseen by Fable, then verified by manual code review. All on disk, **not committed**.

**Files changed:**

- **`lib/core/routing/app_router.dart`** — Added Material 3 `NavigationBar` (4 tabs: Home, Feed, Friends, Profile) via `ShellRoute` + `_AppShell`. Canvas, Guess, and Results push on top of the shell (no nav bar). Selected tab derived from URI path.

- **`lib/core/providers.dart`** — Added `friendNamesProvider`: a `StreamProvider.autoDispose.family<Map<String, String>, List<String>>` that concurrently watches user docs for all given uids and emits a merged `{uid → displayName}` map. Falls back to the uid until the doc arrives.

- **`lib/features/feed/feed_screen.dart`** — `_PlaceholderTile` and `_DrawingTile` now resolve display names via `friendNamesProvider` (no more raw uids in the UI). All `.when()` error branches replaced with `ErrorState(onRetry: ...)`.

- **`lib/features/canvas/canvas_screen.dart`** — Word reminder banner below AppBar, confirm dialog before clear, submit button `ScaleTransition` (disabled/grey when canvas empty).

- **`lib/features/guessing/guessing_screen.dart`** — "X attempts remaining" counter, sin-wave shake animation on wrong guess, green SnackBar + 1.5s delay on correct guess before navigating to feed. Error branches use `ErrorState`.

- **`lib/features/word_selection/word_selection_screen.dart`** — `_WordCard` converted to `StatefulWidget` with bounce `TweenSequence` animation + selected state.

- **`lib/features/friends/friends_screen.dart`**, **`lib/features/profile/profile_screen.dart`**, **`lib/features/results/results_screen.dart`** — All bare error text replaced with `ErrorState(onRetry: ...)`.

- **`lib/widgets/error_state.dart`** *(new)* — Reusable error widget: error icon + message + optional "Try again" `FilledButton.tonal`.

---

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

## Manual setup — DONE ✅ (2026-06-14: Firebase connected, app runs on device)

The interactive Firebase/device setup is now **complete**. The app boots on a physical Samsung (SM S928W), Google sign-in works, and the Phase 2 draw→submit→feed loop runs end-to-end.

What got done this session:
1. ✅ `firebase login` + Firebase project **`pictionary-widget`** created (Blaze plan); Auth (Google), Firestore, Storage, Functions, Messaging enabled.
2. ✅ `firebase use --add` → `.firebaserc` now points at `pictionary-widget`.
3. ✅ `flutterfire configure` → real `lib/firebase_options.dart` + `android/app/google-services.json` (the latter gitignored).
4. ✅ `firebase deploy` — storage/firestore rules, indexes, and **all 5 functions** live (`dailyWordReset`, `addFriendByCode`, `onDrawingSubmitted`, `onGuessCorrect`, `onDrawingStreak`).
5. ✅ Seeded today's `daily/{date}` words.
6. ✅ Samsung connected via USB debugging; `flutter run` builds + installs.
7. ✅ Signed in with Google, picked a word, drew, submitted → landed on feed.

**Setup gotchas hit & resolved (so they don't bite again):**
- `flutterfire` not on PATH after `dart pub global activate` → Pub Cache bin (`%LOCALAPPDATA%\Pub\Cache\bin`) added to user PATH; needs a fresh shell to take effect.
- `firebase deploy --only ...,storage:rules,...` fails with "Could not find rules for storage targets: rules" — Storage uses **`storage`**, not `storage:rules` (Firestore keeps `:rules`/`:indexes`). **The `next_steps.md` START HERE / §3 commands still have this typo — fix when convenient.**
- Storage needs a one-time **Get Started** click in the console before the first deploy.
- First 2nd-gen functions deploy failed 3 Firestore-triggered functions with an Eventarc Service Agent permission error — **just wait a few minutes and re-run `firebase deploy --only functions`** (permissions propagate).
- Google sign-in threw `PlatformException` until the **debug SHA-1** was added to the Firebase Android app and `google-services.json` re-downloaded. Debug SHA-1: `12:FD:7D:D9:74:3D:0F:0C:B4:46:28:3B:E7:F1:02:BE:52:BD:39:D3` (SHA-256 also added). A release SHA-1 will be needed for a signed/release build later.
- Two `storage.rules` bugs fixed + redeployed (see "Known bugs" below and `next_steps.md`).

⚠️ **Still NOT done on device:** Phase 3 (friend invites + push, needs a 2nd account) and Phase 4 (add the home-screen widget). See `next_steps.md` Phase 3 / Phase 4.

---

## Current git state (2026-06-14)

Branch: **`feat/phases-2-4-game-social-widget`**.

- **Committed this session** (`496fece`): `storage.rules` (2 fixes) + `next_steps.md` (bug log).
- **Intentionally left UNCOMMITTED** (user wants to review/commit later) — ~19 modified + 2 untracked:
  - Firebase wiring generated by setup: `.firebaserc`, `firebase.json`, `lib/firebase_options.dart`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`.
  - All the Phase 2–5 `lib/**` screens + `functions/src/notifications.ts` + `pubspec.yaml` + `handoff.md` (these were already uncommitted from prior sessions — the repo only ever had the initial scaffold committed).
  - Untracked: `lib/widgets/` (contains `error_state.dart`), and **`flutter_01.png`** — a stray screenshot in the repo root that should be deleted or gitignored, **not** committed.
- Reminder: `android/app/google-services.json` must stay **gitignored** (it is). **`lib/firebase_options.dart` is now ALSO gitignored** (as of 2026-06-17) — it was briefly committed with real keys, then purged from history; do **not** re-commit it. It stays on disk locally; regenerate with `flutterfire configure` on a fresh clone. The two Firebase API keys it held should be **restricted/rotated in the Google Cloud console** (they were publicly pushed for a short window and are extractable from the APK anyway).

### Known bugs — ✅ ALL FIXED 2026-06-15 (code on disk, not committed; re-test on device)
Fixed by the `fix-ondevice-bugs` workflow; `flutter analyze` clean. Details + per-file changes in `next_steps.md` → 🐛 Known bugs.
- ~~**Home screen lets you draw twice/day.**~~ ✅ FIXED — `word_selection_screen.dart` now gates on the player's `hasSubmittedDrawing` (shows a "come back tomorrow" state); `firestore_service.chooseWord()` no longer clobbers the submit flag back to false.
- ~~**Widget: tapping a word lands on home, not the canvas.**~~ ✅ FIXED — was a cold-start auth race; `app.dart` now defers the widget deep-link and replays it from the auth listener once the user is restored.
- ~~**Widget stays on State 1 after you've drawn.**~~ ✅ FIXED — downstream of the `chooseWord` clobber; also hardened `widget_service.refresh()` so a friend-data enrichment failure can't strand the widget on State 1.

Files changed: `lib/features/word_selection/word_selection_screen.dart`, `lib/core/firebase/firestore_service.dart`, `lib/app.dart`, `lib/services/widget_service.dart`. **Still need an on-device re-test** (original symptoms were seen on the phone).

### Two-account testing fixes — 2026-06-17 (deployed via rules; rebuild for invite code)
Found while testing with two accounts. Both fixed:
- **Guessing showed "something went wrong" under the drawing + empty widget friends.** Root cause: the `firestore.rules` guesses *read* rule dereferenced `resource.data` on a not-yet-created guess doc → `PERMISSION_DENIED`. Fixed by allowing `resource == null` reads. **Server-side — `firebase deploy --only firestore:rules` activates it; no rebuild needed.**
- **2nd account had no invite code.** `auth_service._ensureUserDoc` only set `inviteCode` on first creation; now it **backfills** `inviteCode`/`friendIds`/`streakCount` on existing docs (needs a rebuild + re-sign-in, or add the field manually in Firestore).

### Security-review fixes — 2026-06-17 ✅ (code done; ⚠️ DEPLOY + REBUILD required before retesting)
From the `review-overlooked` audit (see `review-findings.md`); applied by the `fix-security-findings` workflow, `flutter analyze` + `tsc` clean, adversarial verify verdict **ship**. Scope = all HIGH/MEDIUM **security** findings + all `DO` recommendations.
- **#1 (HIGH): secret word was world-readable → guessing was cheatable.** `chosenWord` moved to an owner-only private subdoc (`rounds/{date}/players/{uid}/private/round`); a new **`submitGuess` callable** validates guesses server-side (3-attempt cap, idempotency, normalized compare, reveals the word only on finish). Guess docs are now `allow write: if false` (callable-only) — closes the forgery/tampering vectors too.
- **#2 (DO):** removed dead `toFirestore()` from `AppUser`/`PlayerRound`/`Guess`.
- **#3 (MEDIUM):** `onDrawingSubmitted` notification now claims `lastDrawingNotifiedDate` transactionally → no spam re-fire.

Deploy with `firebase deploy --only firestore:rules,functions` **and** `flutter run` (Dart changed). **Migration gotcha:** rounds drawn before this change keep the word in the old player-doc location, so guessing them returns "not ready" — start a fresh round per account (delete today's `players/{uid}` doc + its `private/round` subdoc + the `guesses/*` docs, then re-pick→draw→submit). Details in `next_steps.md` → 🔒 Security-review fixes.

Out of scope (intentionally not done): low-severity security findings (#10 guess-update tampering — now moot since guesses are callable-only; #11 wide `users` read rule) and all non-security `consider` items. See `review-findings.md`.

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

### Where we actually are (resume here)

Manual setup is **done** — the app runs on the Samsung and the Phase 2 loop works (see "Manual setup — DONE" above). Next, in priority order:

1. ~~**Fix the "draw twice/day" bug**~~ ✅ DONE 2026-06-15 (all 3 on-device bugs fixed; see Known bugs). **Needs an on-device re-test.**
2. **Phase 3 on device** — friend invites need a **second Google account**; then test the 3 push triggers on the real phone. See `next_steps.md` Phase 3.
3. **Phase 4 on device** — add the home-screen widget, verify the 3 states + deep links. See `next_steps.md` Phase 4.
4. **Commit the outstanding files** (review the ~19 modified + drop `flutter_01.png`) — see "Current git state".

The feed is currently empty because there are no friends yet — expected; Phase 3 fills it.

---

## Roadmap (remaining phases)

| Phase | Scope | Codeable by workflow? | Manual parts |
|---|---|---|---|
| **3 — Social & Notifications** | Friend invites, FCM (3 triggers), streak logic | ✅ **DONE** | deploy functions **+ rules**; test invites & push on a real device |
| **4 — Home-Screen Widget** | Android `AppWidgetProvider`, 3 states, `home_widget` sync, deep links, refresh on FCM | ✅ **DONE** — code written + statically verified | build APK; add widget to home screen; verify 3 states + deep-link taps on device; (later) friend thumbnails |
| **5 — Polish & iOS (Dart)** | Bottom nav, friend name resolution, canvas/guessing UX, error states | ✅ **DONE** (this session) | Run `flutter analyze` locally to confirm clean; iOS build + APNs + TestFlight are all manual |
| **Post-MVP** | iOS App Store submission, offline banner (`connectivity_plus`), friend thumbnails in widget (state 2), scoring/leaderboard | — | All manual or deferred |

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
