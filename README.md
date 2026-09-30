# PlanAlarm

A personal iPhone app that turns a daily plan (gym, stretches, study…) into reminders that ring like
real alarms: through silent mode and Focus, again and again, until you open the app and read the task.

Built for one person on **Windows with no Mac**: GitHub builds the app in the cloud, and you install it
with **Sideloadly** using a **free Apple ID**.

**Contents**
1. [Getting the app file (.ipa)](#1-getting-the-app-file-ipa)
2. [Installing with Sideloadly (Windows, free Apple ID)](#2-installing-with-sideloadly-windows-free-apple-id)
3. [The weekly reinstall (free Apple ID)](#3-the-weekly-reinstall-free-apple-id)
4. [First launch](#4-first-launch)
5. [Plans: loading a .dayplan file](#5-plans-loading-a-dayplan-file)
6. [Your day: morning check-in and task alarms](#6-your-day-morning-check-in-and-task-alarms)
7. [History and streaks](#7-history-and-streaks)
8. [Settings](#8-settings)
9. [Known iOS limitations](#9-known-ios-limitations)
10. [Troubleshooting](#10-troubleshooting)
11. [Switching to a paid Apple Developer account / TestFlight](#11-switching-to-a-paid-apple-developer-account--testflight)
12. [For developers](#12-for-developers)

---

## 1. Getting the app file (.ipa)

Every change pushed to `main` is built automatically by GitHub Actions on a Mac in the cloud, with all the
automated tests run on an iPhone simulator first.

1. Open https://github.com/modical/PlanAlarm/actions
2. Click the newest run with a green check mark ✅.
3. Scroll down to **Artifacts** and click **PlanAlarm-build-NN** (NN is the build number). A `.zip` downloads.
4. Unzip it. Inside is **`PlanAlarm.ipa`**: that's the app.

Tagged versions (like `v1.0`) also appear under **Releases** on the repository's main page, with the `.ipa`
attached. Artifacts are kept for 30 days; releases are kept forever.

**Build time:** about 5–8 minutes. The repository is public, so GitHub Actions minutes are free (the macOS
minute limit only applies to private repositories). Changes to documentation only (`*.md`, `docs/`) don't
start a build.

## 2. Installing with Sideloadly (Windows, free Apple ID)

### One-time setup on the PC
1. Install **iTunes** and **iCloud** for Windows from Apple's website (the apple.com versions, *not* the
   Microsoft Store ones). They install the Apple device drivers Windows needs to talk to your iPhone.
2. Install **Sideloadly** from https://sideloadly.io
3. Connect the iPhone with a USB cable. On the iPhone, tap **Trust** and enter your passcode.

### Install the app
1. Open Sideloadly. Your iPhone should appear in the **iDevice** box.
2. Drag `PlanAlarm.ipa` onto the Sideloadly window (or click the IPA icon and pick the file).
3. Type your Apple ID email in the **Apple account** box and click **Start**.
4. Enter your Apple ID password when Sideloadly asks, and the 2-factor code if one appears on your iPhone.
5. Wait for **Done.** at the bottom of Sideloadly.

### First time only, on the iPhone
1. **Turn on Developer Mode:** Settings → Privacy & Security → scroll to the bottom → **Developer Mode** → on.
   The iPhone restarts; afterwards tap **Turn On** and enter your passcode.
   (If Developer Mode isn't listed, install the app once with Sideloadly first, then look again.)
2. **Trust your developer profile:** Settings → General → **VPN & Device Management** → tap your Apple ID
   under *Developer App* → **Trust "…"** → **Trust**.
3. Open **PlanAlarm** from the home screen.

## 3. The weekly reinstall (free Apple ID)

Apps installed with a free Apple ID **stop opening after 7 days**, and their alarms stop with them.
PlanAlarm protects you from forgetting:

- **Settings → App → App expires** shows the exact date and time (read from the signing profile Sideloadly
  puts in the app).
- When less than **48 hours** are left, a red **"Reinstall PlanAlarm soon"** banner appears on **Today**.
- A **"Reinstall PlanAlarm"** alarm rings at **20:00 the evening before** it expires.

**To reinstall:** repeat [Install the app](#install-the-app) with the newest `.ipa` (or the same one).
- **Use the same Apple ID every time**, and **don't delete the app first**: install on top of it. That keeps
  your plans, history and settings.
- Sideloadly adds your Apple team ID to the app's ID (you'll see something like
  `com.habashi.planalarm.J4V38G56NA`). That's normal for free accounts, and it stays the same as long as you
  use the same Apple ID. A different Apple ID would install a *separate* copy with no data.
- Leave Sideloadly's advanced options (bundle ID, etc.) unchanged.
- After reinstalling, open PlanAlarm once: it re-checks its alarms and sets the next reinstall reminder.

## 4. First launch

A short welcome guides you through:
1. What PlanAlarm does.
2. **Allow Alarms**: without this nothing can ring.
3. **Allow Notifications**: for the "Did you finish …?" follow-ups.
4. Your **wake-up time**.
5. Loading a plan (or the sample plan to try things out).

You can see it again any time: **Settings → App → Show Welcome Screens Again**.

## 5. Plans: loading a .dayplan file

A plan is a `.dayplan` file (JSON) with your weekly routine, reusable tasks (with exercise lists, notes…)
and changes for specific dates. The format is described in [`docs/PLAN_FORMAT.md`](docs/PLAN_FORMAT.md).
**Give that document to Claude in a chat and ask it to write your plan as a `.dayplan` file.**

Ways to load one. Each shows a preview (name, dates, first week, any problems) and nothing changes until
you tap **Use This Plan**:
- **Open in PlanAlarm:** tap the `.dayplan` file in Files, WhatsApp, Mail or AirDrop → Share → **PlanAlarm**.
- **Import from Files:** Plan tab **⋯** menu (or Settings) → **Import from Files…**
- **Paste:** copy the plan's text → **Paste Plan JSON…** → **Paste from Clipboard** → **Check**.
- **Load Sample Plan** to try the app (an "October Cut" plan).

If a file has mistakes, the preview lists each one in plain words, e.g.
`Monday, task 2: suggestedTime '25:00' is not a valid time.`

Loading a new plan **archives** the old one (Plan tab → Archived plans). Your history is never deleted.

### Changing a plan in the app
- **Add a task:** Plan tab → **Add Task** under a day → choose **Only that date** or **Every Monday** (etc.).
- **Edit or delete a task:** swipe it left (or long-press) → **Edit** / **Delete**. Tasks from the weekly
  pattern ask whether the change is for that date only or every week.
- **Clear a date:** **Clear Day**. **Undo a date's changes:** **Reset** brings back the normal weekday.
- **Start from nothing:** **New Empty Plan…**
- **Share the plan (with your edits):** Plan tab **⋯** → **Share Plan as File…** (e.g. back to Claude to adjust).
- **Delete plans:** Plan tab **⋯** → **Delete Plan…**, or swipe an archived plan left.

A date you changed on its own keeps its own tasks, even if you later change "every Monday".

**Days outside the plan's dates (or with no plan loaded):** you can still add, edit and delete tasks there.
They're kept in the app rather than in the plan file, so they stay when you load a new plan, but
**Share Plan as File** doesn't include them.

## 6. Your day: morning check-in and task alarms

### Morning check-in
1. The **wake-up alarm** rings (default 07:00; Settings → Alarms → Wake-up alarm).
2. Open PlanAlarm: **Today** shows the **Morning Check-in**.
   - Yesterday's unfinished tasks ask **"Did you do these?"**: answer Done or Skipped.
   - Each task has a time from the plan: change it, tap **Set time** if it has none, or switch on
     **Skip today**. Tasks whose time already passed move to 15 minutes from now (highlighted).
     Overlapping tasks show a warning.
3. Tap **Lock In My Day**: every task gets its alarm.
4. Not locked in yet? A **check-in reminder** rings 30 min after the wake-up alarm, then every 30 min (4 times).

### During the day (Today timeline)
- Change a task's time before it rings (the alarm moves), or mark it **Done** / **Skip**.
- A task that's ringing, in progress or overdue has **New Time**.
- Done or skipped by mistake? **Undo** / **Unskip**.
- Changes to today in the Plan tab show up on Today right away.
- The **open-lock button** (top right) **unlocks the day** to redo the check-in.

### When a task alarm rings
- It rings through silent mode and Focus, and **comes back every snooze interval (default 5 min) however
  it's stopped**: the Stop button, slide-to-stop, the side button or the volume buttons. iOS makes all of
  those stop the ring and apps can't change that, so PlanAlarm schedules the next rings in advance
  (covering about an hour; opening the app restarts them).
- **Open task** on the alarm opens PlanAlarm on that task. Opening the app any other way also goes straight
  to a waiting task.
- The **read screen** shows the whole task in large text. After a countdown (default 30 s; it only runs
  while the app is open on screen), choose one, and the alarm stops:
  - **Starting Now:** the task is in progress. When its duration has passed (or after 60 min), a
    **"Did you finish …?"** notification asks **Done** / **Skipped**; answer right from the notification.
  - **Reschedule:** a later time today; it rings (and you read it) again then.
  - **Skip Today.**

## 7. History and streaks

- **History** tab: a month calendar. Green = all done, orange = partly done, red = nothing done,
  grey = rest day (no tasks), blue = today in progress, faded red = a day without a check-in.
  Tap a day for its tasks, times, how often each rang again, and when it was done.
- **Streaks** (current and best):
  - *Perfect days:* every task done. Skipped or unlogged tasks and days without a check-in break it;
    rest days don't.
  - *Per category* (gym, study…): days that category was scheduled and done; other days are ignored.
  - Today only counts once it's complete.
- **Completion** for the last 7 and 30 days, overall and per category.
- **Export History** (History tab share button, or Settings → History) saves everything as a JSON backup.

History is kept when you load, edit or delete plans, and across reinstalls (same Apple ID, app not deleted).

## 8. Settings

| Setting | Default | Where |
|---|---|---|
| App expiry date, welcome screens | | Settings → App |
| Wake-up alarm (time, per-day on/off and times) | 07:00 every day | Settings → Alarms → Wake-up alarm |
| Check-in reminder (if not locked in) | on, every 30 min after wake-up | Settings → Alarms |
| Snooze length (task alarms ring again) | 5 min | Settings → Alarms |
| Read time before the read screen's buttons unlock | 30 s (a task's own time in the plan wins) | Settings → Alarms |
| Task alarm tone / wake-up tone | iPhone Alarm | Settings → Alarms |
| "Did you finish?" follow-up | on (task duration, or 60 min) | Settings → Follow-up |
| Plan: current plan, import, paste, new, sample | | Settings → Plan |
| Export history (JSON) | | Settings → History |

Hidden test tools (fire a test alarm in 1 minute, list scheduled alarms): tap **Build** in Settings 7 times.

## 9. Known iOS limitations

- **Stop, slide-to-stop and the physical buttons always stop an alarm.** On iOS 26.1+ the Stop button can't
  be removed or renamed, and every physical button stops an app's alarm (Apple's AlarmKit FAQ). PlanAlarm
  works around this with backup rings, so a stopped task alarm still comes back.
- **When the free install expires, its alarms stop too.** That's why the reinstall reminder exists.
- **Custom alarm tones** must be under 30 seconds and may play once per ring; only "iPhone Alarm" loops.
  Sounds added from Files aren't supported (iOS doesn't reliably play them for alarms).
- The read-screen countdown only runs while PlanAlarm is open on screen (by design).

## 10. Troubleshooting

- **Nothing rings:** Today shows a banner if alarms aren't allowed. Tap **Open Settings** → PlanAlarm →
  turn on **Alarms**.
- **No "Did you finish?" notification:** Settings → Follow-up shows a notice if notifications are off.
- **"Untrusted Developer" when opening:** do [First time only, on the iPhone](#first-time-only-on-the-iphone) step 2.
- **The app won't open at all:** the 7-day install expired. Reinstall with Sideloadly (same Apple ID).
- **The app crashes:** iPhone Settings → Privacy & Security → Analytics & Improvements → Analytics Data →
  the newest `PlanAlarm-…` entry → Share. Send that report along with what you were doing.

## 11. Switching to a paid Apple Developer account / TestFlight

A paid account ($99/year) means installs last a year (or TestFlight builds 90 days) instead of 7 days.
The app doesn't need rewriting. There are two options:

**A. Keep Sideloadly, with the paid Apple ID.** No code changes: sign in to Sideloadly with the paid account.
Installs then last a year. (Different Apple ID → Sideloadly gives the app a different ID → it installs as a
separate copy; export your history and share your plan file first.)

**B. TestFlight (installs from Apple's TestFlight app, no PC needed):**
1. In [App Store Connect](https://appstoreconnect.apple.com), create an app with bundle ID
   `com.habashi.planalarm`, and create an **API key** (Users and Access → Integrations → App Store Connect API,
   role *App Manager*). Note the Key ID and Issuer ID, and download the `.p8` file.
2. In the GitHub repository → Settings → Secrets and variables → Actions, add `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   and `ASC_KEY_P8` (the `.p8` file's contents) and `APPLE_TEAM_ID` (your Team ID from the developer account).
3. In `project.yml`, set `DEVELOPMENT_TEAM` to your Team ID.
4. Add a second job to `.github/workflows/build.yml` that signs with Xcode's automatic (cloud) signing and
   uploads to TestFlight, for example on version tags:

   ```yaml
     testflight:
       needs: build
       if: startsWith(github.ref, 'refs/tags/v')
       runs-on: macos-26
       steps:
         - uses: actions/checkout@v7
         - run: sudo xcode-select -s /Applications/Xcode_26.6.app/Contents/Developer
         - run: brew install xcodegen && xcodegen generate
         - name: Archive and upload to TestFlight
           env:
             ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
           run: |
             echo "$ASC_KEY_P8" > /tmp/key.p8
             AUTH="-allowProvisioningUpdates -authenticationKeyPath /tmp/key.p8 \
                   -authenticationKeyID ${{ secrets.ASC_KEY_ID }} -authenticationKeyIssuerID ${{ secrets.ASC_ISSUER_ID }}"
             xcodebuild archive -project PlanAlarm.xcodeproj -scheme PlanAlarm -configuration Release \
               -destination generic/platform=iOS -archivePath build/PlanAlarm.xcarchive \
               DEVELOPMENT_TEAM=${{ secrets.APPLE_TEAM_ID }} CURRENT_PROJECT_VERSION=${{ github.run_number }} $AUTH
             /usr/libexec/PlistBuddy -c "Add :method string app-store-connect" \
               -c "Add :destination string upload" -c "Add :teamID string ${{ secrets.APPLE_TEAM_ID }}" build/ExportOptions.plist
             xcodebuild -exportArchive -archivePath build/PlanAlarm.xcarchive \
               -exportOptionsPlist build/ExportOptions.plist -exportPath build/export $AUTH
   ```
5. Push a tag (e.g. `v1.1`); the build appears in TestFlight after Apple's processing.

The TestFlight app uses the plain bundle ID, so it's a separate app from the Sideloadly one: export your
history and share your plan file before switching.

## 12. For developers

- The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen);
  don't commit the `.xcodeproj`.
- CI: `.github/workflows/build.yml` (select Xcode 26.6 → XcodeGen → unit and screen tests on an iOS 26
  simulator → unsigned Release archive → `PlanAlarm.ipa` artifact, and a GitHub Release on `v*` tags).
- Swift 6, SwiftUI, AlarmKit, App Intents, SwiftData, UserNotifications. No third-party dependencies, no app
  extensions, no special entitlements.
- `CLAUDE.md` has the constraints, design decisions and workflow; `docs/PLAN_FORMAT.md` the plan format.
