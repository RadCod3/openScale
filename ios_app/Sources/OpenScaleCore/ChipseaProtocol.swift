// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from openScale ChipseaBleLib.kt, copyright 2026 openScale contributors.
import Foundation

/// Chipsea-BLE FFF0 / FFF1 notify / FFF2 write. Live and locked readings are distinct.
public struct ChipseaProtocol: Sendable {
    private var chunks: [Int: [UInt8]] = [:]
    private var chunkTotal = 0
    public init() {}

    public mutating func reset() { chunks.removeAll(); chunkTotal = 0 }

    public mutating func feed(_ data: Data) -> ScaleReading? {
        let b = Array(data)
        guard b.count >= 4, b[0] == 0xCA else { return nil }
        if b[1] == 0x10 {
            guard b.count >= 7 else { return nil }
            return reading(b, property: b[4], weightOffset: 5, compositionOffset: 7)
        }
        guard b[1] == 0x11 else { return nil }
        if b[3] == 0 || b[3] == 1 {
            guard b.count >= 12 else { return nil }
            return valid(ScaleReading(weightKg: Self.weight(b[5], b[6], property: b[11]), locked: b[3] == 1))
        }
        // Only live records: history needs explicit user mapping before it can be imported.
        guard b[3] == 18, b.count >= 5, b[2] >= 2 else { return nil }
        let size = Int(b[2]) - 2, index = Int(b[4] >> 4), total = Int(b[4] & 15)
        guard total > 0, index > 0, index <= total, b.count >= size + 5 else { reset(); return nil }
        if index == 1 { reset(); chunkTotal = total }
        guard chunkTotal == total else { reset(); return nil }
        chunks[index] = Array(b[5..<(5 + size)])
        guard index == total else { return nil }
        defer { reset() }
        guard chunks.count == total, (1...total).allSatisfy({ chunks[$0] != nil }) else { return nil }
        let payload = (1...total).flatMap { chunks[$0]! }
        guard payload.count >= 23 else { return nil }
        return reading(payload, property: payload[4], weightOffset: 10, compositionOffset: 12)
    }

    private func reading(_ b: [UInt8], property: UInt8, weightOffset: Int, compositionOffset: Int) -> ScaleReading? {
        var r = ScaleReading(weightKg: Self.weight(b[weightOffset], b[weightOffset + 1], property: property), locked: property & 1 != 0)
        if r.locked, b.count >= compositionOffset + 11 {
            let names = ["BODY_FAT", "WATER", "MUSCLE", "BMR", "VISCERAL_FAT"]
            for (i, name) in names.enumerated() {
                let n = Self.u16(b, compositionOffset + i * 2)
                if n > 0 { r.fields[name] = String(Double(n) / (name == "BMR" ? 1 : 10)) }
            }
            if b[compositionOffset + 10] > 0 { r.fields["BONE"] = String(Double(b[compositionOffset + 10]) / 10) }
        }
        return valid(r)
    }
    private func valid(_ r: ScaleReading) -> ScaleReading? {
        r.weightKg.isFinite && r.weightKg > 0 && r.weightKg < 1000 ? r : nil
    }
    private static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    public static func weight(_ high: UInt8, _ low: UInt8, property: UInt8) -> Double {
        let unit = (property >> 3) & 3
        if unit == 3 { return (Double(high) * 14 + Double(low) / 10) * 0.45359237 }
        let digits = (property >> 1) & 3
        let divisor: Double = digits == 1 ? 1 : (digits == 2 ? 100 : 10)
        let value = Double(Int(high) << 8 | Int(low)) / divisor
        return value * (unit == 1 ? 0.5 : (unit == 2 ? 0.45359237 : 1))
    }
    public static func userSync(profile: Profile, now: Date = Date(), timeZone: TimeZone = .current) -> Data {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        var b: [UInt8] = [0xCA, 0x10, 14, 1,
                          UInt8((c.year ?? 2000) % 100), UInt8(c.month ?? 1), UInt8(c.day ?? 1),
                          UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0),
                          0, 0, 0, 1, profile.isMale ? 1 : 0,
                          UInt8(clamping: profile.age), UInt8(clamping: profile.heightCm), 0, 0, 0]
        b[17] = b[1...16].reduce(0, ^)
        return Data(b)
    }
}

