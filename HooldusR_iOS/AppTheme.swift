//
//  AppTheme.swift
//  HooldusR_iOS
//
//  Colours and constants carried over from the Android app so the two
//  versions look and behave the same in the field.
//

import SwiftUI
import CoreLocation

enum AppTheme {
    /// res/values/colors.xml -> DarkGreen (#079E3B), the button bar background.
    static let darkGreen = Color(red: 0x07 / 255, green: 0x9E / 255, blue: 0x3B / 255)
    static let barHeight: CGFloat = 50
}

enum AppConfig {
    /// Same QGIS Server project the Android app draws.
    static let capabilitiesURL = URL(
        string: "https://nutriloopworks.to.ee/wms/forest/?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetCapabilities")!

    /// Where the map sits before a GPS fix or the project bbox arrives.
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 58.30, longitude: 26.51)

    static let aboutText = "Developed by Tartu Observatory"

    static var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "vers.\(v) (\(b))"
    }
}
