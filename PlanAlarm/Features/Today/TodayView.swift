import SwiftData
import SwiftUI

/// Today: the morning check-in until the day is locked in, then the day's timeline.
struct TodayView: View {
    let date: LocalDate

    @Query private var dayRecords: [DayRecord]

    init(date: LocalDate) {
        self.date = date
        let key = date.description
        _dayRecords = Query(filter: #Predicate<DayRecord> { $0.date == key })
    }

    var body: some View {
        NavigationStack {
            if let dayRecord = dayRecords.first {
                TodayTimelineView(date: date, dayRecord: dayRecord)
            } else {
                CheckInView(date: date)
            }
        }
    }
}
