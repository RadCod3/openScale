// SPDX-License-Identifier: GPL-3.0-or-later
// Based on openScale OkOkHandler and static wire-format observations documented in
// docs/chipsea-ios-protocol.md. Input includes the two CoreBluetooth manufacturer bytes.
import Foundation

public enum OKOKAdvertisement {
    /// Only formats decoded here, not every protocol handled by the vendor app.
    public static func recognizes(_ data: Data) -> Bool {
        let b = Array(data)
        if b.first == 0xC0 {
            // Encrypted C0 needs timestamp-dependent decryption. Never decode it as plain.
            // Real C0 scales can set property bit 5 (e.g. 0x25). It does not
            // change the low-five-bit unit/precision/lock decoding. Keep the
            // separate encryption check and reject unverified bits 6/7.
            return b.count == 15 && b[4] & 0x80 == 0 && b[8] & 0xC0 == 0
        }
        guard b.count >= 10, b[0] == 0xCA, b[1] == 0x20 || b[1] == 0x11 else { return false }
        let length = Int(b[2])
        guard b.count == length + 10 else { return false }
        let checksum = length + 3
        if b[1] == 0x20 {
            guard length >= 11 else { return false }
            return b[2..<checksum].reduce(UInt8(0x20), ^) == b[checksum]
        }
        guard length >= 8 else { return false }
        return b[2..<checksum].reduce(UInt8(0xCA ^ 0x11), ^) == b[checksum]
    }

    public static func parse(_ data: Data) -> ScaleReading? {
        guard recognizes(data) else { return nil }
        let b = Array(data)
        var reading: ScaleReading
        if b[0] == 0xC0 {
            let property = b[8]
            reading = ScaleReading(weightKg: ChipseaProtocol.weight(b[2], b[3], property: property),
                                   locked: property & 1 != 0)
            if reading.locked { addImpedance(b, offset: 4, to: &reading) }
        } else if b[1] == 0x20 {
            let property = b[8]
            reading = ScaleReading(weightKg: ChipseaProtocol.weight(b[10], b[11], property: property),
                                   locked: property & 1 != 0)
            if reading.locked { addImpedance(b, offset: 12, to: &reading) }
        } else {
            // CA11 *broadcast* data area starts at full byte 3. The GATT layout differs.
            let property = b[3]
            reading = ScaleReading(weightKg: ChipseaProtocol.weight(b[5], b[6], property: property),
                                   locked: property & 1 != 0)
        }
        guard reading.weightKg.isFinite, reading.weightKg > 0, reading.weightKg < 1000 else { return nil }
        return reading
    }

    private static func addImpedance(_ b: [UInt8], offset: Int, to reading: inout ScaleReading) {
        let raw = Int(b[offset]) << 8 | Int(b[offset + 1])
        if raw > 0 { reading.fields["IMPEDANCE"] = String(Double(raw) / 10) }
    }
}
