# Process Review

A running log of the multi-agent / workflow work on this project. **Updated whenever a large amount of work is done, or multiple workflows/subagents are used.** Each entry records, per task: the workflow/agents used, the phases, what each agent did, and the outcome (verdict, files changed, gate results).

Newest entries first.

---

## 2026-06-23 — Widget UX fixes + full codebase audit + follow-up fixes

**Trigger:** on-device feedback (3 widget issues) + a request for a full codebase rundown with fixes, docs, and this process log.

### Plan
1. **`widget-ux-fixes`** workflow — (a) widget word tap opens Home instead of the canvas; (b) empty/blank widget when you've drawn but no friend has; (c) friend-drawing preview is cropped (should preserve the square-ish canvas aspect); plus (d) a related data bug: drawing via the widget deep-link skips `chooseWord`, so the owner-only secret word is never written (guessing that drawing would fail).
2. **`codebase-audit`** workflow — read-only rundown of the whole codebase for dead/redundant code, bugs, missing edge cases, and oversights (excluding the 3 known widget issues, owned by #1). → rewrite `review-findings.md` with findings + a lightweight fix plan each.
3. **Fix workflows** for the confirmed audit findings (TBD from the audit output).
4. Update `handoff.md` + `next_steps.md`; finalize this log.

> ⚠️ **Session-limit interruption (2026-06-23):** a usage limit was hit while these two workflows ran. Implement phases completed; several **verify** agents failed and were dropped. Outcomes below reflect that.

### Workflow: `widget-ux-fixes` (run `wf_abbaadb3-3a2`) — ✅ implemented, ⚠️ verify lost to limit
**Phases:** Implement (1 native+Dart agent) → Verify (failed: session limit).
**Implement agent did:** fixed 4 coupled widget issues —
1. **Word tap → Home (not canvas).** Root cause = cold-start race: `app.dart` replayed the widget deep-link only via `ref.listen` on the auth provider, which can miss the `loading→data` transition if auth restores before the listener registers → link dropped → app stays Home. Fix: `_openFromWidget` now also actively awaits `authStateChanges().firstWhere(non-null).timeout(8s)` then replays (clear-before-navigate, so it fires once whichever path wins). Warm path (MainActivity `onNewIntent`) confirmed sound.
2. **Secret word never written via widget path (data bug).** Drawing via the widget deep-link bypassed `word_selection`'s `chooseWord`, so `private/round.chosenWord` was never written (later guessing failed). Fix: `canvas_screen._submit` now calls `chooseWord(date, uid, widget.word)` (guarded, idempotent merge) before upload.
3. **Blank State 2 when no friend has drawn.** Added a `state2_empty` "Waiting for friends to draw…" view; provider shows it + hides the grid rows when `submitted.isEmpty()`.
4. **Cropped drawing preview.** Changed the 6 thumbnail `ImageView`s from `centerCrop` → `fitCenter` (whole square image shows, no distortion); P5 async loader unchanged.
**Files (5):** `lib/app.dart`, `lib/features/canvas/canvas_screen.dart`, `android/.../PictionaryWidgetProvider.kt`, `res/layout/pictionary_widget_state2.xml`, `res/values/widget_strings.xml`.
**Gate:** impl agent's `flutter analyze` clean; **lead re-ran full `flutter analyze` → clean (the dedicated verify agent never ran).** Native = inspection-only; **device build still required.**
**Status:** applied to working tree, **uncommitted**. Outstanding: real verify pass (or device test), then commit.

### Workflow: `codebase-audit` (run `wf_56f39970-ca1`) — ⚠️ partial (verify agents lost to limit)
**Phases:** Review (4 parallel dimension reviewers: flutter-correctness, backend-rules, dead-redundant, edge-cases-oversight) → Verify (pipelined per-finding adversarial check). ~11 verify agents failed on the session limit and were dropped.
**Outcome:** 30 findings reached a verdict; **9 confirmed** worth acting on (all **low** severity — no high/critical). Confirmed: (1) sign-out leaves stale FCM token + daily topic sub; (2) `ensureMyWords` re-shuffles when pool <3 words; (3) **[DO]** `friendNamesProvider` all-or-nothing emit → one slow doc shows all UIDs; (4) canvas `pixelRatio:3` PNG OOM risk; (5) `users` docs world-readable (fcmToken/inviteCode); (6) `dailyReset` `set()` reshuffles on re-run; (7) `addFriendByCode` `batch.update` throws if a doc is missing; (8) `dailyReset` push fires on duplicate write; (9) `friendNamesProvider` 52-line fan-in duplicates the per-uid provider — delete.
**Status:** `review-findings.md` rewritten ✅ (see below). Dropped-verify findings re-surfacable by re-running the audit.

### Continuation (2026-06-24, after limit reset)
- **Widget fixes self-reviewed + committed** (`eb1e4e7` on branch `fix/widget-ux-and-audit`). Lead read all 5 diffs (replacing the lost verify agent): robust auth-restore replay, empty-state toggle, `chooseWord`-on-submit, `fitCenter` — all consistent; full `flutter analyze` clean. Native still inspection-only → device test.
- **`review-findings.md` rewritten** from the 9 confirmed findings (full fix plans + per-finding disposition) + the 11 unverified labels (honest about the partial audit).
- **Workflow `fix-audit-findings`** (run `wf_cccb96e9-3f2`) launched — applies the low-risk confirmed findings:
  - Flutter agent: #1 FCM sign-out cleanup (`FcmService.unregister`), #2 `ensureMyWords` guard relax (`length==3` → `isNotEmpty`), #3+#9 delete the `friendNamesProvider` fan-in → shared per-uid `userDisplayNameProvider` in feed + word_selection, #4 canvas `pixelRatio` 3→2.
  - Backend agent: #6+#8 `dailyReset` create-once guard (no reshuffle/duplicate push on re-run), #7 `addFriendByCode` `batch.update`→`set merge`.
  - **#5 (tighten `users` read rule) DEFERRED** — risks breaking friend/guesser name resolution; needs a deploy + careful device test; low severity.
  - **Outcome: ✅ ship.** Verify agent confirmed all 6 fixes + flutter analyze + tsc clean, no regressions. Lead re-ran the combined gate (analyze + tsc clean). Files: `fcm_service.dart`, `app.dart`, `firestore_service.dart`, `providers.dart`, `feed_screen.dart`, `word_selection_screen.dart`, `canvas_screen.dart`, `dailyReset.ts`, `friendInvite.ts`. **Committed `335118b`.** Backend changes need `firebase deploy --only functions`.

### Workflow: `codebase-audit` (RESUMED, run `wf_56f39970-ca1`)
Resumed the interrupted audit to recover the findings whose verify agents were dropped to the session limit. Reviewers cached; the dropped verify agents re-ran (completed in ~45s). **Outcome: 11 confirmed** (up from 9). Caveat: the resume **cached the verify verdicts from before commit `335118b`**, so 7 of the 11 *show* as open but are already fixed. After cross-referencing against the applied fixes:
- ✅ **7 already fixed** (`335118b`): FCM sign-out, ensureMyWords, friendNamesProvider, pixelRatio, dailyReset create-once, addFriendByCode, dailyReset push.
- ⏸️ **1 deferred:** #5 tighten `users` read rule.
- 🆕 **3 genuinely new/open** (recovered): (a) model fields parsed-but-never-read (dead code, lightweight delete); (b) streak never decremented on a missed day → stale inflated streak (heavier — defer); (c) cold-start from the widget into `/guess`/`/results` strands the user (no back/nav — moderate, recommend fixing).
`review-findings.md` regenerated to this current status. **The 3 open findings are NOT yet fixed** — teed up for the user to action.

### Session summary (2026-06-23 → 06-24)
3 workflows + 1 lead-driven recovery. Branch `fix/widget-ux-and-audit`: `eb1e4e7` (widget UX fixes) + `335118b` (audit fixes). `handoff.md` / `next_steps.md` updated; `review-findings.md` rewritten (gitignored, local). Outstanding: device-test the native widget changes, `firebase deploy --only functions` for the backend fixes, then merge the branch to `main`. Deferred: audit #5 (rules), the ~11 dropped audit findings (re-run the audit to recover).
