import Foundation

/// Alarm sounds. `system` is iOS's own alarm sound (it loops). The others are bundled files in
/// Resources/Sounds: AlarmKit needs custom sounds in the app bundle and under 30 seconds, and they may
/// play once per ring rather than loop.
enum AlarmTone: String, CaseIterable, Identifiable, Sendable {
    case system, classic, chime, pulse, digital, rise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "iPhone Alarm (default)"
        case .classic: "Classic Beeps"
        case .chime: "Chime"
        case .pulse: "Rising Pulse"
        case .digital: "Digital Watch"
        case .rise: "Gentle Rise"
        }
    }

    /// The bundled sound file, or nil for the system sound.
    var fileName: String? {
        self == .system ? nil : "tone-\(rawValue).wav"
    }
}
