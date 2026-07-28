import SwiftUI

/// Native List swipe actions matching Notifications hub motion/UI.
/// Swipe left (trailing) → complete / undo, or alert if not completable.
/// Swipe right (leading) → delete (caller shows confirmation).
struct CalendarOccurrenceSwipeRow: View {
    let occurrence: CalendarEntryOccurrence
    let isCompleted: Bool
    let onOpen: () -> Void
    let onToggleComplete: () -> Void
    let onNotCompletable: () -> Void
    let onRequestDelete: () -> Void
    var onIncrementProgress: (() -> Void)? = nil

    private var isCompletable: Bool {
        occurrence.entry.isCompletable
    }

    var body: some View {
        EntryRowView(
            occurrence: occurrence,
            isCompleted: isCompleted,
            onToggleComplete: isCompletable ? onToggleComplete : nil,
            onIncrementProgress: onIncrementProgress
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .swipeActions(edge: .trailing, allowsFullSwipe: isCompletable) {
            Button {
                if isCompletable {
                    onToggleComplete()
                } else {
                    onNotCompletable()
                }
            } label: {
                Label(
                    isCompleted ? "Undo" : "Complete",
                    systemImage: isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
            }
            .tint(isCompletable ? LifeOSTheme.accent : LifeOSTheme.softText)
        }
        .swipeActions(edge: .leading) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
