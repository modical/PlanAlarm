import AVFoundation
import SwiftUI

/// Picks an alarm tone; tapping a tone plays a short preview.
struct TonePickerView: View {
    let title: String
    @Binding var selection: AlarmTone

    @State private var player = TonePreviewPlayer()

    var body: some View {
        List {
            Section {
                ForEach(AlarmTone.allCases) { tone in
                    Button {
                        selection = tone
                        player.play(tone)
                    } label: {
                        HStack {
                            Text(tone.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if tone == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text("Tap a tone to hear it. iPhone Alarm keeps ringing until stopped; the other tones play for up to 30 seconds per ring (an iOS limit), and the alarm comes back every snooze interval.")
            }
        }
        .navigationTitle(title)
        .onDisappear { player.stop() }
    }
}

/// Plays a few seconds of a bundled tone. The iPhone's own alarm sound can't be previewed by apps.
@MainActor
@Observable
final class TonePreviewPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ tone: AlarmTone) {
        stop()
        guard let fileName = tone.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: nil) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
    }
}
