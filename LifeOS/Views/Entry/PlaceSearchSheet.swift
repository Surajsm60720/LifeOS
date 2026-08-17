import MapKit
import CoreLocation
import SwiftUI

struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSelect: (String, Double?, Double?) -> Void

    @StateObject private var support = PlacePickerSupport()
    @State private var query = ""
    @State private var placeName = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isSearching = false
    @State private var isGeocoding = false
    @State private var errorMessage: String?
    @State private var showCompletions = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case search
        case name
    }

    private var trimmedName: String {
        let named = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { return named }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConfirm: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer

                VStack(spacing: 10) {
                    searchOverlay
                    if showCompletions, !support.completions.isEmpty {
                        completionsList
                    }
                    Spacer()
                    bottomBar
                }
                .padding(12)
            }
            .navigationTitle("Find Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                        .disabled(!canConfirm)
                }
            }
            .onAppear {
                focusedField = .search
            }
            .onChange(of: query) { _, newValue in
                errorMessage = nil
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    support.clearCompletions()
                    showCompletions = false
                    return
                }
                support.updateQuery(trimmed, region: visibleRegion)
                showCompletions = focusedField == .search
            }
            .onChange(of: support.locationStamp) { _, _ in
                guard let coord = support.locationCoordinate else { return }
                applyCoordinate(coord, reverseGeocode: true, recenter: true)
            }
            .onChange(of: support.locationDenied) { _, denied in
                if denied {
                    errorMessage = "Location access is off. Search or tap the map instead."
                }
            }
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let selectedCoordinate {
                    Marker(trimmedName.isEmpty ? "Place" : trimmedName, coordinate: selectedCoordinate)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    focusedField = nil
                    showCompletions = false
                    guard let coord = proxy.convert(event.location, from: .local) else { return }
                    applyCoordinate(coord, reverseGeocode: true, recenter: false)
                    Haptics.light()
                }
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var searchOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search or type a place name", text: $query)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .focused($focusedField, equals: .search)
                .onSubmit { searchQuery() }
            if isSearching || isGeocoding {
                ProgressView()
                    .controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    support.clearCompletions()
                    showCompletions = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: focusedField) { _, field in
            showCompletions = field == .search && !support.completions.isEmpty
        }
    }

    private var completionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(support.completions.enumerated()), id: \.offset) { _, item in
                    Button {
                        selectCompletion(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(.primary)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Place name", text: $placeName)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)

                Button {
                    support.requestCurrentLocation()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use current location")
            }

            Text(selectedCoordinate == nil
                 ? "Tap the map to drop a pin, or confirm a typed name."
                 : "Pin set. Confirm to save, or tap again to move it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        focusedField = nil
        showCompletions = false
        query = completion.title
        isSearching = true
        errorMessage = nil

        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, error in
            isSearching = false
            if let error {
                errorMessage = error.localizedDescription
                return
            }
            guard let item = response?.mapItems.first else {
                errorMessage = "No places found."
                return
            }
            applyMapItem(item)
        }
    }

    private func searchQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        focusedField = nil
        showCompletions = false
        isSearching = true
        errorMessage = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let visibleRegion {
            request.region = visibleRegion
        }
        MKLocalSearch(request: request).start { response, error in
            isSearching = false
            if let error {
                errorMessage = error.localizedDescription
                return
            }
            guard let item = response?.mapItems.first else {
                placeName = trimmed
                errorMessage = "No map match. Confirm to save the name, or tap the map."
                return
            }
            applyMapItem(item)
        }
    }

    private func applyMapItem(_ item: MKMapItem) {
        let name = item.name ?? item.placemark.title ?? "Place"
        placeName = name
        query = name
        let coord = item.placemark.coordinate
        if CLLocationCoordinate2DIsValid(coord) {
            applyCoordinate(coord, reverseGeocode: false, recenter: true)
        }
    }

    private func applyCoordinate(
        _ coord: CLLocationCoordinate2D,
        reverseGeocode: Bool,
        recenter: Bool
    ) {
        selectedCoordinate = coord
        if recenter {
            position = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
        guard reverseGeocode else { return }

        isGeocoding = true
        errorMessage = nil
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            isGeocoding = false
            if let place = placemarks?.first {
                let resolved = place.name
                    ?? [place.thoroughfare, place.locality].compactMap { $0 }.joined(separator: ", ")
                if !resolved.isEmpty {
                    placeName = resolved
                } else if placeName.isEmpty {
                    placeName = "Dropped pin"
                }
            } else if placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placeName = "Dropped pin"
            }
        }
    }

    private func confirm() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        if let selectedCoordinate, CLLocationCoordinate2DIsValid(selectedCoordinate) {
            onSelect(name, selectedCoordinate.latitude, selectedCoordinate.longitude)
        } else {
            onSelect(name, nil, nil)
        }
        dismiss()
    }
}

@MainActor
final class PlacePickerSupport: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var locationCoordinate: CLLocationCoordinate2D?
    @Published var locationDenied = false
    @Published var locationStamp = 0

    private let completer = MKLocalSearchCompleter()
    private let locationManager = CLLocationManager()

    private var awaitingLocation = false

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func updateQuery(_ query: String, region: MKCoordinateRegion?) {
        completer.queryFragment = query
        if let region {
            completer.region = region
        }
    }

    func clearCompletions() {
        completer.queryFragment = ""
        completions = []
    }

    func requestCurrentLocation() {
        awaitingLocation = true
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationDenied = false
            locationManager.requestLocation()
        case .denied, .restricted:
            awaitingLocation = false
            locationDenied = true
        @unknown default:
            awaitingLocation = false
            locationDenied = true
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationDenied = false
                if self.awaitingLocation {
                    self.locationManager.requestLocation()
                }
            case .denied, .restricted:
                self.awaitingLocation = false
                self.locationDenied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.awaitingLocation = false
            self.locationCoordinate = coordinate
            self.locationStamp += 1
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.awaitingLocation = false
        }
    }
}
