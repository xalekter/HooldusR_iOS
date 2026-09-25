//
//  MapScreen.swift
//  HooldusR_iOS
//
//  The whole app, same as Android's single MainActivity: a green button bar,
//  the map, and a coordinate strip along the bottom.
//

import SwiftUI
import MapKit

struct MapScreen: View {

    @State private var store = PointsStore()
    @State private var location = LocationService()
    @State private var controller = MapController()

    @State private var capabilities: WMSCapabilities?
    @State private var isLoadingLayers = true
    @State private var showForestMap = true
    @State private var showPoints = false
    @State private var satellite = false

    @State private var isAddingPoint = false
    @State private var pointToDelete: PointAnnotation?
    @State private var exportedCSV: ExportedFile?
    @State private var showingAbout = false
    @State private var toast: ToastMessage?
    @State private var layerError: String?

    var body: some View {
        VStack(spacing: 0) {
            buttonBar
            mapArea
            coordinateStrip
        }
        .background(Color.black)
        .ignoresSafeArea(.keyboard)
        .task {
            location.start()
            await loadForestLayers()
        }
        .sheet(isPresented: $isAddingPoint) {
            AddPointSheet(coordinate: location.coordinate, onSave: save)
        }
        .sheet(item: $exportedCSV) { file in
            ShareSheet(items: [file.url])
        }
        .alert("Remove point",
               isPresented: Binding(get: { pointToDelete != nil },
                                    set: { if !$0 { pointToDelete = nil } }),
               presenting: pointToDelete) { point in
            Button("Delete", role: .destructive) { delete(point) }
            Button("Cancel", role: .cancel) { pointToDelete = nil }
        } message: { point in
            Text("Point #\(point.pointID) will be removed from the database.")
        }
        .alert("About", isPresented: $showingAbout) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(AppConfig.aboutText)\n\(AppConfig.versionText)")
        }
        .overlay(alignment: .top) {
            if let toast {
                ToastView(message: toast)
                    .padding(.top, 8)
            }
        }
        .animation(.snappy, value: toast)
    }

    // MARK: - Bar

    private var buttonBar: some View {
        HStack(spacing: 0) {
            barButton("location.fill", label: "My location", action: goToMyLocation)

            barButton("plus.circle.fill", label: "Add point") {
                guard location.coordinate != nil else {
                    show(.init(text: "Position no set", kind: .warning))
                    return
                }
                isAddingPoint = true
            }

            barButton(image: showForestMap ? "tree_hide" : "tree_show",
                      label: "Forest map") {
                showForestMap.toggle()
            }

            if isLoadingLayers {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }

            barButton(satellite ? "map.fill" : "globe.americas.fill",
                      label: "Base map") {
                satellite.toggle()
            }

            Menu {
                Toggle("Show points", isOn: $showPoints)
                Button("Save as *.csv", systemImage: "square.and.arrow.up", action: exportCSV)
                Button("About", systemImage: "info.circle") { showingAbout = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: AppTheme.barHeight)
        .background(AppTheme.darkGreen)
    }

    private func barButton(_ systemName: String,
                           label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(label)
    }

    private func barButton(image: String,
                           label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 26)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Map

    private var mapArea: some View {
        MapContainerView(controller: controller,
                         capabilities: capabilities,
                         showForestMap: showForestMap,
                         satellite: satellite,
                         annotations: annotations,
                         onSelect: { pointToDelete = $0 })
            .overlay(alignment: .bottomLeading) { layerErrorBadge }
    }

    private var annotations: [PointAnnotation] {
        guard showPoints else { return [] }
        return store.points.compactMap { point in
            guard let coordinate = point.coordinate else { return nil }
            return PointAnnotation(point: point, coordinate: coordinate)
        }
    }

    @ViewBuilder
    private var layerErrorBadge: some View {
        if let layerError {
            Button {
                Task { await loadForestLayers() }
            } label: {
                Label(layerError, systemImage: "arrow.clockwise")
                    .font(.caption)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(12)
        }
    }

    // MARK: - Coordinates

    private var coordinateStrip: some View {
        HStack(spacing: 14) {
            Text(text(location.coordinate?.latitude))
            Text(text(location.coordinate?.longitude))
            Spacer()
            if location.isDenied {
                Button("Location off — open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(height: 25)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "00.000000" }
        return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: - Actions

    private func loadForestLayers() async {
        isLoadingLayers = true
        layerError = nil
        do {
            let loaded = try await WMSLoader.load(from: AppConfig.capabilitiesURL)
            capabilities = loaded
            if let box = loaded.boundingBox, location.coordinate == nil {
                controller.show(box.region)
            }
        } catch {
            layerError = "Forest map unavailable. Tap to retry."
            print("[WMS] \(error.localizedDescription)")
        }
        isLoadingLayers = false
    }

    private func goToMyLocation() {
        guard let coordinate = location.coordinate else {
            show(.init(text: "Position no set", kind: .warning))
            return
        }
        controller.center(on: coordinate)
    }

    private func save(_ detection: ObservationPoint.Detection, _ comment: String) {
        guard let coordinate = location.coordinate else {
            show(.init(text: "Position no set", kind: .warning))
            return
        }
        let saved = store.insert(date: ObservationPoint.timestamp(),
                                 detection: detection,
                                 latitude: coordinate.latitude,
                                 longitude: coordinate.longitude,
                                 comment: comment)
        if saved {
            showPoints = true
            show(.init(text: "Point has saved", kind: .success))
        } else {
            show(.init(text: store.lastError ?? "Could not save the point", kind: .failure))
        }
    }

    private func delete(_ annotation: PointAnnotation) {
        pointToDelete = nil
        if store.delete(id: annotation.pointID) {
            show(.init(text: "Point #\(annotation.pointID) removed", kind: .success))
        } else {
            show(.init(text: store.lastError ?? "Could not remove the point", kind: .failure))
        }
    }

    private func exportCSV() {
        guard !store.points.isEmpty else {
            show(.init(text: "No points to export", kind: .warning))
            return
        }
        do {
            exportedCSV = ExportedFile(url: try CSVExporter.write(store.points))
        } catch {
            show(.init(text: "Export failed: \(error.localizedDescription)", kind: .failure))
        }
    }

    private func show(_ message: ToastMessage) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.id == message.id { toast = nil }
        }
    }
}

// MARK: - Share sheet

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

#Preview {
    MapScreen()
}
