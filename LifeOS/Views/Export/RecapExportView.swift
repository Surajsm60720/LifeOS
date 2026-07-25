import SwiftUI
import UIKit

struct RecapExportView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [Entry]

    @State private var preset: RecapPreset = .thisMonth
    @State private var customStart = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now
    @State private var customEnd = Date.now
    @State private var includeIRL = true
    @State private var includeGames = true
    @State private var includeEntertainment = true
    @State private var exportURL: URL?
    @State private var lastMarkdown: String = ""
    @State private var showingShareSheet = false
    @State private var exportError: String?
    @State private var copyConfirmation: String?

    private let exporter = RecapExporter()

    enum RecapPreset: String, CaseIterable, Identifiable {
        case thisMonth
        case thisYear
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thisMonth: "This Month"
            case .thisYear: "This Year"
            case .custom: "Custom Range"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Range") {
                    Picker("Preset", selection: $preset) {
                        ForEach(RecapPreset.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }

                    if preset == .custom {
                        DatePicker("Start", selection: $customStart, displayedComponents: [.date])
                        DatePicker("End", selection: $customEnd, displayedComponents: [.date])
                    }
                }

                Section("Categories") {
                    Toggle("IRL", isOn: $includeIRL)
                    Toggle("Games", isOn: $includeGames)
                    Toggle("Entertainment", isOn: $includeEntertainment)
                }

                Section {
                    Button("Generate Recap") {
                        generateRecap(share: true)
                    }
                    .disabled(!includeIRL && !includeGames && !includeEntertainment)

                    Button("Copy Markdown") {
                        generateRecap(share: false)
                        UIPasteboard.general.string = lastMarkdown
                        copyConfirmation = "Copied to clipboard"
                    }
                    .disabled(!includeIRL && !includeGames && !includeEntertainment)
                }

                if let copyConfirmation {
                    Section {
                        Text(copyConfirmation)
                            .foregroundStyle(.secondary)
                    }
                }

                if let exportError {
                    Section {
                        Text(exportError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export Recap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    private func generateRecap(share: Bool) {
        let range = selectedRange
        let options = RecapExporter.Options(
            includeIRL: includeIRL,
            includeGames: includeGames,
            includeEntertainment: includeEntertainment
        )
        let result = exporter.export(entries: entries, range: range, options: options)
        lastMarkdown = result.markdown

        guard share else {
            exportError = nil
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(result.suggestedFilename)
        do {
            try result.markdown.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showingShareSheet = true
            exportError = nil
            copyConfirmation = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var selectedRange: ClosedRange<Date> {
        let calendar = Calendar.current
        switch preset {
        case .thisMonth:
            let interval = DateFormatting.monthInterval(containing: .now, calendar: calendar)
            return interval.start...interval.end
        case .thisYear:
            let interval = DateFormatting.yearInterval(containing: .now, calendar: calendar)
            return interval.start...interval.end
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = DateFormatting.endOfDay(max(customStart, customEnd), calendar: calendar)
            return start...end
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
