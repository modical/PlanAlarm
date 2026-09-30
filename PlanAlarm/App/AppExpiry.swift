import Foundation

/// When this install stops opening. Apps signed with a free Apple ID (sideloaded with Sideloadly) expire
/// after 7 days, which would silently stop every alarm.
struct AppExpiry: Equatable, Sendable {
    enum Source: Sendable {
        /// Read from the signing profile (embedded.mobileprovision) that Sideloadly puts in the app.
        case signingProfile
        /// Estimated as install date + 7 days (no readable signing profile).
        case estimatedFromInstall
    }

    static let freeAccountLifetime: TimeInterval = 7 * 24 * 3600
    static let warningWindow: TimeInterval = 48 * 3600

    var date: Date
    var source: Source

    /// Under 48 hours left: show the banner on Today.
    func isWarningDue(now: Date = .now) -> Bool {
        date.timeIntervalSince(now) < Self.warningWindow
    }

    /// The "Reinstall PlanAlarm" alarm: 20:00 on the day before the expiry day (local time), about a day
    /// ahead at a sensible hour. Nil if that time has passed.
    static func reminderDate(for expiry: Date, now: Date, calendar: Calendar = .plan) -> Date? {
        let reminder = LocalDate(expiry, calendar: calendar).adding(days: -1).date(hour: 20, minute: 0, calendar: calendar)
        guard reminder > now, reminder < expiry else { return nil }
        return reminder
    }

    /// Reads ExpirationDate from a provisioning profile. The file is a signed (CMS) wrapper around an XML
    /// property list, so the plist is cut out between "<?xml" and "</plist>".
    static func expirationDate(fromProvisioningProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }

    /// This install's expiry: from the signing profile, else install date + 7 days.
    static func current(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> AppExpiry? {
        if let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let date = expirationDate(fromProvisioningProfile: data) {
            return AppExpiry(date: date, source: .signingProfile)
        }
        guard let installed = installDate(bundle: bundle, defaults: defaults) else { return nil }
        return AppExpiry(date: installed.addingTimeInterval(freeAccountLifetime), source: .estimatedFromInstall)
    }

    /// When this copy was installed: the app folder is created fresh by every install (even of the same
    /// build). If that can't be read, the first launch of this build number is used.
    static func installDate(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> Date? {
        if let created = (try? FileManager.default.attributesOfItem(atPath: bundle.bundlePath))?[.creationDate] as? Date {
            return created
        }
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        if defaults.string(forKey: "expiry.lastBuild") != build {
            defaults.set(build, forKey: "expiry.lastBuild")
            defaults.set(Date.now, forKey: "expiry.firstLaunchOfBuild")
        }
        return defaults.object(forKey: "expiry.firstLaunchOfBuild") as? Date
    }
}
