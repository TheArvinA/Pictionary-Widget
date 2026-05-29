# Pictionary Daily — Project Spec

## Overview

A daily mobile app (Flutter) where friends take turns drawing a word and guessing each other's drawings. One round per day, per group. The app also ships with a **home screen widget** (Android-first) that surfaces the entire game loop without ever opening the app — pick your word, see friends' drawings, track your streak.

**Target platforms:** Android first (test on Samsung), iOS shortly after (same Flutter codebase).

---

## Core Game Loop

1. Each day, **3 random words** are presented to every player.
2. The player picks **one word** and draws it on a canvas.
3. Once submitted, the player can view **friends' drawings** and try to guess what they drew.
4. Guessing is **free-text with up to 3 attempts** per friend's drawing.
5. At the end of the day (or once everyone has drawn and guessed), results are revealed.
6. Repeat daily. A **streak counter** tracks consecutive days played.

**Anti-cheat rule:** A player must submit their own drawing before they can see or guess any friend's drawing. Enforced server-side via Firestore Security Rules.

---

## Home Screen Widget — States

The Android home screen widget has **three distinct states** based on daily progress:

### State 1 — Haven't drawn yet
- Shows the **3 word choices** as tappable buttons/cards.
- Tapping a word records the selection and **opens the app directly to the drawing canvas** for that word.

### State 2 — Have drawn; friends have drawings to guess
- Shows **thumbnail previews of friends' submitted drawings** (those who have drawn so far).
- Tapping a friend's drawing **opens the app to the guessing screen** for that drawing.
- Friends who haven't drawn yet are shown as a placeholder ("waiting for [name]…").

### State 3 — Have drawn AND guessed all available friends' drawings
- Shows the **streak counter** and current day number.
- Optionally shows a summary ("You guessed 2/3 correctly today").

Widget refreshes when:
- A friend submits a drawing (FCM push triggers widget update).
- The player submits their own drawing.
- Midnight daily reset fires.

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Mobile framework | **Flutter (Dart)** | Single codebase for Android + iOS; CustomPainter for drawing canvas |
| Backend / DB | **Firebase Firestore** | Real-time listeners, security rules for anti-cheat |
| Auth | **Firebase Auth** | Google Sign-In (simple, no passwords) |
| File storage | **Firebase Storage** | Stores submitted drawing images |
| Notifications | **Firebase Cloud Messaging (FCM)** | Alert friends when it's their turn to guess |
| Scheduled jobs | **Firebase Cloud Functions** | Daily word rotation at midnight |
| Home screen widget | **`home_widget` Flutter package** | Renders native Android/iOS widgets from Flutter data |

---

## Firestore Data Model

### `users/{userId}`
```json
{
  "displayName": "Arvin",
  "photoUrl": "https://...",
  "fcmToken": "...",
  "friendIds": ["uid2", "uid3"],
  "streakCount": 7,
  "lastPlayedDate": "2026-05-25"
}
```

### `daily/{YYYY-MM-DD}`
```json
{
  "wordChoices": ["bicycle", "volcano", "saxophone"],
  "generatedAt": "<timestamp>"
}
```

### `rounds/{YYYY-MM-DD}/players/{userId}`
```json
{
  "chosenWord": "bicycle",
  "drawingUrl": "gs://bucket/rounds/2026-05-25/uid1.png",
  "submittedAt": "<timestamp>",
  "hasSubmittedDrawing": true
}
```

### `rounds/{YYYY-MM-DD}/guesses/{guesserId_drawerId}`
```json
{
  "guesserId": "uid1",
  "drawerId": "uid2",
  "attempts": ["train", "scooter", "bicycle"],
  "correct": true,
  "solvedOnAttempt": 3,
  "completedAt": "<timestamp>"
}
```

**Document ID pattern for guesses:** `{guesserId}_{drawerId}` — makes it easy to query "all guesses by user X" or "all guesses on user Y's drawing."

---

## Firestore Security Rules (Core Logic)

```
// Player can only read another player's drawing if their own drawing is submitted
match /rounds/{date}/players/{drawerId} {
  allow read: if request.auth != null
    && exists(/databases/$(database)/documents/rounds/$(date)/players/$(request.auth.uid))
    && get(/databases/$(database)/documents/rounds/$(date)/players/$(request.auth.uid)).data.hasSubmittedDrawing == true;

  allow write: if request.auth.uid == drawerId;
}
```

---

## Key Features — MVP Scope

### Must Have (v1.0)
- [ ] Google Sign-In authentication
- [ ] Friend system (add friends by sharing a short invite link/code)
- [ ] Daily word selection (3 choices, pick 1)
- [ ] Drawing canvas (finger drawing, color picker, brush size, undo)
- [ ] Drawing submission (converts canvas to PNG, uploads to Firebase Storage)
- [ ] Anti-cheat enforcement (must draw before you can guess)
- [ ] Free-text guessing with 3 attempts per friend's drawing
- [ ] Push notifications when a friend submits their drawing
- [ ] Android home screen widget (all 3 states)
- [ ] Daily reset via Cloud Function
- [ ] Streak counter

### Deferred (post-v1.0)
- Scoring / leaderboard (to be decided later)
- iOS App Store submission
- Word list expansion / user-submitted words
- Animated drawing replay (stroke-by-stroke)
- Group management (multiple friend groups)

---

## Drawing Canvas — Implementation

Use Flutter's `GestureDetector` + `CustomPainter`:

```dart
// Data model for a stroke
class DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
}

// State
List<DrawingStroke> strokes = [];
DrawingStroke? currentStroke;
```

- **GestureDetector** captures `onPanStart`, `onPanUpdate`, `onPanEnd` → appends to `currentStroke.points`.
- **CustomPainter** calls `canvas.drawPath()` for each stroke using `Paint()..strokeCap = StrokeCap.round`.
- **Undo** removes the last stroke from the list.
- **Submit** calls `repaintBoundary.toImage()` → converts to PNG bytes → uploads to Firebase Storage.
- Keep strokes in local state only (don't stream to Firestore — submit as final image).

Controls to include: color palette (6–8 preset colors), brush size slider, undo button, clear button, submit button.

---

## Home Screen Widget — Implementation

Use the [`home_widget`](https://pub.dev/packages/home_widget) package.

**Flow:**
1. On app launch and on Firestore state changes, call `HomeWidget.saveWidgetData<String>('widgetState', jsonEncode(data))`.
2. The native Android widget reads this data via `HomeWidgetProvider` and renders the appropriate state layout.
3. For word selection taps in the widget, use `HomeWidget.setAppGroupId` + deep link intent to route to the canvas screen with the pre-selected word.
4. Register a `HomeWidgetBackgroundCallback` to handle widget tap events that open the app.

**Android setup required:**
- Create `res/layout/pictionary_widget_state1.xml`, `state2.xml`, `state3.xml` layouts.
- Register `AppWidgetProvider` in `AndroidManifest.xml`.
- Add `AppWidgetProviderInfo` metadata XML.

**Widget data payload (JSON saved via home_widget):**
```json
{
  "state": 1,
  "wordChoices": ["bicycle", "volcano", "saxophone"],
  "friendDrawings": [
    { "uid": "uid2", "name": "Sara", "thumbUrl": "https://..." }
  ],
  "streakCount": 7,
  "dayCount": 42
}
```

---

## Daily Word System — Cloud Function

```typescript
// functions/src/dailyReset.ts
export const dailyWordReset = functions.scheduler
  .onSchedule('0 0 * * *', async () => {
    const wordList = await getWordList(); // fetch from Firestore or bundled JSON
    const shuffled = wordList.sort(() => Math.random() - 0.5);
    const chosen = shuffled.slice(0, 3);

    await admin.firestore()
      .doc(`daily/${todayString()}`)
      .set({ wordChoices: chosen, generatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
```

- Word list stored in `wordList/master` Firestore doc (array of strings), or bundled as `assets/words.json` for offline fallback.
- Timezone: **UTC midnight** for the initial version (can be made user-local later).
- Cloud Function also clears old round data (rounds older than 7 days) to manage storage costs.

---

## Friend System

- Each user gets a **short invite code** (6-character alphanumeric, stored on their `users/{uid}` doc).
- To add a friend: enter their code → Firestore Cloud Function validates and adds each user to the other's `friendIds` array.
- Friends see each other's drawings automatically on any shared day they both participate.
- **No group concept in v1** — it's a flat friend list. Everyone in your friend list is in your "group."

---

## Push Notifications

Trigger FCM notifications in these cases:
1. Friend submits a drawing → notify all friends: "Sara submitted her drawing! Can you guess what it is?"
2. Friend correctly guesses your drawing → notify drawer: "Arvin guessed your drawing!"
3. Daily reset (midnight) → notify all users: "Today's words are ready. Start drawing!"

Use Firebase Cloud Functions triggered on Firestore writes to send FCM messages.

---

## Project Structure

```
pictionary_app/
├── android/
│   └── app/src/main/
│       ├── res/layout/         # Widget XML layouts (state1, state2, state3)
│       ├── res/xml/            # AppWidgetProviderInfo
│       └── AndroidManifest.xml
├── ios/
├── lib/
│   ├── main.dart
│   ├── app.dart               # MaterialApp + routing
│   ├── core/
│   │   ├── auth/              # Firebase Auth service
│   │   ├── firebase/          # Firestore + Storage services
│   │   └── notifications/     # FCM setup
│   ├── features/
│   │   ├── word_selection/    # Daily word picker screen
│   │   ├── canvas/            # Drawing canvas screen
│   │   ├── feed/              # Friends' drawings feed
│   │   ├── guessing/          # Guess input screen
│   │   ├── results/           # End-of-day results
│   │   ├── friends/           # Friend list + invite flow
│   │   └── profile/           # User profile + streak
│   ├── models/                # Dart data classes (User, Round, Guess, etc.)
│   ├── services/
│   │   ├── firestore_service.dart
│   │   ├── storage_service.dart
│   │   └── widget_service.dart  # home_widget data sync
│   └── widgets/               # Shared UI components
├── functions/
│   └── src/
│       ├── dailyReset.ts
│       ├── sendNotification.ts
│       └── friendInvite.ts
├── pubspec.yaml
└── CLAUDE.md                  # This file
```

---

## Development Phases

### Phase 1 — Foundation (Week 1–2)
- [ ] Flutter project setup with Firebase
- [ ] Google Sign-In auth flow
- [ ] Firestore data model + security rules
- [ ] Basic navigation skeleton (all screens stubbed out)
- [ ] Cloud Function: daily word reset

### Phase 2 — Core Game (Week 3–4)
- [ ] Word selection screen (reads from `daily/{date}`)
- [ ] Drawing canvas (full feature: draw, color, undo, submit)
- [ ] Drawing upload to Firebase Storage
- [ ] Friends' feed screen (shows submitted drawings, anti-cheat gate)
- [ ] Guessing screen (3 attempts, free-text)

### Phase 3 — Social & Notifications (Week 5)
- [ ] Friend invite system (code-based)
- [ ] FCM push notifications (all 3 trigger cases)
- [ ] Streak counter logic

### Phase 4 — Home Screen Widget (Week 6)
- [ ] Android widget setup (AppWidgetProvider, layouts)
- [ ] `home_widget` package integration
- [ ] All 3 widget states rendering correctly
- [ ] Deep links from widget taps into correct app screens
- [ ] Widget refresh on FCM events

### Phase 5 — Polish & iOS (Week 7–8)
- [ ] UI polish, animations, empty states
- [ ] Error handling and offline states
- [ ] iOS build + TestFlight setup
- [ ] APNs key upload to Firebase for iOS push notifications
- [ ] End-to-end testing with real devices

---

## Setup Instructions for Development

### Prerequisites
- Flutter SDK (stable channel)
- Android Studio + Android SDK
- Firebase CLI (`npm install -g firebase-tools`)
- Node.js 18+ (for Cloud Functions)
- Samsung Android device (or emulator) in developer mode

### Firebase Setup
1. Create a Firebase project at console.firebase.google.com
2. Enable: Firestore, Storage, Auth (Google provider), Functions, Cloud Messaging
3. Download `google-services.json` → place in `android/app/`
4. Download `GoogleService-Info.plist` → place in `ios/Runner/` (when doing iOS)
5. Deploy security rules: `firebase deploy --only firestore:rules`
6. Deploy Cloud Functions: `cd functions && npm install && firebase deploy --only functions`

### Run on Android
```bash
flutter pub get
flutter run  # with Samsung connected via USB
```

### Key Packages (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.0.0
  firebase_auth: ^5.0.0
  cloud_firestore: ^5.0.0
  firebase_storage: ^12.0.0
  firebase_messaging: ^15.0.0
  home_widget: ^0.7.0
  go_router: ^14.0.0
  riverpod: ^2.0.0          # state management
  flutter_riverpod: ^2.0.0
  cached_network_image: ^3.0.0
```

---

## Open Questions / Decisions for Later

- **Scoring system**: Decided to skip for MVP. Consider: points for correct guesses, bonus for guessing on fewer attempts, weekly leaderboard among friends.
- **Word difficulty**: Should the 3 daily word choices vary in difficulty (easy / medium / hard)?
- **Timezone for daily reset**: Currently UTC midnight. May want to switch to user's local midnight.
- **Drawing time limit**: Should there be a time cap on how long you can spend drawing?
- **Word reveal**: When exactly is the chosen word revealed to friends who guessed incorrectly? (End of day, or after all attempts are used?)
- **Multiple friend groups**: v1 has a flat friend list. Groups could be added later.
