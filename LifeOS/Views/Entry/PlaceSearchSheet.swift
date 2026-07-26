import MapKit
import CoreLocation
import SwiftUI

struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSelect: (String, Double?, Double?) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search places", text: $query)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)
                        .onSubmit { search() }
                }

                if isSearching {
                    ProgressView("Searching…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }

                Section("Results") {
                    if results.isEmpty, !isSearching, errorMessage == nil {
                        Text("Type a place name and search.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button {
                            let name = item.name
                                ?? item.placemark.title
                                ?? "Place"
                            let coord = item.placemark.coordinate
                            if CLLocationCoordinate2DIsValid(coord) {
                                onSelect(name, coord.latitude, coord.longitude)
                            } else {
                                onSelect(name, nil, nil)
                            }
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place")
                                    .foregroundStyle(.primary)
                                if let subtitle = item.placemark.title, subtitle != item.name {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") { search() }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        results = []

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            if let error {
                errorMessage = error.localizedDescription
                return
            }
            results = response?.mapItems ?? []
            if results.isEmpty {
                errorMessage = "No places found."
            }
        }
    }
}
