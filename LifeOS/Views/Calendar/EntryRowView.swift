import SwiftUI

struct EntryRowView: View {
    let occurrence: CalendarEntryOccurrence
    let isCompleted: Bool
    var onToggleComplete: (() -> Void)? = nil
    var onIncrementProgress: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(rowAccent)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.entry.title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? LifeOSTheme.softText : .white)

                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
            }

            Spacer(minLength: 8)

            if occurrence.entry.supportsProgress, onIncrementProgress != nil {
                Button {
                    onIncrementProgress?()
                } label: {
                    Text("+1")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(LifeOSTheme.canvas)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(LifeOSTheme.accent.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add one \(occurrence.entry.progress?.unitLabel ?? "unit")")
            }

            if occurrence.entry.isCompletable {
                Button {
                    onToggleComplete?()
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isCompleted ? LifeOSTheme.accent : LifeOSTheme.softText.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onToggleComplete == nil)
                .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
        .opacity(isCompleted ? 0.72 : 1)
        .accessibilityElement(children: .contain)
    }

    private var rowAccent: Color {
        if occurrence.entry.category == .game {
            return GameIdentity.accent(for: occurrence.entry.gameSubCategory)
        }
        return occurrence.entry.displayColor
    }

    private var subtitle: String {
        var parts = [occurrence.entry.category.displayName]
        if let subCategory = occurrence.entry.subCategory {
            parts.append(subCategory)
        }
        if let progress = occurrence.entry.progress {
            if let total = progress.totalUnits {
                parts.append("\(progress.currentUnit)/\(total) \(progress.unitLabel)")
            } else {
                parts.append("\(progress.currentUnit) \(progress.unitLabel)")
            }
        }
        if !occurrence.entry.isAllDay {
            let time = DateFormatter.localizedString(from: occurrence.occurrenceDate, dateStyle: .none, timeStyle: .short)
            parts.append(time)
        }
        return parts.joined(separator: " · ")
    }
}
