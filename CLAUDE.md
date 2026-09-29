# PlanAlarm — notes for Claude

Personal iOS app (single user, not for the App Store): alarm-grade daily plan reminders built on AlarmKit.
The owner is a beginner on **Windows with no Mac**. Give simple numbered steps whenever they need to act,
and say exactly what to reply afterwards.

## Hard constraints
- **No Mac, no local Xcode or Simulator.** All builds and tests run in GitHub Actions (`macos-26` runner).
  Nothing counts as working until CI is green. Say explicitly what can only be checked on the physical iPhone.
- **Free Apple ID.** CI produces an **unsigned** `PlanAlarm.ipa` artifact; the owner sideloads it with
  Sideloadly on Windows (re-signs with the free Apple ID, expires after 7 days, reinstalled weekly).
- Keep a later switch to a paid account + TestFlight small: signing settings plus one extra CI job.
- **Bundle ID `com.habashi.planalarm` never changes** (reinstalling over it keeps the app's data).
- iOS 26.0 deployment target. Swift 6, SwiftUI, AlarmKit, App Intents, SwiftData, UserNotifications (only for soft follow-ups).
- Time zone: always use the device's local `TimeZone`/`Calendar` (owner is in Africa/Cairo, which has DST). Never hard-code offsets.
- **Ask the owner first** before adding: app extensions (each uses a free-account App ID), entitlements,
  App Groups, third-party dependencies. Currently: none of these.
- **Never change the `.dayplan` schema without asking the owner.** Schema docs live in `docs/PLAN_FORMAT.md`.
- Read Apple's current AlarmKit docs before writing AlarmKit code; don't guess API signatures.

## Project layout
- `project.yml` — XcodeGen spec (source of truth). The `.xcodeproj` is generated in CI and git-ignored.
- `PlanAlarm/Info.plist` — extra Info.plist keys merged with the `INFOPLIST_KEY_*` build settings.
- `PlanAlarm/App/` — app entry point and root tab view.
- `PlanAlarm/Features/<Screen>/` — one folder per screen (Today, Plan, History, Settings, …).
- `PlanAlarm/PlanFormat/` — `LocalDate`/`TimeOfDay`/`Weekday`, `Plan` models, `PlanParser` + `PlanValidator`
  (JSON → located, human-readable errors), `DayResolution` (template + overrides), `UTType.dayplan`.
- `PlanAlarm/Scheduling/` — **all AlarmKit code** (`@preconcurrency import AlarmKit` only here):
  `AlarmService` (the single service: permission, wake-up alarms, task alarms, re-arming, debug tools),
  `AlarmIntents` (LiveActivityIntents for the alarm buttons), `WakeSchedule` (pure logic),
  `AlarmRegistry` (which AlarmKit alarm IDs belong to what; UserDefaults, since AlarmKit doesn't expose metadata).
- `PlanAlarm/App/AppRouter.swift` — `presentedTaskKey`: a task pending acknowledgement is shown full screen.
- `PlanAlarm/Persistence/AppDatabase.swift` — the one `ModelContainer`, shared with App Intents.
  `AppSettings` (SwiftData, single record): wake-up schedule, snooze length.
- `PlanAlarm/Persistence/` — SwiftData: `StoredPlan` (raw JSON + metadata; one active, the rest archived,
  never deleted), `PlanStore` (activate + parsed-plan cache).
- `PlanAlarm/Features/Import/` — `ImportController` (Open in / Files / paste / sample / new plan → sheets).
- `PlanAlarm/Features/PlanEditing/` — `NewPlanView`, `TaskEditorView` (add a task to one date).
- `PlanAlarm/PlanFormat/PlanEditing.swift` + `PlanEncoder.swift` — in-app edits stored as ordinary
  weeklyTemplate entries / dateOverrides, then re-encoded to schema-v1 JSON. Scopes: `.thisDate` or
  `.everyWeek` (add / edit / delete a task), plus clear day and reset day (remove the date's override).
  A date with its own "replace" override keeps its tasks when the weekly pattern changes (except
  "add every week" started from that date, which also appends there). `PlanStore.update` re-parses
  before saving, so an unreadable plan is never stored.
- `PlanAlarm/Features/TaskDetail/` — `TaskContentView`, the large-type task view (reuse for read-to-dismiss).
- `PlanAlarm/Resources/` — asset catalog.
- `Samples/sample-october.dayplan` — sample plan; bundled into the app via `project.yml` (single copy).
- `docs/PLAN_FORMAT.md` — schema v1 documentation (written for AIs generating plans).
- `Tests/PlanAlarmTests/` — Swift Testing unit tests (run on a simulator in CI). `SamplePlanTests` reads the
  repo sample via `#filePath`.

## Conventions
- Plan dates are `LocalDate` (pure Gregorian day math). Convert to/from `Date` only via `Calendar.plan`
  (Gregorian, device time zone), so a phone set to another calendar or a DST day doesn't shift dates.
- Plan interpretation decisions (documented in `docs/PLAN_FORMAT.md`): library entries must be complete tasks;
  `replace` overrides drop the template's dayNote when they don't give one; `description.summary` and
  `description.sections` override library values separately; unknown weekday keys are errors (typo guard);
  `null` = missing; curly quotes in pasted text are repaired with a warning.
- AlarmKit facts (checked against Apple's docs, Sep 2026):
  - `AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)` is iOS 26.1+. The `stopButton:`
    initializer is deprecated in 26.1 ("will no longer be used"): iOS draws its own Stop button. We use
    `#available(iOS 26.1, *)` and fall back to the stop-label initializer on 26.0 ("Snooze N min").
  - A widget extension is required only for countdown presentations. We use alert-only alarms and never
    `secondaryButtonBehavior: .countdown`, so **no extension**.
  - Apple's AlarmKit FAQ (developer.apple.com/forums/thread/797158): **every physical button stops** the
    alerting alarm(s); slide-to-stop can't be removed. The stop intent is *supposed* to run on any dismissal,
    but developers report it often doesn't (and on-device testing confirmed Stop didn't re-arm in build 11).
  - `AlarmManager.alarms` is `get throws`; `Alarm` has no metadata, hence `AlarmRegistry`.
  - Button intents must be `LiveActivityIntent`; they run in the app process. "Open" intents use
    `supportedModes = .foreground(.immediate)`. `perform()` is nonisolated → hop via `AlarmService.handle…`.
  - Info.plist needs `NSAlarmKitUsageDescription` (non-empty) or scheduling fails.
  - Custom sounds: `AlertSound.named("file")` must be in the **app bundle** (Library/Sounds reportedly
    doesn't play), **< 30 s**, and may play once per ring instead of looping. Tones: `Resources/Sounds/tone-*.wav`
    (generated in-house, no third-party audio); `AlarmTone` enum; `.system` = `.default` (loops).
- Task alarm design: each task gets a **chain of rings scheduled in advance** (one per snooze interval,
  covering ~1 h, 3–12 rings; `AlarmRegistry.chainLength`), so however a ring is stopped the next one follows.
  When `SnoozeTaskIntent` does run, the chain is re-timed from now + snooze. "Open task" stops the ring,
  re-times, and opens the app. Only **Stop Alarm** in the app (after the unlock countdown: Settings
  `stopUnlockSeconds`, default 30 s; a task's own readSeconds wins; runs only while in the foreground)
  cancels the chain. `AlarmService.refresh()` (app active): cancels AlarmKit alarms not in the registry,
  restores wake alarms, restarts chains that ran out.
- `ExtraTask` (SwiftData): tasks the user adds on dates outside the plan or with no plan. Kept outside the
  plan file (no schema change), so they survive plan replacement but aren't in shared `.dayplan` files.
  `DayAgenda` = plan day tasks followed by that date's extras; later phases must schedule from `DayAgenda`.
- Days: `DayRecord` (a locked-in date) + `TaskRecord` (one per task per day: snapshot of the task, chosen
  time, `TaskStatus` scheduled → ringing → inProgress → done | skipped, or unlogged; timestamps; snooze count).
  `DayStore` reads/writes them. A task's alarm-chain key is `TaskRecord.alarmKey` (its UUID string).
- Morning check-in (`Features/CheckIn`): `CheckInPlanner` holds the rules (passed times → now + 15 min rounded
  up to 5 min; overlap warnings by duration; blocking reasons). Today tab shows `CheckInView` until the date
  has a `DayRecord`, then `TodayTimelineView`. Opening the app switches to Today until locked in.
  Yesterday's unresolved tasks must be answered; older ones become `unlogged` automatically.
  **Unlock Day** (`DayStore.unlock`): deletes the `DayRecord` and every record not resolved during the day
  (done, or skipped after check-in), cancels their alarms; the check-in then leaves out already-finished titles.
  Live plan updates: `CheckInPlanner.signature(of:)` detects changes; the check-in rebuilds with
  `CheckInPlanner.merge` (keeps chosen times/skips by title); a locked-in day runs `DayStore.sync`
  (adds new tasks at their time or "Needs a time", removes open tasks gone from the day, keeps finished ones).
  Timeline: Undo/Unskip/Reopen (`DayStore.undo`), New Time (`DayStore.reschedule`) for ringing,
  in-progress or overdue tasks. "Needs a time" = scheduled, time nil or past, and no alarm chain.
- Check-in reminder: `AlarmService.updateCheckInReminders()` keeps 4 rings (every `checkInReminderMinutes`
  after that day's wake time) for today and tomorrow while not locked in; `registry.checkInChains`.
- `AlarmRegistry` decodes missing fields as empty (custom `init(from:)`): **add new fields there too**, or a
  missing key would wipe the registry and the orphan clean-up would cancel every alarm.
- Swift 6 gotcha: don't build `Binding(get:set:)` from a stored callback property (Sendable warning); marking
  the callback `@MainActor` crashed the Swift 6.2 compiler in Xcode 26.6. Use local `@State` + `.onChange`.
- Plans can be deleted (active or archived). So history (phases 5–6) must **snapshot** task data
  (title, category, times) in its own records and must never depend on a `StoredPlan` still existing.

## CI (`.github/workflows/build.yml`)
Runs on push to `main`, on `v*` tags, and on manual dispatch; skips doc-only changes (`**.md`, `docs/**`).
Steps: select Xcode (pinned by `XCODE_VERSION`, fails clearly if missing) → install XcodeGen (cached) →
`xcodegen generate` → `xcodebuild test` on an iOS 26 iPhone simulator → unsigned Release archive →
package `Payload/PlanAlarm.app` into `PlanAlarm.ipa` → upload artifact (and attach to a Release on tags).
`CURRENT_PROJECT_VERSION` is set to the GitHub run number.

On this Windows machine `gh` may not be on PATH in the agent shell; use `"C:\Program Files\GitHub CLI\gh.exe"`.
- Trigger: `gh workflow run build.yml --ref main`
- Watch: `gh run watch <run-id> --exit-status` (list with `gh run list --workflow build.yml`)
- Failure logs: `gh run view <run-id> --log-failed`
- Download IPA: `gh run download <run-id> -n PlanAlarm-build-<run-number>`

## Phased workflow
After each phase: commit, push, get a green CI run, then summarise what works and what to test on the phone.
1. **Skeleton + CI** — XcodeGen project, four empty tabs, unsigned IPA from CI. *(done, sideload confirmed)*
2. **Plan format** — models, parser, validator, day resolution, import (file / Open in / paste), preview, sample plan, `docs/PLAN_FORMAT.md`, tests. *(done in build 7)*
   **2b. Plan editing** (owner request) — add / edit / delete tasks for one date or every week, clear day,
   reset day, new empty plan, delete active/archived plans, share plan as `.dayplan`.
   *(done in build 9)*
3. **AlarmKit core** — permissions, wake-up alarm, one test task alarm with stop-rearms / open-task behaviour,
   hidden debug tools (Settings → tap "Build" 7×). Build 11 tested on the phone: Stop didn't snooze.
   **3b. Owner feedback** — backup-ring chains, Stop Alarm unlock timer, alarm tones, tasks on any day.
   *(done in build 12 — waiting for on-device tests)*
4. **Morning check-in** + scheduling, re-alarm, passed-time handling, Today timeline.
   *(done in build 15; Unlock Day in 16; undo, new time and live plan updates in 17 — waiting for on-device tests)*
5. Read-to-dismiss, statuses, follow-up notifications.
6. History and streaks (+ edge-case tests: rest days, skips, plan changes, DST).
7. Expiry protection, onboarding, settings polish, README.
