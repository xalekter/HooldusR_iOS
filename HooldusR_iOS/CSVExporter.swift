//
//  CSVExporter.swift
//  HooldusR_iOS
//
//  Port of MainActivity.save_csv(). The header row and the ";" separator are
//  kept exactly as Android writes them so exports from both platforms can be
//  concatenated or diffed.
//
//  iOS has no shared external storage, so the file goes to the app's Documents
//  folder (visible in the Files app) and is handed to the share sheet.
//

import Foundation

enum CSVExporter {

    static func write(_ points: [ObservationPoint]) throws -> URL {
        var text = "id;Date;Detection;Latitude;Longitude;Comment  \n"

        for point in points {
            // Newlines inside a comment would break the row; Android has the same
            // hazard and simply never handles it.
            let comment = point.comment
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: ";", with: ",")

            text += "\(point.id);\(point.date);\(point.detection.rawValue);"
                  + "\(point.latitudeText);\(point.longitudeText);\(comment)\n"
        }

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Points_\(fileTimestamp()).csv")

        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Android overwrites one fixed "Points_.csv"; a timestamp keeps every export.
    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: Date())
    }
}
