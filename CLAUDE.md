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
- `PlanAlarm/Scheduling/` — all AlarmKit code, behind a single service. *(phase 3)*
- `PlanAlarm/Persistence/` — SwiftData: `StoredPlan` (raw JSON + metadata; one active, the rest archived,
  never deleted), `PlanStore` (activate + parsed-plan cache).
- `PlanAlarm/Features/Import/` — `ImportController` (Open in / Files / paste / sample → preview sheet).
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
2. **Plan format** — models, parser, validator, day resolution, import (file / Open in / paste), preview, sample plan, `docs/PLAN_FORMAT.md`, tests. *(done in build 7 — waiting for the owner to test on the phone)*
3. AlarmKit core — permissions, wake-up alarm, one test task alarm with stop-rearms / open-task behaviour, hidden debug "fire test alarm in 1 minute".
4. Morning check-in + scheduling, re-alarm, passed-time handling.
5. Read-to-dismiss, statuses, follow-up notifications.
6. History and streaks (+ edge-case tests: rest days, skips, plan changes, DST).
7. Expiry protection, onboarding, settings polish, README.
