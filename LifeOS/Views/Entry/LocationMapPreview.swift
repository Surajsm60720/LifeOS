import MapKit
import SwiftUI

struct LocationMapPreview: View {
    let name: String
    let latitude: Double
    let longitude: Double
    var height: CGFloat = 120
    var interactive: Bool = false

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
    }

    var body: some View {
        Map(position: .constant(.region(region)), interactionModes: interactive ? [.pan, .zoom] : []) {
            Marker(name.isEmpty ? "Place" : name, coordinate: coordinate)
        }
        .mapStyle(.standard)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of \(name.isEmpty ? "saved place" : name)")
    }
}
