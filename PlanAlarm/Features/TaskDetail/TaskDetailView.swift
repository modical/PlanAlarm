import SwiftUI

struct TaskDetailView: View {
    let task: PlanTask

    var body: some View {
        ScrollView {
            TaskContentView(task: task)
                .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The full task in large, readable type. Also used by the read-to-dismiss screen.
struct TaskContentView: View {
    let task: PlanTask

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(.largeTitle.bold())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { chips }
                    VStack(alignment: .leading, spacing: 8) { chips }
                }
            }

            if let summary = task.summary, !summary.isEmpty {
                Text(summary)
                    .font(.title3)
            }

            ForEach(Array(task.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.title2.bold())
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("•")
                                .font(.title3.bold())
                                .foregroundStyle(.tint)
                            Text(item)
                                .font(.title3)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chips: some View {
        Chip(text: task.category.capitalized, systemImage: "tag")
        if let duration = task.durationText {
            Chip(text: duration, systemImage: "clock")
        }
        if let time = task.suggestedTime {
            Chip(text: time.description, systemImage: "alarm")
        }
    }
}

private struct Chip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemFill), in: Capsule())
    }
}
