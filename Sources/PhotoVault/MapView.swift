import MapKit
import SwiftUI

/// Photos that carry GPS tags, shown on a map. Nearby photos merge into one pin that
/// splits apart as you zoom in; selecting a pin lists its photos along the bottom.
struct MapView: View {
    @EnvironmentObject private var gallery: GalleryModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 240))
    @State private var didFit = false
    @State private var selectedPin: String?
    @State private var viewerIndex: Int?

    private struct Pin: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let items: [GalleryItem]
    }

    private var located: [(GalleryItem, GalleryModel.Coordinate)] {
        gallery.items.compactMap { item in gallery.locations[item.id].map { (item, $0) } }
    }

    private var pins: [Pin] {
        let cell = max(region.span.latitudeDelta, region.span.longitudeDelta) / 12
        var buckets: [String: [(GalleryItem, GalleryModel.Coordinate)]] = [:]
        for entry in located {
            let key = "\(Int((entry.1.latitude / cell).rounded(.down)))_\(Int((entry.1.longitude / cell).rounded(.down)))"
            buckets[key, default: []].append(entry)
        }
        return buckets.map { key, entries in
            let lat = entries.map(\.1.latitude).reduce(0, +) / Double(entries.count)
            let lon = entries.map(\.1.longitude).reduce(0, +) / Double(entries.count)
            return Pin(id: key, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                       items: entries.map(\.0).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        let pins = pins
        let selected = pins.first { $0.id == selectedPin }
        ZStack {
            Map(coordinateRegion: $region, annotationItems: pins) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
                    pinView(pin, isSelected: pin.id == selectedPin)
                        .onTapGesture { selectedPin = pin.id }
                }
            }
            overlayMessage
            if let selected {
                VStack {
                    Spacer()
                    strip(for: selected)
                }
            }
            if let index = viewerIndex, let selected, index < selected.items.count {
                ViewerView(items: selected.items, index: Binding(
                    get: { min(index, selected.items.count - 1) },
                    set: { viewerIndex = $0 }
                )) { viewerIndex = nil }
            }
        }
        .navigationTitle("Map")
        .navigationSubtitle(located.isEmpty ? "" : "\(located.count) photos with a location")
        .onAppear { gallery.loadLocations() }
        .onChange(of: gallery.items.count) { _ in gallery.loadLocations() }
        .onChange(of: gallery.locations.count) { _ in fitToPhotos() }
    }

    @ViewBuilder
    private var overlayMessage: some View {
        if gallery.isReadingLocations && gallery.locations.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Reading photo locations…").font(.callout)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        } else if !gallery.isReadingLocations && located.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "mappin.slash").font(.system(size: 32, weight: .light))
                Text("No Located Photos").font(.headline)
                Text("None of your photos have GPS data. Turn on Location\nServices for Camera on the iPhone to tag new photos.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func pinView(_ pin: Pin, isSelected: Bool) -> some View {
        ZStack {
            Circle().fill(isSelected ? Color.orange : Color.accentColor)
            Circle().strokeBorder(.white, lineWidth: 2)
            Text(pin.items.count > 999 ? "999+" : "\(pin.items.count)")
                .font(.caption.weight(.bold)).foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .shadow(radius: 2)
    }

    private func strip(for pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(pin.items.count) photo\(pin.items.count == 1 ? "" : "s") here").font(.headline)
                Spacer()
                Button { selectedPin = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(pin.items.enumerated()), id: \.element.id) { offset, item in
                        ThumbnailCell(item: item)
                            .frame(width: 96, height: 96)
                            .onTapGesture { viewerIndex = offset }
                    }
                }
            }
        }
        .padding(10)
        .background(.regularMaterial)
    }

    /// Zooms to the bounding box of all located photos, once per visit.
    private func fitToPhotos() {
        guard !didFit, !located.isEmpty else { return }
        didFit = true
        let lats = located.map(\.1.latitude), lons = located.map(\.1.longitude)
        let (minLat, maxLat, minLon, maxLon) = (lats.min()!, lats.max()!, lons.min()!, lons.max()!)
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(max((maxLat - minLat) * 1.4, 0.02), 170),
                                   longitudeDelta: min(max((maxLon - minLon) * 1.4, 0.02), 350)))
    }
}
