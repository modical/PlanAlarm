import Foundation
import Testing
@testable import PlanAlarm

struct AppExpiryTests {
    private func cairo() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
        return calendar
    }

    private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) throws -> Date {
        Fixtures.date(iso).date(hour: hour, minute: minute, calendar: try cairo())
    }

    /// A provisioning profile is binary (a CMS signature) around an XML plist; imitate that shape.
    private func profileData(expiring: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AppIDName</key><string>PlanAlarm</string>
            <key>CreationDate</key><date>2026-09-30T08:00:00Z</date>
            <key>ExpirationDate</key><date>\(expiring)</date>
            <key>TeamIdentifier</key><array><string>J4V38G56NA</string></array>
        </dict>
        </plist>
        """
        return Data([0x30, 0x82, 0x0F, 0x1A, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0])
            + Data(plist.utf8)
            + Data([0x00, 0xA0, 0x82, 0x0B, 0x6D, 0x30, 0x82, 0x04, 0x04, 0xFF])
    }

    @Test func readsTheExpirationDateFromASigningProfile() throws {
        let date = try #require(AppExpiry.expirationDate(fromProvisioningProfile: profileData(expiring: "2026-10-07T08:00:00Z")))
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-07T08:00:00Z"))
    }

    @Test func unreadableProfilesGiveNoDate() {
        #expect(AppExpiry.expirationDate(fromProvisioningProfile: Data()) == nil)
        #expect(AppExpiry.expirationDate(fromProvisioningProfile: Data("not a profile".utf8)) == nil)
        #expect(AppExpiry.expirationDate(fromProvisioningProfile: Data("<?xml version=\"1.0\"?><plist><dict>".utf8)) == nil)
    }

    @Test func reminderIsAtEightTheEveningBefore() throws {
        let calendar = try cairo()
        // Expires Wed 7 Oct 11:00 → reminder Tue 6 Oct 20:00.
        #expect(AppExpiry.reminderDate(for: try at("2026-10-07", 11), now: try at("2026-10-01", 9), calendar: calendar)
                == (try at("2026-10-06", 20)))
        // Expires just after midnight → still the evening before.
        #expect(AppExpiry.reminderDate(for: try at("2026-10-07", 0, 30), now: try at("2026-10-01", 9), calendar: calendar)
                == (try at("2026-10-06", 20)))
        // The evening before has already passed → no alarm (the Today banner covers it).
        #expect(AppExpiry.reminderDate(for: try at("2026-10-07", 11), now: try at("2026-10-06", 21), calendar: calendar) == nil)
    }

    @Test func warningStartsFortyEightHoursBefore() throws {
        let expiry = AppExpiry(date: try at("2026-10-07", 11), source: .signingProfile)
        #expect(!expiry.isWarningDue(now: try at("2026-10-05", 10)))
        #expect(expiry.isWarningDue(now: try at("2026-10-05", 12)))
        #expect(expiry.isWarningDue(now: try at("2026-10-08", 12)))
    }

    @Test func fallsBackToInstallDatePlusSevenDays() throws {
        // The test host app has no signing profile, so the estimate is used.
        let expiry = try #require(AppExpiry.current())
        #expect(expiry.source == .estimatedFromInstall)
        let installed = try #require(AppExpiry.installDate())
        #expect(expiry.date == installed.addingTimeInterval(7 * 24 * 3600))
    }

    @Test func registryKeepsTheReinstallReminder() throws {
        let defaults = try #require(UserDefaults(suiteName: "ExpiryRegistry-\(UUID().uuidString)"))
        var registry = AlarmRegistry()
        let ring = ScheduledRing(id: UUID(), date: try at("2026-10-06", 20))
        registry.expiryReminder = ring
        registry.save(to: defaults)
        let loaded = AlarmRegistry.load(from: defaults)
        #expect(loaded.expiryReminder == ring)
        #expect(loaded.knownAlarmIDs.contains(ring.id))
    }
}
