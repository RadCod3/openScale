// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OpenScaleCore

final class WeighInWorkflowTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var frame: Data { Data([0xC0, 1, 0x1D, 0x7E, 0x13, 0x88, 0, 1, 0x25, 1, 2, 3, 4, 5, 6]) }

    func testRememberedBroadcastMatchesExactIdentityAcrossUUIDChanges() throws {
        let remembered = RememberedScale(peripheralID: id, name: "Unnamed device", manufacturerData: frame)
        XCTAssertEqual(remembered.name, "Your OKOK scale")
        let restored = try JSONDecoder().decode(RememberedScale.self, from: JSONEncoder().encode(remembered))
        XCTAssertTrue(restored.matches(peripheralID: UUID(), manufacturerData: frame))
        var other = frame; other[14] = 7
        XCTAssertFalse(restored.matches(peripheralID: id, manufacturerData: other))
        XCTAssertFalse(restored.matches(peripheralID: UUID(), manufacturerData: nil))
    }
    func testGATTAndInvalidEmbeddedIdentityUseOnlySavedPeripheralID() {
        let remembered = RememberedScale(peripheralID: id, name: "Chipsea-BLE", manufacturerData: nil)
        XCTAssertTrue(remembered.matches(peripheralID: id, manufacturerData: nil))
        XCTAssertFalse(remembered.matches(peripheralID: UUID(), manufacturerData: nil))
        var blank = frame; blank.replaceSubrange(9...14, with: repeatElement(0, count: 6))
        XCTAssertNil(RememberedScale(peripheralID: id, name: "Scale", manufacturerData: blank).broadcastIdentity)
    }
    func testFinalBurstIsSuppressedAcrossSessionsAndRelaunch() throws {
        var gate = FinalReadingGate()
        let final = ScaleReading(weightKg: 75.5, locked: true, fields: ["IMPEDANCE": "500"])
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(gate.allows(final, device: "scale", now: now))
        XCTAssertFalse(gate.allows(final, device: "scale", now: now.addingTimeInterval(1)))
        let receipt = try JSONDecoder().decode(FinalReadingGate.Receipt.self, from: JSONEncoder().encode(gate.receipt!))
        var relaunched = FinalReadingGate(receipt: receipt)
        XCTAssertFalse(relaunched.allows(final, device: "scale", now: now.addingTimeInterval(60)))
        XCTAssertTrue(relaunched.allows(final, device: "scale", now: now.addingTimeInterval(121)))
    }
    func testNewLiveSequenceAllowsSameWeightAndDevicesAreIndependent() {
        var gate = FinalReadingGate()
        let final = ScaleReading(weightKg: 75.5, locked: true)
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(gate.allows(final, device: "one", now: now))
        XCTAssertTrue(gate.allows(ScaleReading(weightKg: 70, locked: false), device: "one", now: now))
        XCTAssertTrue(gate.allows(final, device: "one", now: now))
        XCTAssertFalse(gate.allows(final, device: "one", now: now))
        XCTAssertTrue(gate.allows(final, device: "two", now: now))
    }
}
