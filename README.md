# PlanAlarm

A personal iPhone app that turns a daily plan (gym, stretches, study…) into reminders that ring like
real alarms: through silent mode and Focus, over and over, until you open the app and read the task.

> Status: **phase 2 (plan files)**. You can load and browse plans; alarms arrive in phase 3.

## Getting the app (.ipa)

Every push to `main` is built automatically by GitHub Actions on a Mac in the cloud.

1. Open https://github.com/modical/PlanAlarm/actions
2. Click the newest run with a green check mark ✅.
3. Scroll down to **Artifacts** and click **PlanAlarm-build-NN** to download a `.zip`.
4. Unzip it. Inside is `PlanAlarm.ipa`. That's the app file.

Tagged versions (like `v1.0`) also appear under **Releases** on the repository's main page, with the `.ipa` attached.

**Build time:** roughly 5–10 minutes per build. The repository is public, so GitHub Actions minutes
are free (the macOS minute limit only applies to private repositories).

## Installing on your iPhone with Sideloadly (Windows, free Apple ID)

### One-time setup
1. Install **iTunes** and **iCloud** for Windows from Apple's website (the versions from apple.com,
   *not* the Microsoft Store). This installs the drivers Windows needs to talk to your iPhone.
2. Install **Sideloadly** from https://sideloadly.io
3. Connect your iPhone with a USB cable. On the iPhone, tap **Trust** and enter your passcode.

### Install (or reinstall) the app
1. Open Sideloadly. Your iPhone should appear in the **iDevice** box.
2. Drag `PlanAlarm.ipa` onto the Sideloadly window (or click the IPA icon and pick the file).
3. Type your Apple ID email in the **Apple account** box and click **Start**.
4. Enter your Apple ID password when Sideloadly asks, and the 2-factor code if one appears.
5. Wait for **Done.** at the bottom of Sideloadly.

### First time only, on the iPhone
1. **Turn on Developer Mode:** Settings → Privacy & Security → scroll to the bottom → **Developer Mode** → on.
   The iPhone restarts; after it restarts, tap **Turn On** and enter your passcode.
   (If you don't see Developer Mode, install the app once with Sideloadly first, then look again.)
2. **Trust yourself as a developer:** Settings → General → **VPN & Device Management** → tap your
   Apple ID under *Developer App* → **Trust "…"** → **Trust**.
3. Open PlanAlarm from the home screen.

### Weekly reinstall
Apps installed with a free Apple ID stop opening after **7 days**. Once a week, repeat
*Install (or reinstall) the app* with the newest `.ipa`.
- Always use the **same Apple ID**, and **don't delete the app first**: install on top of it. The app keeps
  the same bundle ID (`com.habashi.planalarm`), so your plan and history are kept.
- In Sideloadly, leave the bundle ID in the advanced options unchanged.

## Loading a plan (.dayplan file)

A plan is a `.dayplan` file (JSON). The format is described in [`docs/PLAN_FORMAT.md`](docs/PLAN_FORMAT.md).
Give that document to Claude in a chat and ask it to write your plan as a `.dayplan` file.

Three ways to load one. Each shows a preview first, and nothing changes until you tap **Use This Plan**:
- **Open in PlanAlarm:** tap the `.dayplan` file in Files, WhatsApp, Mail or AirDrop, tap the Share button,
  and choose **PlanAlarm**.
- **Import from Files:** in the app, **Settings → Import from Files…** (or the import button on the Plan tab).
- **Paste:** copy the plan's text, then **Settings → Paste Plan JSON… → Paste from Clipboard → Check**.

To try the app without a real plan, use **Settings → Load Sample Plan** (October 2026).
Loading a new plan archives the old one (Plan tab → Archived plans). Nothing is deleted.

## Switching to a paid Apple Developer account / TestFlight (later)

Nothing needs rewriting. The steps are:
1. In `project.yml`, set `DEVELOPMENT_TEAM` to your Team ID.
2. Add signing secrets to the repository (distribution certificate + App Store Connect API key) and add a CI job
   that archives *with* signing and uploads to TestFlight.
3. Create the app in App Store Connect with the same bundle ID, `com.habashi.planalarm`.

This section will be expanded in phase 7.

## For developers

- The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  Don't commit the `.xcodeproj`.
- CI: `.github/workflows/build.yml`. See `CLAUDE.md` for the project's constraints and workflow.
