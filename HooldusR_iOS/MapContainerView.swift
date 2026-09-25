//
//  MapContainerView.swift
//  HooldusR_iOS
//
//  The MKMapView bridge. Replaces osmdroid's MapView plus its overlay stack:
//  TilesOverlay -> MKTileOverlay, ItemizedIconOverlay -> MKAnnotationView,
//  ScaleBarOverlay -> showsScale, CopyrightOverlay -> Apple's own attribution.
//

import SwiftUI
import MapKit
import Observation

// MARK: - Annotation

final class PointAnnotation: NSObject, MKAnnotation {
    nonisolated let coordinate: CLLocationCoordinate2D
    nonisolated let title: String?
    nonisolated let subtitle: String?
    nonisolated let pointID: Int
    nonisolated let detection: ObservationPoint.Detection

    nonisolated init(point: ObservationPoint, coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        // Android puts the row id in the title and "comment\ndate" in the snippet.
        self.title = "#\(point.id)"
        self.subtitle = point.comment.isEmpty ? point.date : "\(point.comment) — \(point.date)"
        self.pointID = point.id
        self.detection = point.detection
        super.init()
    }
}

// MARK: - Imperative camera control

/// Buttons need to move the camera without re-rendering the whole view, so the
/// map hands itself to this controller instead of being driven by state.
@Observable
final class MapController {
    @ObservationIgnored weak var mapView: MKMapView?

    func center(on coordinate: CLLocationCoordinate2D, metersAcross: Double = 700) {
        mapView?.setRegion(MKCoordinateRegion(center: coordinate,
                                              latitudinalMeters: metersAcross,
                                              longitudinalMeters: metersAcross),
                           animated: true)
    }

    func show(_ region: MKCoordinateRegion) {
        guard let mapView else { return }
        mapView.setRegion(mapView.regionThatFits(region), animated: true)
    }
}

// MARK: - The view

struct MapContainerView: UIViewRepresentable {

    let controller: MapController
    var capabilities: WMSCapabilities?
    var showForestMap: Bool
    var satellite: Bool
    var annotations: [PointAnnotation]
    var onSelect: (PointAnnotation) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true           // Android's ScaleBarOverlay
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.setRegion(MKCoordinateRegion(center: AppConfig.fallbackCenter,
                                         latitudinalMeters: 20_000,
                                         longitudinalMeters: 20_000),
                      animated: false)
        controller.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.applyBaseMap(satellite: satellite, to: map)
        context.coordinator.applyForestLayer(capabilities: capabilities,
                                             visible: showForestMap,
                                             to: map)
        context.coordinator.applyAnnotations(annotations, to: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {

        var onSelect: (PointAnnotation) -> Void = { _ in }

        private var tileOverlay: WMSTileOverlay?
        private var installedLayerKey: String?
        private var annotationKey: String?
        private var satelliteApplied: Bool?

        // MARK: Base map

        func applyBaseMap(satellite: Bool, to map: MKMapView) {
            guard satelliteApplied != satellite else { return }
            satelliteApplied = satellite
            map.preferredConfiguration = satellite
                ? MKImageryMapConfiguration()
                : MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        }

        // MARK: Forest layer

        func applyForestLayer(capabilities: WMSCapabilities?, visible: Bool, to map: MKMapView) {
            guard let capabilities, !capabilities.layerNames.isEmpty else { return }

            let key = capabilities.layerNames.joined(separator: ",")
            if installedLayerKey != key {
                if let existing = tileOverlay { map.removeOverlay(existing) }
                let overlay = WMSTileOverlay(getMapURL: capabilities.getMapURL,
                                             layerNames: capabilities.layerNames)
                tileOverlay = overlay
                installedLayerKey = key
            }

            guard let overlay = tileOverlay else { return }
            let isShown = map.overlays.contains { $0 === overlay }
            if visible, !isShown {
                // Above labels so the forest compartments read like they do in QGIS.
                map.addOverlay(overlay, level: .aboveLabels)
            } else if !visible, isShown {
                map.removeOverlay(overlay)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: Points

        func applyAnnotations(_ annotations: [PointAnnotation], to map: MKMapView) {
            let key = annotations.map { "\($0.pointID):\($0.detection.rawValue)" }
                .joined(separator: "|")
            guard key != annotationKey else { return }
            annotationKey = key

            let existing = map.annotations.compactMap { $0 as? PointAnnotation }
            map.removeAnnotations(existing)
            map.addAnnotations(annotations)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PointAnnotation else { return nil }

            let identifier = "observation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.image = UIImage(named: point.detection.assetName)
            view.centerOffset = CGPoint(x: 0, y: -12)   // pin tip at the coordinate
            view.canShowCallout = true
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }

        func mapView(_ mapView: MKMapView,
                     annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let point = view.annotation as? PointAnnotation else { return }
            onSelect(point)
        }
    }
}
