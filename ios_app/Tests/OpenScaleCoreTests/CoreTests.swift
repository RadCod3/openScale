// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OpenScaleCore

final class CoreTests: XCTestCase {
    func hex(_ text: String) -> Data { Data(text.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    func testChipseaGoldenFrames() throws {
        // Same synthetic golden vectors as Android ChipseaBleLibTest.
        var parser = ChipseaProtocol()
        let live = try XCTUnwrap(parser.feed(hex("CA 10 12 00 00 02 F3")))
        XCTAssertFalse(live.locked); XCTAssertEqual(live.weightKg, 75.5, accuracy: 0.001)
        let locked = try XCTUnwrap(parser.feed(hex("CA 10 12 00 01 02 F3 00 EA 02 27 01 48 06 72 00 5A 1D")))
        XCTAssertTrue(locked.locked); XCTAssertEqual(locked.fields["BODY_FAT"], "23.4")
        XCTAssertEqual(locked.fields["BMR"], "1650.0")
        XCTAssertNil(parser.feed(hex("CA 11 10 12 12 00 00 00 00 01 00 00 00 00 01 02 F3 00 EA")))
        XCTAssertEqual(parser.feed(hex("CA 11 0B 12 22 02 27 01 48 06 72 00 5A 1D"))?.fields, locked.fields)
    }
    func testChipseaBoundsAndSequenceRecovery() {
        var p = ChipseaProtocol()
        for n in 0..<7 { XCTAssertNil(p.feed(Data([UInt8](repeating: 0xCA, count: n)))) }
        XCTAssertNil(p.feed(hex("CA 11 06 12 15 01 02 03 04")))
        XCTAssertNil(p.feed(hex("CA 11 06 12 45 05 06 07 08")))
        XCTAssertNil(p.feed(hex("CA 11 06 12 33 09 0A 0B 0C")))
        XCTAssertNil(p.feed(hex("CA 10 12 00 01 00 00")))
        XCTAssertEqual(ChipseaProtocol.weight(0x06, 0x75, property: 0x10), 74.978818761, accuracy: 0.001)
        XCTAssertEqual(ChipseaProtocol.weight(10, 75, property: 0x18), 66.90487, accuracy: 0.001)
    }
    func testUserSyncMatchesAndroid() {
        var p = Profile(); p.isMale = true; p.age = 40; p.heightCm = 170
        let date = ISO8601DateFormatter().date(from: "2026-10-21T23:30:15Z")!
        XCTAssertEqual(ChipseaProtocol.userSync(profile: p, now: date, timeZone: TimeZone(secondsFromGMT: 0)!),
                       hex("CA 10 0E 01 1A 0A 15 17 1E 0F 00 00 00 01 01 28 AA 9E 00 00"))
    }
    func testCSVQuotedFieldsUnitsAndRoundTrip() throws {
        let tz = TimeZone(secondsFromGMT: 0)!
        let text = "\u{FEFF}DATE,TIME,WEIGHT,COMMENT,CUSTOM\r\n2026-10-21,23:30:15,165.3,\"Line one\nLine \"\"two\"\"\",7\r\n"
        let result = try MeasurementCSV.parse(text, weightUnit: .lb, timeZone: tz)
        XCTAssertTrue(result.skippedRows.isEmpty)
        XCTAssertEqual(result.measurements[0].weightKg, 74.978818761, accuracy: 0.001)
        XCTAssertEqual(result.measurements[0].fields["COMMENT"], "Line one\nLine \"two\"")
        let imported = try MeasurementCSV.parse(MeasurementCSV.export(result.measurements, timeZone: tz), weightUnit: .kg, timeZone: tz)
        XCTAssertEqual(imported.measurements[0].fields, result.measurements[0].fields)
        XCTAssertEqual(imported.measurements[0].date, result.measurements[0].date)
        XCTAssertThrowsError(try MeasurementCSV.rows("DATE,WEIGHT\n\"unfinished"))
        XCTAssertThrowsError(try MeasurementCSV.parse("DATE,WEIGHT,weight\n", weightUnit: .kg))
    }
    func testCSVReportsInvalidRowsAndDefaultsMissingTimeToNoon() throws {
        let tz = TimeZone(secondsFromGMT: 0)!
        let r = try MeasurementCSV.parse("DATE,WEIGHT\n2026-11-07,80\n2026-02-30,75\n2026-11-06,nan\n2026-11-05,-4", weightUnit: .kg, timeZone: tz)
        XCTAssertEqual(r.measurements.count, 1); XCTAssertEqual(r.skippedRows, [3, 4, 5])
        XCTAssertEqual(r.measurements[0].date, ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z"))
    }
    func testNativeTimestampExportReimportIsIdempotent() throws {
        let tz = TimeZone(secondsFromGMT: 0)!
        let original = Measurement(date: Date(timeIntervalSince1970: 1_800_000_000.123456), weightKg: 70)
        let reimported = try MeasurementCSV.parse(MeasurementCSV.export([original], timeZone: tz), weightUnit: .kg, timeZone: tz)
        let store = try MeasurementStore(path: ":memory:")
        XCTAssertEqual(try store.insert([original]), 1)
        XCTAssertEqual(try store.insert(reimported.measurements), 0)
        let shortFraction = try MeasurementCSV.parse("DATE,TIME,WEIGHT\n2026-11-07,09:00:00.1,70", weightUnit: .kg, timeZone: tz)
        XCTAssertTrue(shortFraction.skippedRows.isEmpty)
        XCTAssertEqual(shortFraction.measurements[0].date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.1, accuracy: 0.0001)
    }
    func testSQLitePersistenceDuplicatesAndAtomicRollback() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try MeasurementStore(path: path)
        let m = Measurement(date: Date(timeIntervalSince1970: 1000), weightKg: 75.5, fields: ["COMMENT": "A ' quote"])
        XCTAssertEqual(try store.insert([m, m]), 1)
        XCTAssertEqual(try MeasurementStore(path: path).all(), [m])
        XCTAssertThrowsError(try store.insert([Measurement(weightKg: 80), Measurement(weightKg: -1)]))
        XCTAssertEqual(try store.all(), [m])
        let other = Measurement(date: Date(timeIntervalSince1970: 1001), weightKg: 70)
        try store.insert([other])
        try store.delete(id: m.id)
        XCTAssertEqual(try store.all(), [other], "Undo-style deletion must preserve unrelated records")
        try store.delete(id: other.id); XCTAssertTrue(try store.all().isEmpty)
    }
}
