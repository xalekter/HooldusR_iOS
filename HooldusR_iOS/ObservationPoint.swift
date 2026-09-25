//
//  ObservationPoint.swift
//  HooldusR_iOS
//
//  One field observation. Mirrors `tb_points` in the Android app's SQLite
//  database column for column, so a CSV from either platform lines up.
//

import Foundation
import CoreLocation
import SwiftUI

struct ObservationPoint: Identifiable, Hashable {

    enum Detection: Int, CaseIterable, Identifiable, Hashable {
        case incorrect = 0
        case correct   = 1
        case missing   = 2

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .correct:   return "Correct"
            case .incorrect: return "Incorrect"
            case .missing:   return "Missing"
            }
        }

        /// Marker PNGs carried over from res/drawable.
        var assetName: String {
            switch self {
            case .correct:   return "marker_green"
            case .incorrect: return "marker_red"
            case .missing:   return "marker_yellow"
            }
        }

        var tint: Color {
            switch self {
            case .correct:   return .green
            case .incorrect: return .red
            case .missing:   return .yellow
            }
        }

        /// Android treats any value other than 0 or 1 as "missing" (yellow marker).
        init(storedValue: Int) {
            self = Detection(rawValue: storedValue) ?? .missing
        }
    }

    var id: Int
    /// yyyy_MM_dd_HH_mm, the format Android's SimpleDateFormat writes.
    var date: String
    var detection: Detection
    /// Latitude and longitude are TEXT in the shared schema. They are kept as the
    /// stored strings so an exported CSV is byte-comparable with Android's.
    var latitudeText: String
    var longitudeText: String
    var comment: String

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = Self.number(latitudeText), let lon = Self.number(longitudeText) else { return nil }
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Android's timestamp format, forced to a fixed locale so an Estonian
    /// device does not produce a different string.
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy_MM_dd_HH_mm"
        return formatter.string(from: date)
    }

    /// Android stores String.valueOf(double); this keeps a dot separator on every locale.
    static func coordinateText(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

