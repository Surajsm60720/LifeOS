import SwiftUI

struct RecurrenceEditorView: View {
    @Bindable var rule: RecurrenceRule

    var body: some View {
        Picker("Frequency", selection: $rule.frequency) {
            ForEach(RecurrenceFrequency.allCases) { frequency in
                Text(frequency.displayName).tag(frequency)
            }
        }

        Stepper("Every \(rule.interval)", value: $rule.interval, in: 1...52)

        if rule.frequency == .weekly {
            weekdayPicker
        }

        Toggle("End Date", isOn: Binding(
            get: { rule.endDate != nil },
            set: { enabled in
                rule.endDate = enabled ? Calendar.current.date(byAdding: .month, value: 3, to: .now) : nil
            }
        ))

        if rule.endDate != nil {
            DatePicker("Ends", selection: Binding(
                get: { rule.endDate ?? .now },
                set: { rule.endDate = $0 }
            ), displayedComponents: [.date])
        }

        Toggle("Limit Occurrences", isOn: Binding(
            get: { rule.occurrenceCount != nil },
            set: { enabled in
                rule.occurrenceCount = enabled ? 10 : nil
            }
        ))

        if rule.occurrenceCount != nil {
            Stepper(
                "Occurrences: \(rule.occurrenceCount ?? 0)",
                value: Binding(
                    get: { rule.occurrenceCount ?? 10 },
                    set: { rule.occurrenceCount = $0 }
                ),
                in: 1...365
            )
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days of Week")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                ForEach(Weekday.allCases) { weekday in
                    let selected = rule.daysOfWeek?.contains(weekday) ?? false
                    Button(weekday.shortName) {
                        var days = rule.daysOfWeek ?? []
                        if selected {
                            days.remove(weekday)
                        } else {
                            days.insert(weekday)
                        }
                        rule.daysOfWeek = days.isEmpty ? nil : days
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? LifeOSTheme.accent : LifeOSTheme.softText)
                }
            }
        }
    }
}
