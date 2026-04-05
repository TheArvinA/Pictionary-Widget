PICTIONARY WIDGET
=================
A mobile app that lets you play Pictionary with friends, once a day.

CONCEPT
-------
- Each day, players are presented with 3 words to choose from
- You pick one word and draw it on your phone
- Friends must submit their own drawing before they can see yours and guess
- Everyone guesses each other's drawings
- Resets the next day with new words


PROJECT OUTLINE
---------------

1. CORE FEATURES (MVP)
   - Daily word selection (3 choices per day, shared across all users)
   - Drawing canvas (finger-drawn, color picker, brush size)
   - Submit drawing to lock it in
   - View friends' drawings only after submitting your own
   - Guess what friends drew
   - Push notification when it's your turn to guess

2. USER SYSTEM
   - Account creation via Firebase Auth (Google sign-in)
   - Friend system using unique user codes or usernames
   - User profile (display name, avatar)

3. GAME LOOP
   - Daily reset at midnight via Firebase Cloud Function
   - 3 random words selected and written to Firestore "daily" document
   - Each player picks their word (stored privately)
   - Player draws and submits (image uploaded to Firebase Storage)
   - hasSubmittedDrawing flag unlocks guessing view
   - Guesses submitted and shown after round ends or time expires

4. BACKEND
   - Firebase Auth (authentication)
   - Firestore (game state, user data, friend relationships, daily words)
   - Firebase Storage (drawing images)
   - Firebase Cloud Messaging (push notifications)
   - Firebase Cloud Functions (daily word rotation, scheduled reset)

5. PLATFORMS
   - Phase 1: Android (Samsung test device via USB / APK sideload)
   - Phase 2: iOS (requires Mac + Xcode, distribute via TestFlight)


INITIAL SETUP — WHAT TO DOWNLOAD
---------------------------------
Everything below assumes a fresh Windows machine with nothing installed.

STEP 1 — Git
  Download: https://git-scm.com/download/win
  Install with defaults. Required for version control and pushing to GitHub.

STEP 2 — GitHub CLI (gh)
  Download: https://cli.github.com
  Or via terminal: winget install --id GitHub.cli
  After installing, run: gh auth login
  Required to create/manage GitHub repos from the terminal.

STEP 3 — Flutter SDK
  Download: https://docs.flutter.dev/get-started/install/windows
  - Download the Flutter ZIP, extract it (e.g. to C:\flutter)
  - Add C:\flutter\bin to your system PATH
  - Run: flutter doctor   (shows what else is missing)
  Includes Dart — no separate Dart install needed.

STEP 4 — Android Studio
  Download: https://developer.android.com/studio
  Required for:
  - Android SDK and build tools (flutter needs these even if you don't use the IDE)
  - USB debugging / device connection
  After installing, open Android Studio and complete the setup wizard.
  Then run: flutter doctor   again to confirm Android toolchain is green.

STEP 5 — Enable Developer Mode on your Samsung
  On your Samsung: Settings -> About Phone -> tap "Build Number" 7 times
  Then: Settings -> Developer Options -> enable "USB Debugging"
  Connect via USB and run: flutter devices   to confirm it's detected.

STEP 6 — VS Code (recommended editor)
  Download: https://code.visualstudio.com
  Install these extensions inside VS Code:
  - Flutter (by Dart Code) — includes Dart support
  - Dart (by Dart Code)

STEP 7 — Firebase CLI + Node.js (for Cloud Functions)
  Node.js download: https://nodejs.org  (install LTS version)
  Then in terminal:
    npm install -g firebase-tools
    firebase login
  Required for deploying Cloud Functions and Firestore rules.

STEP 8 — Create a Firebase Project
  Go to: https://console.firebase.google.com
  - Create a new project (e.g. "pictionary-widget")
  - Enable: Authentication, Firestore, Storage, Cloud Messaging, Functions
  - Add an Android app, download google-services.json (goes in android/app/)
  - Add an iOS app later when ready for Phase 2

VERIFICATION CHECKLIST
  Run these to confirm everything is working before writing code:
  [ ] git --version
  [ ] gh --version
  [ ] flutter doctor   (all checkmarks green for Android)
  [ ] flutter devices   (your Samsung shows up)
  [ ] firebase --version
  [ ] node --version


TECH STACK
----------
- Framework:  Flutter (Dart) — single codebase for Android + iOS
- Drawing:    Flutter CustomPainter + GestureDetector
- Database:   Cloud Firestore (real-time)
- Storage:    Firebase Storage (drawing images)
- Auth:       Firebase Auth
- Messaging:  Firebase Cloud Messaging (FCM)
- Functions:  Firebase Cloud Functions (Node.js)


DEVELOPMENT PHASES
------------------
Phase 1 - Foundation
  [ ] Set up Flutter project and Firebase
  [ ] Implement Firebase Auth (Google sign-in)
  [ ] Build drawing canvas (CustomPainter)
  [ ] Canvas to image export (toImage -> PNG -> Firebase Storage)

Phase 2 - Game Logic
  [ ] Daily word system (Cloud Function + Firestore)
  [ ] Word selection UI (pick 1 of 3)
  [ ] Drawing submission flow
  [ ] Anti-cheat: gate guessing behind hasSubmittedDrawing flag

Phase 3 - Social
  [ ] Friend system (add by code/username)
  [ ] View friends' drawings after submitting
  [ ] Guess submission and reveal
  [ ] Push notifications (FCM)

Phase 4 - Polish & Deploy
  [ ] UI/UX polish, animations
  [ ] Android release (Play Console internal testing)
  [ ] iOS port (Xcode + TestFlight)
  [ ] App Store / Play Store submissions
