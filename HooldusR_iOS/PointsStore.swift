//
//  PointsStore.swift
//  HooldusR_iOS
//
//  Port of DB.java. Same database file name, same table, same columns.
//  Android ships a prebuilt `db_f` in assets and copies it out on first run;
//  here the table is simply created if it is missing, which needs no asset
//  and no hardcoded /data/data path.
//

import Foundation
import Observation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Observable
final class PointsStore {

    @ObservationIgnored private var db: OpaquePointer?

    private(set) var points: [ObservationPoint] = []
    private(set) var lastError: String?

    /// Documents/db_f — visible in the Files app, and included in device backups.
    static var databaseURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("db_f")
    }

    init() {
        openDatabase()
        createTableIfNeeded()
        reload()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Setup

    private func openDatabase() {
        if sqlite3_open(Self.databaseURL.path, &db) != SQLITE_OK {
            lastError = errorMessage
            print("[DB] open failed: \(errorMessage)")
        }
    }

    private func createTableIfNeeded() {
        // Column names and types match the Android schema exactly.
        let sql = """
        CREATE TABLE IF NOT EXISTS tb_points (
            id_p    INTEGER NOT NULL UNIQUE,
            date_pr TEXT,
            correct INTEGER,
            lat_    TEXT,
            long_   TEXT,
            comment TEXT,
            PRIMARY KEY(id_p AUTOINCREMENT)
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            lastError = errorMessage
            print("[DB] create table failed: \(errorMessage)")
        }
    }

    private var errorMessage: String {
        guard let db, let text = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: text)
    }

    // MARK: - Reads

    func reload() {
        var loaded: [ObservationPoint] = []
        let sql = "SELECT id_p, date_pr, correct, lat_, long_, comment FROM tb_points ORDER BY id_p;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            lastError = errorMessage
            print("[DB] select failed: \(errorMessage)")
            return
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            loaded.append(ObservationPoint(
                id: Int(sqlite3_column_int(statement, 0)),
                date: Self.text(statement, 1),
                detection: ObservationPoint.Detection(storedValue: Int(sqlite3_column_int(statement, 2))),
                latitudeText: Self.text(statement, 3),
                longitudeText: Self.text(statement, 4),
                comment: Self.text(statement, 5)))
        }
        points = loaded
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    // MARK: - Writes

    @discardableResult
    func insert(date: String,
                detection: ObservationPoint.Detection,
                latitude: Double,
                longitude: Double,
                comment: String) -> Bool {

        let sql = "INSERT INTO tb_points (date_pr, correct, lat_, long_, comment) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            lastError = errorMessage
            print("[DB] insert prepare failed: \(errorMessage)")
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, date, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(detection.rawValue))
        sqlite3_bind_text(statement, 3, ObservationPoint.coordinateText(latitude), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, ObservationPoint.coordinateText(longitude), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, comment, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            lastError = errorMessage
            print("[DB] insert failed: \(errorMessage)")
            return false
        }
        reload()
        return true
    }

    @discardableResult
    func delete(id: Int) -> Bool {
        let sql = "DELETE FROM tb_points WHERE id_p = ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            lastError = errorMessage
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(id))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            lastError = errorMessage
            print("[DB] delete failed: \(errorMessage)")
            return false
        }
        reload()
        return true
    }
}
