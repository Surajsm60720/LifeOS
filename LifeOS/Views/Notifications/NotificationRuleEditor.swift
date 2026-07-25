import SwiftUI

struct NotificationRuleEditor: View {
    @Bindable var rule: NotificationRule
    var showActiveToggle: Bool = true

    var body: some View {
        Section {
            Picker("Trigger", selection: $rule.triggerKind) {
                ForEach(NotificationTriggerKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            Text(rule.triggerKind.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch rule.triggerKind {
            case .fixedTime, .ifNotCompletedBy:
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { rule.triggerDate ?? defaultTime },
                        set: { rule.triggerDate = $0 }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
            case .relativeToStart:
                Stepper(
                    offsetLabel,
                    value: Binding(
                        get: { Int((rule.triggerInterval ?? 0) / 60) },
                        set: { rule.triggerInterval = TimeInterval($0 * 60) }
                    ),
                    in: -24 * 60...24 * 60,
                    step: 5
                )
            }
        } header: {
            Text("When")
        }

        Section {
            TextField("Message", text: $rule.messageTemplate, axis: .vertical)
                .lineLimit(2...5)

            Text("Placeholders: {title}, {category}")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let entry = rule.entry {
                LabeledContent("Preview") {
                    Text(rule.renderedMessage(for: entry))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Message")
        }

        if showActiveToggle {
            Section {
                Toggle("Active", isOn: $rule.isActive)
            } footer: {
                Text("Inactive rules stay saved but will not schedule local notifications.")
            }
        }
    }

    private var defaultTime: Date {
        Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
    }

    private var offsetLabel: String {
        let minutes = Int((rule.triggerInterval ?? 0) / 60)
        if minutes == 0 { return "Offset: at start" }
        if minutes > 0 { return "Offset: \(minutes) min after start" }
        return "Offset: \(-minutes) min before start"
    }
}
