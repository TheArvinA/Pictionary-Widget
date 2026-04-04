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
