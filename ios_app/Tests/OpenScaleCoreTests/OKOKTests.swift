// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OpenScaleCore

final class OKOKTests: XCTestCase {
    func testC0CapturedWeighInWithPropertyBit5() throws {
        // From the failed hardware diagnostic. Embedded device identity is redacted;
        // it is not used for decoding. Property 0x25: locked, hundredths, kg, bit 5 set.
        let frame = Data([0xC0, 0x33, 0x19, 0xFF, 0x17, 0x70, 0x0A, 0x01, 0x25,
                          0, 0, 0, 0, 0, 0])
        XCTAssertTrue(OKOKAdvertisement.recognizes(frame), "The captured scale must be selectable")
        let reading = try XCTUnwrap(OKOKAdvertisement.parse(frame), "The captured final weigh-in must be decoded")
        XCTAssertTrue(reading.locked)
        XCTAssertEqual(reading.weightKg, 66.55, accuracy: 0.0001)
        XCTAssertEqual(reading.fields["IMPEDANCE"], "600.0")

        var live = frame; live[8] = 0x24
        let moving = try XCTUnwrap(OKOKAdvertisement.parse(live))
        XCTAssertFalse(moving.locked)
        XCTAssertTrue(moving.fields.isEmpty)

        var encrypted = frame; encrypted[4] |= 0x80
        XCTAssertFalse(OKOKAdvertisement.recognizes(encrypted))
        XCTAssertNil(OKOKAdvertisement.parse(encrypted))
        for property: UInt8 in [0x45, 0x85] {
            var unsupported = frame; unsupported[8] = property
            XCTAssertFalse(OKOKAdvertisement.recognizes(unsupported))
        }
    }
    // Synthetic layouts, not captured measurements. Last six bytes stand for embedded MAC.
    private func caFrame(version: UInt8, property: UInt8) -> Data {
        var b: [UInt8]
        if version == 0x20 {
            b = [0xCA, version, 11, 0, 0, 0, 1, 1, property, 7, 0x02, 0xF3, 0x13, 0x88, 0,
                 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        } else {
            b = [0xCA, version, 15, property, 0, 0x02, 0xF3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
                 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        }
        let index = Int(b[2]) + 3
        b[index] = b[2..<index].reduce(version == 0x20 ? 0x20 : (0xCA ^ 0x11), ^)
        return Data(b)
    }

    func testCA20LiveAndLockedWithImpedance() throws {
        let live = try XCTUnwrap(OKOKAdvertisement.parse(caFrame(version: 0x20, property: 0)))
        XCTAssertEqual(live.weightKg, 75.5, accuracy: 0.001)
        XCTAssertFalse(live.locked)
        XCTAssertTrue(live.fields.isEmpty)
        let final = try XCTUnwrap(OKOKAdvertisement.parse(caFrame(version: 0x20, property: 1)))
        XCTAssertTrue(final.locked)
        XCTAssertEqual(final.fields["IMPEDANCE"], "500.0")
    }

    func testCA11UsesBroadcastPropertyNotGATTPropertyOffset() throws {
        // Byte 11 is zero even for a locked packet; stable lives at full byte 3.
        let final = try XCTUnwrap(OKOKAdvertisement.parse(caFrame(version: 0x11, property: 1)))
        XCTAssertTrue(final.locked)
        XCTAssertEqual(final.weightKg, 75.5, accuracy: 0.001)
        XCTAssertFalse(try XCTUnwrap(OKOKAdvertisement.parse(caFrame(version: 0x11, property: 0))).locked)
    }

    func testCA11ResolutionAndUnit() throws {
        // Same raw value at two decimals, in pounds, locked.
        let final = try XCTUnwrap(OKOKAdvertisement.parse(caFrame(version: 0x11, property: 0x15)))
        XCTAssertEqual(final.weightKg, 7.55 * 0.45359237, accuracy: 0.00001)
    }

    func testChecksumAndDeclaredLengthAreRequired() {
        for version: UInt8 in [0x11, 0x20] {
            let valid = caFrame(version: version, property: 1)
            for count in 0..<valid.count {
                XCTAssertNil(OKOKAdvertisement.parse(Data(valid.prefix(count))))
            }
            var corrupt = valid; corrupt[5] ^= 1
            XCTAssertFalse(OKOKAdvertisement.recognizes(corrupt))
            XCTAssertNil(OKOKAdvertisement.parse(corrupt))
            var wrongLength = valid; wrongLength[2] += 1
            XCTAssertFalse(OKOKAdvertisement.recognizes(wrongLength))
        }
    }

    func testC0IsStableOnlyWhenPropertySaysSo() throws {
        var b: [UInt8] = [0xC0, 7, 0x02, 0xF3, 0x13, 0x88, 0, 1, 1, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        let final = try XCTUnwrap(OKOKAdvertisement.parse(Data(b)))
        XCTAssertTrue(final.locked)
        XCTAssertEqual(final.weightKg, 75.5, accuracy: 0.001)
        XCTAssertEqual(final.fields["IMPEDANCE"], "500.0")
        b[8] = 0
        let live = try XCTUnwrap(OKOKAdvertisement.parse(Data(b)))
        XCTAssertFalse(live.locked)
        XCTAssertTrue(live.fields.isEmpty)
        b[4] |= 0x80
        XCTAssertFalse(OKOKAdvertisement.recognizes(Data(b)))
        XCTAssertNil(OKOKAdvertisement.parse(Data(b)))
    }

    func testC0StoneUnitAndInvalidWeight() throws {
        var b: [UInt8] = [0xC0, 1, 10, 55, 0, 0, 0, 0, 0x19, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(try XCTUnwrap(OKOKAdvertisement.parse(Data(b))).weightKg,
                       145.5 * 0.45359237, accuracy: 0.00001)
        b[2] = 0; b[3] = 0
        XCTAssertNil(OKOKAdvertisement.parse(Data(b)))
        for count in 0..<15 { XCTAssertFalse(OKOKAdvertisement.recognizes(Data(b.prefix(count)))) }
    }
}
