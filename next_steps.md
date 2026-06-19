# Next Steps — Things Only You Can Do

This file lists the **manual** tasks — the ones that need browser OAuth, Firebase console clicks, billing, a physical device, or Apple/Google developer accounts. None of these can be scripted from a Claude session. The actual app/Cloud-Function **code** is written for you (Phases 1–5 are done).

Run terminal steps from a **fresh PowerShell window** (so the PATH / `ANDROID_HOME` env vars are picked up):

```powershell
cd "C:\Projects\Pictionary Widget"
```

## ⭐ START HERE next session

**Foundation is DONE as of 2026-06-14** — Firebase project `pictionary-widget` is live, the app runs on the Samsung, sign-in works, and the Phase 2 draw→submit→feed loop works on device. (Setup details + gotchas are in `handoff.md` → "Manual setup — DONE".)

Pick up here, in order:

1. [x] **Fix the "draw twice/day" bug** — ✅ FIXED 2026-06-15 (all 3 known bugs below). `flutter analyze` clean.
2. [ ] **Phase 3 on device** — friend invites (needs a **2nd Google account**) + the 3 push triggers on the real phone. See Phase 3 section.
3. [ ] **Phase 4 on device** — add the home-screen widget, verify 3 states + deep links. See Phase 4 section.
4. [ ] **Commit the outstanding files** — see "Uncommitted files" below.

<details><summary>Original foundation checklist (all ✅ done 2026-06-14)</summary>

- [x] `firebase login` → create Firebase project (Blaze plan) → enable Auth/Firestore/Storage/Functions/Messaging
- [x] `firebase use --add` (project `pictionary-widget`)
- [x] `dart pub global activate flutterfire_cli` then `flutterfire configure`
- [x] `firebase deploy` — rules, indexes, all 5 functions live
- [x] Seeded today's words
- [x] USB debugging on, `flutter run`
- [x] Signed in, drew, submitted → feed

</details>

---

## 🐛 Known bugs — ✅ ALL FIXED 2026-06-15 (code only; re-verify on device)

Found during the first on-device run (2026-06-14); fixed 2026-06-15 by the `fix-ondevice-bugs` workflow (3 parallel investigators → single implementer → adversarial verify). `flutter analyze` clean. **On disk, not yet committed.** Still needs an on-device re-test (the original symptoms were observed on the phone).

Files changed: `lib/features/word_selection/word_selection_screen.dart`, `lib/core/firebase/firestore_service.dart`, `lib/app.dart`, `lib/services/widget_service.dart`.

- [x] **Home screen lets you draw again after you've already submitted today.** ✅ FIXED. The root cause was twofold: (1) `WordSelectionScreen` never checked the player's round, and (2) `chooseWord()` merged `hasSubmittedDrawing: false`, so re-tapping a word *clobbered* an existing submission (re-locking anti-cheat reads + double-firing streak/notification triggers).
  - **Fix:** added a `_myRoundProvider` (watches `watchPlayerRound(todayKey(), uid)`); when `hasSubmittedDrawing == true` the screen renders a "You've drawn today — come back tomorrow" state (with the submitted drawing + a button to `/feed`) instead of tappable word cards. `chooseWord()` no longer writes `hasSubmittedDrawing: false` (the flag still defaults false on first create), so a stray re-tap can never clobber a submission.

- [x] **Widget: tapping a word opens the app to the home screen instead of the canvas for that word.** ✅ FIXED. Root cause: a **cold-start auth race** — the deep link was consumed in `didChangeDependencies` while `FirebaseAuth.currentUser` was still null, so the go_router redirect bounced it `/sign-in → /`, dropping the canvas target. (The native Kotlin route value was correct.)
  - **Fix (`lib/app.dart`):** `_openFromWidget` now stores the route in `_pendingDeepLink` when `currentUser == null` and the `authStateChanges` listener replays it (post-frame, clear-before-navigate) once the user is restored. Warm taps are unchanged.

- [x] **Widget still offers new words to draw after you've already drawn.** ✅ FIXED — was a downstream consequence of the `chooseWord` clobber above. Also hardened `widget_service.refresh()`: it now syncs a baseline State 2 right after detecting `hasSubmittedDrawing == true` and wraps the friend-data enrichment in its own try/catch, so an enrichment failure can no longer abort the whole refresh and strand the widget on State 1.

## 🔒 Security-review fixes — code done 2026-06-17 (⚠️ DEPLOY + REBUILD required)

Fixed by the `fix-security-findings` workflow (single implementer → adversarial verify; `flutter analyze` + `tsc` clean, verdict **ship**). On disk, **not yet committed/deployed**. These came from the `review-overlooked` audit (`review-findings.md`).

- **#1 (HIGH) — the secret word was readable from Firestore → guessing was trivially cheatable.** `chosenWord` now lives in an **owner-only private subdoc** (`rounds/{date}/players/{uid}/private/round`); the friend-readable player doc no longer holds it. Guesses are validated by a **new `submitGuess` Cloud Function** (callable) — it reads the word via the admin SDK, enforces the 3-attempt cap + idempotency + normalized compare server-side, and reveals the word only when you finish. Firestore rules now lock guess docs to `allow write: if false` (callable-only), which also closes the earlier forgery/tampering vectors.
- **#2 (DO) — dead code.** Removed the unused `toFirestore()` methods from `AppUser`, `PlayerRound`, `Guess`.
- **#3 (MEDIUM) — notification spam.** `onDrawingSubmitted` now claims `lastDrawingNotifiedDate` in a transaction (mirrors the streak fn), so toggling submit can't re-fire the push.

Files: `firestore.rules`, `functions/src/{submitGuess.ts (new),index.ts,notifications.ts}`, `lib/core/firebase/{firestore_service,functions_service}.dart`, `lib/models/{player_round,guess,app_user}.dart`, `lib/features/guessing/guessing_screen.dart`, `lib/features/results/results_screen.dart`.

**To activate (do BEFORE retesting guessing/widget):**
```powershell
firebase deploy --only firestore:rules,functions   # publishes the new submitGuess callable + locked guess rules
flutter run                                         # rebuild — the guessing/results screens + models changed
```

**⚠️ Data-migration gotcha (important for your current test accounts):** any round drawn *before* this change has its `chosenWord` in the **old** player-doc location, not the new private subdoc. After deploying, guessing such a drawing returns *"This drawing isn't ready to guess yet"* (the callable finds no word). To retest cleanly, **start fresh on each account**: in Firestore delete today's `rounds/{date}/players/{uid}` doc **and** its `private/round` subdoc (and the `rounds/{date}/guesses/{guesserId}_{drawerId}` docs), then re-pick a word → draw → submit. New rounds write the word to the private subdoc automatically.

## 🗺️ Feedback backlog & roadmap — from on-device testing (2026-06-18)

Guessing works end-to-end after the security deploy. New items found while testing, ordered **most → least important**. All are **code tasks** (codeable via workflows), separate from the manual device steps further down. Each notes the grounded root cause (for bugs), the recommended lightest approach, and a rough effort (S/M/L).

### P1 — 🐛 CRITICAL: every user gets the SAME 3 words (per-user word selection)
- **Symptom:** both accounts see the same 3 word choices, so two friends often draw the same word → guessing is pointless.
- **Cause (confirmed):** `functions/src/dailyReset.ts` writes ONE shared `daily/{date}.wordChoices`; `word_selection_screen.dart` reads that same doc for everyone.
- **Fix (server-authoritative, fits the private-word model):** new callable `getMyWords({date})` → on first call per user/day, pick 3 random words from `wordList/master`, store them in the owner-only private round doc (`rounds/{date}/players/{uid}/private/round.wordChoices`), and return them. **Idempotent** — returns the stored set on later calls so words can't be re-rolled for easier ones. `word_selection_screen` calls it instead of reading `daily/{date}`. Widget State-1 reads the per-user words (owner-readable private doc). Keep `dailyReset` only for the daily "new words" push / pool refresh; the shared `daily/{date}` doc can be retired.
- **Also:** expand `wordList/master` to 100+ words (currently ~30 fallback) so all-3 collisions are rare. Pure-random from a large pool makes "all 3 identical" very unlikely; strict per-friend-group uniqueness is a harder constraint — optional later.
- **Touches:** new `functions/src/getMyWords.ts` + `index.ts`, `functions_service.dart`, `firestore_service.dart`, `word_selection_screen.dart`, `widget_service.dart`. **Effort: M.**

### P2 — 🐛 CRITICAL: widget "guess" opens Home instead of the feed/guess screen
- **Symptom:** tapping a friend (or "see all") in the widget foregrounds the app at Home, not the guess/feed screen.
- **Cause (grounded):** `MainActivity` is a bare `FlutterActivity` with no `onNewIntent` override. On a **warm** relaunch (app already running) Android delivers the widget deep-link as a *new intent* to the existing activity, but `home_widget` only captures the launch intent on create — so `HomeWidget.widgetClicked` never fires and the app just resumes at its last route (Home). The cold-start path (fixed earlier) works; warm doesn't.
- **Fix:** override `onNewIntent` in `MainActivity` to forward the intent to `HomeWidgetPlugin` (the documented warm-launch hook) so `widgetClicked` fires and `app.dart` `_openFromWidget` navigates. Friend rows already carry `/guess/{uid}` — verify.
- **Touches:** `MainActivity.kt` (+ maybe manifest `launchMode`). **Effort: S.**

### P3 — ✅ DONE 2026-06-18 (rebuild to see): feed shows whose drawing + a guessed indicator
Implemented in `feed_screen.dart`: each tile now has a bottom scrim with the drawer's name (left) and a status badge (right) — green ✓ once you've guessed it correctly, red ✗ once you're out of attempts, nothing while unfinished. Uses a `_myGuessProvider` (your guess per drawer via `watchGuess`). `flutter analyze` clean. Just needs `flutter run`.
- **Symptom:** with many friends you can't tell whose drawing is whose (the name is only a hidden long-press `Tooltip`), and there's no sign you've already guessed one.
- **Fix:** (a) show the drawer's display name as a visible caption on each tile (already resolved via `friendNamesProvider`); (b) per tile, watch your guess (`watchGuess(date, uid, drawerId)`) and overlay a badge bottom-right: green ✓ (correct), red ✗ (finished, wrong), none (not yet guessed).
- **Touches:** `feed_screen.dart` (UI only; providers already exist). **Effort: S–M.**

### P4 — ✅ DONE 2026-06-18 (⚠️ deploy + rebuild): hint button in guessing
New `getGuessHint` callable returns `{wordLength, firstLetter}` (word stays server-only). The guessing screen shows hangman-style blanks for the length + a one-time free "Hint" button revealing the first letter. Exact-match unchanged (no fuzzy matching). `flutter analyze` + `tsc` clean. **Activate:** `firebase deploy --only functions` + `flutter run`.

<details><summary>original P4 spec</summary>

### P4 — ✨ Hint button in guessing (QoL — the "too hard / exact-match" pain)
- **Symptom:** exact word in 3 tries is hard ("rocket"/"rocketship" ≠ "spaceship").
- **Fix:** a "Hint" button revealing progressive hints — **letter count** (hangman blanks) and/or **first letter**. Word is now server-only, so hints come from the server: have the guess flow (`submitGuess` or a small `getGuessContext`) return `wordLength` (cheap; show blanks) and a `firstLetter` on explicit Hint tap. Keep exact-match validation; **do NOT** add fuzzy matching (false-positive risk).
- **Touches:** the words/guess callable, `guessing_screen.dart`. **Effort: S–M.** Synergizes with P1 (same callable surface).

</details>

### P5 — ✨ Widget: show friends' actual drawing thumbnails (known Phase-4 deferral)
- **Symptom:** widget State 2 lists friends with initials/placeholder, not their drawings.
- **Fix:** RemoteViews can't load network images directly — fetch each friend's PNG to a Bitmap natively (`setImageViewBitmap`, e.g. via coroutine/Glide) in `PictionaryWidgetProvider`, or pre-download in Flutter and pass local file paths.
- **Touches:** `PictionaryWidgetProvider.kt` (native bitmap fetch), maybe `widget_service.dart`. **Effort: M.**

### P6 — ✅ DONE 2026-06-18 (rebuild only): Home shows "who guessed your drawing today"
`watchGuessesForDrawer` (drawer reads `guesses where drawerId == self` — rules already allow it; single-field auto-index, **no index change**). The post-submit Home state now lists each guesser (name via `friendNamesProvider`) with ✓ "guessed in N" / ✗ "didn't get it" / "guessing…", inside a scroll view. `flutter analyze` clean. Dart-only — just `flutter run` (no deploy).

<details><summary>original P6 spec</summary>
- **Symptom:** want a list of friends who guessed your word, with their guesses / #tries / pass-fail.
- **Fix:** on the post-submit Home state, query `rounds/{date}/guesses where drawerId == uid` (rules already let the drawer read these). Show each guesser (name via `friendNamesProvider`), correct/failed, `solvedOnAttempt`. Add a Firestore composite index on `guesses` (drawerId).
- **Touches:** `word_selection_screen.dart` ("you've drawn today" state), `firestore_service.dart`, `firestore.indexes.json`. **Effort: M.**

</details>

### P7 — ✅ DONE 2026-06-18 (⚠️ deploy + rebuild): profile Wordle-style stats
`submitGuess` now increments the guesser's `users/{uid}.guessStats` (correct / failed / win1·win2·win3) **exactly once on the finishing transition** via a `WriteBatch` + `FieldValue.increment`. `AppUser` parses `guessStats`; the profile shows total correct/missed + a 1/2/3-try win distribution (zero-state when empty). Stats accrue going forward only (past guesses aren't backfilled). `flutter analyze` + `tsc` clean. **Activate:** `firebase deploy --only functions` + `flutter run`.

> Also fixed (2026-06-18): the P6 "who guessed your drawing" list was showing raw UIDs — `friendNamesProvider` is `List`-keyed and a fresh list each build kept it stuck in loading. Replaced with a stable per-uid `_guesserNameProvider` (String key). Dart-only.

<details><summary>original P7 spec</summary>
- **Symptom:** want total correct/incorrect + a distribution of wins in 1 / 2 / 3 tries.
- **Fix:** maintain a per-user stats doc updated **server-side** by the `submitGuess` callable on the finishing transition (increment `totalCorrect`/`totalIncorrect` + a `[1,2,3]`-try histogram; guard double-count via the existing idempotent finished-branch). Profile reads & renders it. Server-side aggregation avoids scanning every guess doc.
- **Touches:** `submitGuess.ts`, `profile_screen.dart`, a stats model/field. **Effort: M.** Synergizes with P6 (both about guess outcomes).

</details>

**Suggested batching:** P1+P4 share the words/guess callable surface; P6+P7 share guess-outcome data (P7's stats can be written by the same `submitGuess` finishing path). P2 and P3 are independent and quick. Recommended order: **P1 → P2 → P3 → P4 → P5 → P6 → P7** (bugs first, then high-value QoL, then features).

---

### Already fixed this session (for reference)
- `storage.rules`: `{drawerId}.png` was invalid wildcard syntax → changed to `{fileName}` with `fileName == request.auth.uid + '.png'` checks.
- `storage.rules`: read rule denied the owner reading their own freshly-uploaded drawing (the `getDownloadURL()` right after upload 403'd) → added an owner-can-always-read clause.
- Both `storage.rules` fixes are **deployed AND committed** (`496fece`), along with this file's bug log.

### Uncommitted files (left for review — commit next session)
Committed so far: only `storage.rules` + `next_steps.md` (`496fece`). Everything else from the Firebase setup + Phases 2–5 is **still uncommitted on `feat/phases-2-4-game-social-widget`**:
- Firebase wiring: `.firebaserc`, `firebase.json`, `lib/firebase_options.dart`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`
- App code: all modified `lib/**` screens, `functions/src/notifications.ts`, `pubspec.yaml`, `handoff.md`
- Untracked: `lib/widgets/` (`error_state.dart`) — should be committed; **`flutter_01.png`** (stray screenshot in repo root) — **delete or gitignore, do NOT commit**
- Keep `android/app/google-services.json` **gitignored** (it is). **`lib/firebase_options.dart` is now gitignored too** (2026-06-17) — it was briefly committed with real keys, then purged from history; do not re-commit it. Regenerate via `flutterfire configure` on a fresh clone. **TODO (manual, you):** restrict/rotate the 2 Firebase API keys in the Google Cloud console (they were briefly public).

### ✏️ Doc fix for next time
The START HERE / §3 deploy commands below still say `storage:rules` — that **errors**. For Storage use just `storage` (Firestore keeps `firestore:rules`/`firestore:indexes`). Correct form:
`firebase deploy --only firestore:rules,storage,firestore:indexes,functions`

---

## Manual checklist at a glance

**Before anything runs (one-time foundation — NOT yet done):**
- [ ] §1 `firebase login` + create project (Blaze plan) + enable Auth/Firestore/Storage/Functions/Messaging
- [ ] §1 `firebase use --add`
- [ ] §2 `flutterfire configure` (replaces the placeholder `lib/firebase_options.dart`)
- [ ] §3 `firebase deploy` (rules, indexes, functions)
- [ ] §4 Seed `daily/{today}` once
- [ ] §5 Connect a Samsung (USB debugging) or create an emulator
- [ ] §6 `flutter run` and smoke-test the Phase 1 + Phase 2 game loop

**After the Phase 3 code is written (already done — just needs deploy + test):**
- [ ] `cd functions; npm install` then `firebase deploy --only functions`
- [ ] `flutter pub get` (picks up the `cloud_functions` package)
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
