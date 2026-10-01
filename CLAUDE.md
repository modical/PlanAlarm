# PlanAlarm — project guide for Claude

A personal iPhone app (one user, not for the App Store) that turns a daily plan (gym, stretches, study…)
into reminders that ring like real alarms (AlarmKit): through silent mode and Focus, again and again,
until the user opens the app and reads the task. Repo: https://github.com/modical/PlanAlarm (public).

Read this whole file before changing anything. Keep it up to date when behaviour or structure changes.

---

## 1. The owner and how to work with them

- **Beginner, on Windows, no Mac.** Explain in plain words. Whenever they must do something (install,
  tap through iPhone settings, test on the phone), give **short numbered steps** and end with
  **exactly what to reply** (a fill-in list works well).
- Lives in **Egypt (Africa/Cairo, has DST)**, phone language English, **iPhone 16 Pro Max (440 pt wide)**,
  iOS 26.x. Tests by sideloading on that phone.
- **Tell them whenever the conversation has been compacted/summarized** (they asked explicitly).
- **Ask first** before: app extensions, entitlements, App Groups, third-party dependencies, or **any change
  to the `.dayplan` schema**. Today the project has none of the first four.
- Show results honestly: nothing is "working" until CI is green, and say clearly what can only be verified
  on the physical iPhone (alarms ringing, notifications, Sideloadly installs).
- They like concrete before/after explanations of bugs, and being asked when a rule is ambiguous
  (use the question tool with clear options).

## 2. Current status (Oct 2026)

- **v1.0 released** (tag `v1.0`, GitHub Release with `PlanAlarm.ipa`).
- `main` is ahead of v1.0 with the **plan-lifecycle changes** (build 28, 143/143 tests green): frozen past
  days, today keeps its lock-in when the plan changes, start-date choice for late plans, "Use This Plan
  Again", recording days without a check-in. Not yet released (owner wants more changes first; when
  ready, release as v1.1).
- **On-device testing is far behind.** Confirmed on the phone: sideload works (build 1), Stop didn't snooze
  (build 11, fixed by backup-ring chains), History crash (build 19, fixed in 23). Everything after build 12
  is **untested on the phone**: backup rings vs slide/side/volume buttons, tones, check-in + reminders,
  read screen + follow-ups, history, expiry reminder, onboarding, plan lifecycle.
- **Owner's future plans** (separate conversation): rebrand / new name, a paid Apple Developer account
  (removes the 7-day expiry; README §11 has the TestFlight job), more user-friendly UX.

## 3. Hard constraints

- **No Mac, no local Xcode, no Simulator.** Every build and test runs in GitHub Actions (`macos-26`
  runner, Xcode **26.6** pinned). You can't compile locally: write carefully, push, read CI logs, fix.
- **Free Apple ID.** CI produces an **unsigned** `PlanAlarm.ipa`; the owner installs it with **Sideloadly**
  on Windows, which re-signs it. Installs **expire after 7 days**; the owner reinstalls weekly over the
  existing app (same Apple ID, don't delete) so data is kept.
- **Bundle ID `com.habashi.planalarm` never changes.** (Sideloadly appends the team ID, e.g.
  `com.habashi.planalarm.J4V38G56NA`; stable as long as the same Apple ID is used.) A rebrand may change
  the *display name* (`INFOPLIST_KEY_CFBundleDisplayName` in `project.yml`) freely, but a new bundle ID
  is a **separate app with no data**: export history first and discuss with the owner.
- iOS **26.0** deployment target; Swift 6 (strict concurrency), SwiftUI, AlarmKit, App Intents, SwiftData,
  UserNotifications (only for the soft "Did you finish?" follow-up). No third-party code.
- **Time:** always the device's time zone via `Calendar.plan`; never hard-code offsets.
- Read Apple's current docs before writing AlarmKit (or other new-API) code; don't guess signatures.
  Apple's doc pages are fetchable as JSON: `https://developer.apple.com/tutorials/data/documentation/<path>.json`.

## 4. Development workflow

1. Edit files on Windows (`E:\user\Documents\PlanAlarm`). Git stores LF line endings (`.gitattributes`).
2. Commit (end messages with the attribution line the harness gives you) and push to `main`.
3. CI (`.github/workflows/build.yml`) runs on push to `main`, on `v*` tags, and manual dispatch. It skips
   doc-only pushes (`**.md`, `docs/**`). Steps: select Xcode → XcodeGen (cached) → `xcodegen generate` →
   `xcodebuild test` on an iOS 26 iPhone simulator (fails if 0 tests ran; failing tests appear as
   annotations) → unsigned Release archive → `PlanAlarm.ipa` artifact `PlanAlarm-build-<run number>` →
   on `v*` tags, a GitHub Release with the IPA. `CURRENT_PROJECT_VERSION` = run number (shown in Settings).
4. `gh` isn't on PATH in the agent shell; use `"/c/Program Files/GitHub CLI/gh.exe"` (Bash) or
   `& "C:\Program Files\GitHub CLI\gh.exe"` (PowerShell), with `-R modical/PlanAlarm`.
   - Latest run: `gh run list -R modical/PlanAlarm --workflow build.yml --limit 1 --json databaseId,number,conclusion`
   - Wait: `gh run watch <id> -R modical/PlanAlarm --exit-status --interval 30`
   - Test counts: `gh run view <id> --log | grep "Test summary" | grep -E '"(totalTestCount|passedTests|failedTests)"'`
   - Failures: `gh run view <id> --log-failed | grep -E "error:"` and the ANNOTATIONS in `gh run view <id>`
   - Warnings: grep the log for `warning:` (keep the app at zero warnings).
5. A build takes ~5–8 min. Give the owner the run URL
   `https://github.com/modical/PlanAlarm/actions/runs/<id>` → Artifacts → `PlanAlarm-build-NN`.
6. **Release:** bump `MARKETING_VERSION` in `project.yml`, push, then `git tag -a vX.Y -m ...` and push the
   tag; CI creates the Release. Replace the auto notes with a plain-language summary
   (`gh release edit vX.Y --notes-file …`). Only release when the owner asks.
7. Crash reports from the phone: iPhone Settings → Privacy & Security → Analytics & Improvements →
   Analytics Data → `PlanAlarm-…ips` → Share. Reproduce in `ScreenSmokeTests` before fixing.

## 5. Architecture

```
PlanAlarm/
  App/            PlanAlarmApp (+AppDelegate: notification delegate), RootView (tabs, sheets, read-screen
                  cover, onboarding cover, app-activation sequence), AppRouter, AppExpiry
  PlanFormat/     LocalDate/TimeOfDay/Weekday + Calendar.plan, Plan models, JSONValue, PlanParser +
                  PlanValidator, DayResolution, PlanEditing (edits, continuing/restarting/shifted),
                  PlanEncoder, UTType.dayplan
  Persistence/    AppDatabase (the one ModelContainer), StoredPlan + PlanStore, AppSettings, ExtraTask +
                  DayAgenda, DayRecords (DayRecord, TaskRecord, TaskStatus, DayStore), HistoryExport,
                  DayPlanFile (share a plan)
  Scheduling/     ALL AlarmKit code: AlarmService, AlarmIntents, AlarmRegistry, WakeSchedule, AlarmTone
  Notifications/  FollowUpService + NotificationDelegate
  Features/       CheckIn, Today, TaskAlarm (read screen), TaskDetail, Plan, PlanEditing, Import,
                  History, Settings, Onboarding, Shared (TaskActions, banners, Formatting)
  Resources/      Assets (icon), Sounds/tone-*.wav (generated in-house)
Samples/sample-october.dayplan   bundled into the app via project.yml (single copy)
docs/PLAN_FORMAT.md              the .dayplan schema v1, written for AIs that generate plans
Tests/PlanAlarmTests/            Swift Testing, hosted in the app, run in CI
project.yml                      XcodeGen spec (source of truth; .xcodeproj is generated, git-ignored)
PlanAlarm/Info.plist             extra keys (UTType export, document types, NSAlarmKitUsageDescription…)
```

**Data model (SwiftData, one container):**
- `StoredPlan` — imported/created plans as raw JSON + metadata; exactly one `isActive`, others archived.
  `PlanStore.plan(for:)` parses (cached by JSON). `PlanStore.update` re-encodes and re-parses before saving.
- `ExtraTask` — tasks added in the app on dates outside the plan / with no plan (not in the plan file).
- `DayAgenda` — a date's plan tasks followed by its extras. `DayAgenda.current(on:)` reads the database.
- `DayRecord` — a recorded day: `checkedIn` (false = recorded afterwards), `planKey` (plan it was locked in
  with), dayNote, planName, lockedInAt. `TaskRecord` — one task on one day: snapshot of the task (JSON),
  title/category, `TaskStatus` (scheduled → ringing → inProgress → done | skipped, or unlogged), chosen time,
  timestamps, snooze count, `alarmKey` (= its UUID string). **History and past days come only from these.**
- `AppSettings` (single record): wake schedule (enabled, time, per-weekday rules), snooze minutes,
  stopUnlockSeconds (read time), task/wake tones, check-in reminder (on, minutes), follow-up on.
- `AlarmRegistry` (UserDefaults, not SwiftData): which AlarmKit alarm IDs belong to what (task ring chains,
  wake alarms, check-in chains, expiry reminder, test alarms). AlarmKit exposes no metadata.

**One door for task changes:** every task state change goes through `TaskActions` (Features/Shared), which
keeps `TaskRecord`s, alarm chains (AlarmService) and follow-ups (FollowUpService) in step.

**App activation sequence (RootView):** `DayStore.recordDaysWithoutCheckIn` → switch to Today if not locked
in → `TaskActions.reconcile()` → `AlarmService.refresh()` (orphan clean-up, wake alarms, chains that ran out,
check-in + expiry reminders) → mark ringing tasks → show a waiting task's read screen. A 15-s loop also
catches alarms going off while open and the date changing at midnight. Going to the background refreshes
the check-in reminders.

## 6. Behaviour rules (decided with the owner — keep them)

**Plan format** (`docs/PLAN_FORMAT.md`; schema changes need the owner's OK)
- Library entries must be complete tasks; `replace` overrides drop the template dayNote unless they give
  one; `description.summary`/`sections` override library values separately; unknown weekday keys are errors;
  `null` = missing; unknown fields ignored; curly quotes in pasted text repaired with a warning.
- In-app edits (one date or every week, clear/reset day) are written back as ordinary weeklyTemplate
  entries / dateOverrides. A date with its own "replace" override keeps its tasks when the weekly pattern
  changes (except "add every week" started from that date).
- The bundled sample is moved by whole weeks to cover today when loaded (`Plan.movedToCover`).

**Plan lifecycle**
- **Past days never change** when plans are loaded, edited, replaced or deleted. The Plan tab shows recorded
  past days as recorded ("Checked in" / "No check-in"); the **only** change allowed is deleting a task by hand
  (swipe → confirm; Plan tab and History day view; `DayStore.deleteRecord`). Past dates can't be planned.
- Days that pass without a check-in are recorded the next time the app opens, from the plan in effect
  (`recordDaysWithoutCheckIn`): yesterday's tasks stay open (asked in "Did you do these?"), older → unlogged.
- **A locked-in day follows only edits to its own plan** (`DayRecord.follows`); another plan or a deleted
  plan leaves today's tasks and alarms (`DayStore.sync(extrasOnly: true)`); Today explains; Unlock Day switches.
- A plan whose start date has passed: the preview offers **Continue it** (`Plan.continuing(from:)`) or
  **Start from day 1** (`Plan.restarting(on:)`) on today / tomorrow / a picked date (`PlanStartChoice`).
- Replacing archives the old plan (never deleted automatically); archived plans have "Use This Plan Again".

**Morning check-in and Today**
- Today shows `CheckInView` until the date has a `DayRecord`, then `TodayTimelineView`. Opening the app
  goes to Today until locked in. Tasks without a time need "Set time" or "Skip today"; passed times move to
  now + 15 min (rounded up to 5 min) and are highlighted; overlaps warn. Yesterday's open tasks must be
  answered first. Lock In re-checks times. Plan changes show up live (`CheckInPlanner.signature` / `merge`).
- Timeline: change a time before it rings (debounced 1 s), New Time for ringing/in-progress/overdue tasks
  (never past midnight), Done / Skip, Undo / Unskip / Reopen, **Unlock Day** (keeps tasks finished during
  the day). Same-plan edits sync into a locked-in day (`DayStore.sync`).
- **Check-in reminder:** 4 rings every `checkInReminderMinutes` after the wake time, today and tomorrow,
  only while not locked in and only on days with something planned.

**Alarms**
- Wake-up: repeating AlarmKit alarms grouped by time per weekday; buttons Stop + Open.
- **Task alarms:** each task gets a **chain of rings scheduled in advance**, one per snooze interval,
  covering ~1 h (3–12 rings), because iOS stops alarms on Stop/slide/physical buttons and the stop intent
  often doesn't run. When the stop intent does run, the chain is re-timed from now + snooze. Rings are
  scheduled **ring by ring across tasks** (all first rings first), so hitting iOS's alarm limit never leaves
  a task with no alarm; times that just passed ring in 5 s.
- Buttons: iOS's own Stop (can't be relabelled on 26.1+; on 26.0 it shows "Snooze N min") + "Open task".
- **Read screen** (`TaskAlarmView`, full screen whenever a task is waiting): whole task in large type,
  countdown (`stopUnlockSeconds`, default 30 s; a task's own readSeconds wins; foreground only), then
  **Starting Now / Reschedule / Skip Today**, each of which stops the chain.
- **Follow-up:** "Did you finish …?" notification at start + duration (or +60 min) with Done/Skipped buttons
  (work with the app closed). Permission is asked the first time it's needed.
- **Reconcile** (every activation): stops chains of earlier days' tasks and of finished/in-progress/deleted
  tasks; restores missing alarms for today's scheduled tasks (TaskRecords are the source of truth).
- Tones: iPhone default (loops) or 5 bundled tones (< 30 s, may play once per ring).

**History**
- Calendar colours: all done / partly / nothing / rest day / today in progress / "No check-in" (missed).
  A day recorded without a check-in with nothing done is "missed"; with no tasks it's a rest day.
- Perfect-day streak: every task done; skipped/unlogged tasks and missed days break it; rest days are
  neutral; today counts only once complete. Category streaks: days the category was scheduled and fully
  done; days without it are ignored. Categories compare case-insensitively. 7/30-day completion excludes
  today's open tasks. Export = JSON (built only when shared).

**Expiry (free Apple ID)**
- `AppExpiry`: ExpirationDate from `embedded.mobileprovision` (plist cut out of the CMS blob), else app
  folder creation date + 7 days. "Reinstall PlanAlarm" alarm at 20:00 the evening before; banner on Today
  under 48 h; shown in Settings → App.

**Onboarding:** first launch only (skipped when plans/history exist); Settings → Show Welcome Screens Again.
Hidden debug tools: tap "Build" in Settings 7 times.

## 7. AlarmKit facts (checked against Apple's docs and forums, Sep 2026)

- `AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)` is iOS 26.1+; the `stopButton:`
  initializer is deprecated in 26.1 ("will no longer be used"). Use `#available(iOS 26.1, *)`.
- A **widget extension is required only for countdown presentations**; we use alert-only alarms and never
  `.countdown`, so there's no extension.
- AlarmKit FAQ (developer.apple.com/forums/thread/797158): every physical button stops alerting alarms;
  slide-to-stop can't be removed; the stop intent should run on dismissal but often doesn't in practice.
- `AlarmManager.alarms` is `get throws`; `Alarm` has no metadata. `NSAlarmKitUsageDescription` must be set.
- Button intents must be `LiveActivityIntent` (run in the app process); "open" intents use
  `supportedModes = .foreground(.immediate)`; `perform()` is nonisolated → hop to `AlarmService.handle…`.
- Custom sounds: `AlertSound.named(file)` from the **app bundle** only (Library/Sounds reportedly doesn't
  play), < 30 s, may not loop.

## 8. Lessons learned / gotchas

- **Never put `LazyVGrid`/`LazyHGrid` inside a `List` row** — UIKit's list layout loops and the app
  crashes (SIGTRAP) on some widths (the build-19 History crash). Use plain stacks.
- `ScreenSmokeTests` opens every tab at six iPhone widths and switches tabs: **add new screens there**.
- Swift 6 / Xcode 26.6: don't build `Binding(get:set:)` from a stored callback property (Sendable warning);
  marking that callback `@MainActor` **crashed the compiler**. Use local `@State` + `.onChange`/`.task(id:)`.
- `AlarmRegistry` has a custom `init(from:)` that defaults missing keys: **add every new field there**,
  or old saved data fails to decode → empty registry → the orphan clean-up cancels every alarm.
- SwiftData model changes: only add properties **with default values** (lightweight migration).
- Swift pitfalls hit before: `let x = x` shadowing a property; a local named like a method used on the line
  before it; destructuring a key/value pair in a `ForEach` closure; `switch await …`; type-checker timeouts
  on long `min(...)`/closure chains (split them); `static let` on a `@MainActor` type used from tests needs
  `nonisolated`.
- Floating-point dates: compare intervals with a tolerance in tests.
- Avoid `rm` of paths outside the repo/scratchpad (a safety check blocks it).

## 9. Tests

Swift Testing in `Tests/PlanAlarmTests/` (hosted in the app; `@MainActor` suites for SwiftData; in-memory
`ModelContainer`s). Pure logic lives in testable types: `PlanValidator`, `DayResolution`, `PlanEditing`,
`CheckInPlanner`, `PlanStartChoice`, `HistoryCalculator`, `WakeSchedule`, `AlarmRegistry`, `AppExpiry`,
`DayStore`. AlarmKit itself can't be exercised in the simulator. Use Cairo's DST days (2026-04-24, 23 h;
2026-10-29, 25 h) for date edge cases. `SamplePlanTests` reads the repo sample via `#filePath`.
