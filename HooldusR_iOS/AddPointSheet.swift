//
//  AddPointSheet.swift
//  HooldusR_iOS
//
//  Replaces the add_point_layout panel. Same three inputs as Android:
//  detection, comment, and the current GPS fix taken at save time.
//

import SwiftUI
import CoreLocation

struct AddPointSheet: View {

    let coordinate: CLLocationCoordinate2D?
    let onSave: (ObservationPoint.Detection, String) -> Void

    @State private var detection: ObservationPoint.Detection = .correct
    @State private var comment = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Detection") {
                    Picker("Detection", selection: $detection) {
                        ForEach([ObservationPoint.Detection.correct,
                                 .incorrect,
                                 .missing]) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Comment") {
                    TextField("Put your comments", text: $comment, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Position") {
                    if let coordinate {
                        LabeledContent("Latitude", value: formatted(coordinate.latitude))
                        LabeledContent("Longitude", value: formatted(coordinate.longitude))
                    } else {
                        Label("Waiting for a GPS fix", systemImage: "location.slash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(detection, comment.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(coordinate == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
