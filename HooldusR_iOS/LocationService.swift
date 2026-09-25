//
//  LocationService.swift
//  HooldusR_iOS
//
//  Replaces MyLocationNewOverlay + GpsMyLocationProvider. The Android app polls
//  the overlay with a Handler once a second; CoreLocation already delivers
//  updates at about that rate, so the coordinate strip just binds to it.
//

import Foundation
import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    @ObservationIgnored private let manager = CLLocationManager()

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    var hasFix: Bool { coordinate != nil }

    /// iOS asks once. If the surveyor picks "Don't Allow" the app has to send
    /// them to Settings — there is no Android-style re-prompt on next launch.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let fix = latest.coordinate
        Task { @MainActor in self.coordinate = fix }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] \(error.localizedDescription)")
    }
}
