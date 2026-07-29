import Foundation

struct CalendarEntryOccurrence: Identifiable {
    /// A composite key instead of an interpolated string. Expanding a year of
    /// recurring entries can create six figures of these, and `uuidString` plus
    /// string interpolation per occurrence was pure allocation overhead.
    struct ID: Hashable {
        let entryID: UUID
        let occurrenceDate: Date
    }

    let id: ID
    let entry: Entry
    let occurrenceDate: Date

    init(entry: Entry, occurrenceDate: Date) {
        self.entry = entry
        self.occurrenceDate = occurrenceDate
        self.id = ID(entryID: entry.id, occurrenceDate: occurrenceDate)
    }
}

struct RecurrenceEngine {
    static let shared = RecurrenceEngine()
    private let hardCap = 2_000

    func occurrences(for entry: Entry, in range: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        guard let rule = entry.recurrence else {
            let start = entry.startDate
            guard range.contains(start) else { return [] }
            return [start]
        }

        return occurrences(
            frequency: rule.frequency,
            interval: rule.interval,
            daysOfWeek: rule.daysOfWeek,
            endDate: rule.endDate,
            occurrenceCount: rule.occurrenceCount,
            anchor: entry.startDate,
            in: range,
            calendar: calendar
        )
    }

    func occurrences(
        frequency: RecurrenceFrequency,
        interval rawInterval: Int,
        daysOfWeek: Set<Weekday>?,
        endDate: Date?,
        occurrenceCount: Int?,
        anchor: Date,
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [Date] {
        let interval = max(1, rawInterval)
        var results: [Date] = []
        var count = 0
        let maxCount = min(occurrenceCount ?? hardCap, hardCap)
        var safety = 0
        let anchorDay = calendar.startOfDay(for: anchor)

        switch frequency {
        case .daily:
            var cursor = anchorDay
            // Jump near the range without skipping the first overlapping day.
            if cursor < calendar.startOfDay(for: range.lowerBound) {
                let days = calendar.dateComponents([.day], from: cursor, to: calendar.startOfDay(for: range.lowerBound)).day ?? 0
                let steps = max(0, days / interval)
                if let advanced = calendar.date(byAdding: .day, value: steps * interval, to: cursor) {
                    cursor = advanced
                }
            }
            while count < maxCount, safety < hardCap {
                safety += 1
                if let endDate, cursor > endDate { break }
                if cursor > calendar.startOfDay(for: range.upperBound) { break }

                if cursor >= anchorDay {
                    let occurrence = combineTime(from: anchor, day: cursor, calendar: calendar)
                    if shouldInclude(occurrence, endDate: endDate, range: range) {
                        results.append(occurrence)
                        count += 1
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: interval, to: cursor), next > cursor else { break }
                cursor = next
            }

        case .weekly:
            if let days = daysOfWeek, !days.isEmpty {
                var dayCursor = calendar.startOfDay(for: range.lowerBound)
                let endDay = calendar.startOfDay(for: range.upperBound)
                while dayCursor <= endDay, count < maxCount, safety < hardCap {
                    safety += 1
                    let weekday = calendar.component(.weekday, from: dayCursor)
                    if days.contains(where: { $0.rawValue == weekday }),
                       dayCursor >= anchorDay,
                       weeksBetween(from: anchor, to: dayCursor, interval: interval, calendar: calendar) {
                        let occurrence = combineTime(from: anchor, day: dayCursor, calendar: calendar)
                        if shouldInclude(occurrence, endDate: endDate, range: range) {
                            results.append(occurrence)
                            count += 1
                        }
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor), next > dayCursor else { break }
                    dayCursor = next
                }
            } else {
                var cursor = anchorDay
                while count < maxCount, safety < hardCap {
                    safety += 1
                    if let endDate, cursor > endDate { break }
                    if cursor > calendar.startOfDay(for: range.upperBound) { break }

                    let occurrence = combineTime(from: anchor, day: cursor, calendar: calendar)
                    if shouldInclude(occurrence, endDate: endDate, range: range) {
                        results.append(occurrence)
                        count += 1
                    }
                    guard let next = calendar.date(byAdding: .weekOfYear, value: interval, to: cursor), next > cursor else { break }
                    cursor = next
                }
            }

        case .monthly, .everyNMonths:
            var year = calendar.component(.year, from: anchor)
            var month = calendar.component(.month, from: anchor)

            // Fast-forward toward the range lower bound using month arithmetic (no Jan-31 overflow).
            while safety < hardCap {
                safety += 1
                guard let probe = dateInMonth(year: year, month: month, anchoring: anchor, calendar: calendar) else { break }
                if probe >= range.lowerBound { break }
                month += interval
                while month > 12 {
                    month -= 12
                    year += 1
                }
            }

            safety = 0
            while count < maxCount, safety < hardCap {
                safety += 1
                guard let occurrence = dateInMonth(year: year, month: month, anchoring: anchor, calendar: calendar) else { break }
                if occurrence > range.upperBound { break }
                if occurrence >= anchor, shouldInclude(occurrence, endDate: endDate, range: range) {
                    results.append(occurrence)
                    count += 1
                }
                month += interval
                while month > 12 {
                    month -= 12
                    year += 1
                }
            }
        }

        return results.sorted()
    }

    func occurs(on day: Date, entry: Entry, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        let end = DateFormatting.endOfDay(day, calendar: calendar)
        return !occurrences(for: entry, in: start...end, calendar: calendar).isEmpty
    }

    func normalizeOccurrenceStart(_ date: Date, for entry: Entry, calendar: Calendar = .current) -> Date {
        if entry.recurrence == nil {
            if entry.isAllDay {
                return calendar.startOfDay(for: entry.startDate)
            }
            return entry.startDate
        }
        if entry.isAllDay {
            return calendar.startOfDay(for: date)
        }
        // A recurring occurrence always lands on the anchor's wall-clock time, so the
        // normalized value is just that time on `date`'s day. Running a full expansion
        // here was needless work on a path that `isCompleted` hits per visible row.
        let dayStart = calendar.startOfDay(for: date)
        return combineTime(from: entry.startDate, day: dayStart, calendar: calendar)
    }

    /// Ceiling on occurrences returned from a single expansion. A year view over a
    /// large library of daily-recurring entries can otherwise materialize hundreds of
    /// thousands of objects; no UI can present that, so we stop early instead.
    static let maxExpandedOccurrences = 20_000

    func expandEntries(_ entries: [Entry], in interval: DateInterval, calendar: Calendar = .current) -> [CalendarEntryOccurrence] {
        // DateInterval.end is exclusive; convert carefully for ClosedRange expansion.
        let endInclusive = interval.end.addingTimeInterval(-0.001)
        let range = interval.start...max(interval.start, endInclusive)

        var results: [CalendarEntryOccurrence] = []
        for entry in entries {
            // Cheap O(1) rejection before touching any Calendar math.
            guard overlapsRange(entry, range: range) else { continue }

            for date in occurrences(for: entry, in: range, calendar: calendar) {
                results.append(CalendarEntryOccurrence(entry: entry, occurrenceDate: date))
                if results.count >= Self.maxExpandedOccurrences { break }
            }
            if results.count >= Self.maxExpandedOccurrences { break }
        }

        results.sort { $0.occurrenceDate < $1.occurrenceDate }
        if results.count > Self.maxExpandedOccurrences {
            results = Array(results.prefix(Self.maxExpandedOccurrences))
        }
        return results
    }

    /// Counts occurrences without building `CalendarEntryOccurrence` objects or
    /// sorting, for callers that only display a total.
    func countOccurrences(_ entries: [Entry], in interval: DateInterval, calendar: Calendar = .current) -> Int {
        let endInclusive = interval.end.addingTimeInterval(-0.001)
        let range = interval.start...max(interval.start, endInclusive)

        var total = 0
        for entry in entries {
            guard overlapsRange(entry, range: range) else { continue }
            total += occurrences(for: entry, in: range, calendar: calendar).count
            if total >= Self.maxExpandedOccurrences { break }
        }
        return min(total, Self.maxExpandedOccurrences)
    }

    /// Rejects entries that provably cannot produce an occurrence in `range`,
    /// using only date comparisons.
    private func overlapsRange(_ entry: Entry, range: ClosedRange<Date>) -> Bool {
        guard let rule = entry.recurrence else {
            return range.contains(entry.startDate)
        }
        // Series hasn't begun by the end of the window.
        if entry.startDate > range.upperBound { return false }
        // Series already finished before the window opens.
        if let end = rule.endDate, end < range.lowerBound { return false }
        return true
    }

    private func shouldInclude(_ occurrence: Date, endDate: Date?, range: ClosedRange<Date>) -> Bool {
        if let endDate, occurrence > endDate { return false }
        return range.contains(occurrence)
    }

    private func combineTime(from source: Date, day: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    private func weeksBetween(from anchor: Date, to date: Date, interval: Int, calendar: Calendar) -> Bool {
        let safeInterval = max(1, interval)
        let anchorStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        let dateStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let weekDelta = calendar.dateComponents([.weekOfYear], from: anchorStart, to: dateStart).weekOfYear ?? 0
        return weekDelta >= 0 && weekDelta % safeInterval == 0
    }

    /// Builds an occurrence in `year`/`month` using the anchor's day-of-month, clamped to month length.
    private func dateInMonth(year: Int, month: Int, anchoring anchor: Date, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let monthStart = calendar.date(from: components) else { return nil }
        let day = calendar.component(.day, from: anchor)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? day
        components.day = min(day, daysInMonth)
        guard let dayDate = calendar.date(from: components) else { return nil }
        return combineTime(from: anchor, day: dayDate, calendar: calendar)
    }
}
