import SwiftUI

/// A compact one-day summary: date, note and task times. Used in the import preview.
struct DaySummaryRow: View {
    let day: ResolvedDay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.date.shortText).font(.headline)
                Spacer()
                if let mode = day.overrideMode {
                    OverrideBadge(mode: mode)
                }
            }
            if let note = day.dayNote {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if day.tasks.isEmpty {
                Text("No tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(day.tasks.enumerated()), id: \.offset) { _, task in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(task.suggestedTime?.description ?? "--:--")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(task.title)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Marks a day changed by a dateOverride.
struct OverrideBadge: View {
    let mode: DateOverride.Mode

    var body: some View {
        Text(mode == .add ? "Extra tasks" : "Changed day")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2), in: Capsule())
            .foregroundStyle(.orange)
            .textCase(nil)
    }
}
