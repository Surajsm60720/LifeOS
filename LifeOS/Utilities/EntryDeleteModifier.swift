import SwiftUI

/// Shared delete confirmation + context-menu actions for entries.
struct EntryDeleteModifier: ViewModifier {
    let title: String
    let onDelete: () -> Void

    @State private var confirm = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Delete Entry", role: .destructive) {
                    confirm = true
                }
            }
            .confirmationDialog(
                "Delete “\(title)”?",
                isPresented: $confirm,
                titleVisibility: .visible
            ) {
                Button("Delete Entry", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the entry, its recurrence, completions, and notification rules.")
            }
    }
}

extension View {
    func entryDeleteMenu(title: String, onDelete: @escaping () -> Void) -> some View {
        modifier(EntryDeleteModifier(title: title, onDelete: onDelete))
    }
}
