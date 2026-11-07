// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct RememberedScale: Codable, Equatable, Sendable {
    public let peripheralID: UUID
    public let name: String
    public let broadcastIdentity: Data?

    public init(peripheralID: UUID, name: String, manufacturerData: Data?) {
        self.peripheralID = peripheralID
        self.name = name == "Unnamed device" || name.isEmpty ? "Your OKOK scale" : name
        broadcastIdentity = Self.identity(in: manufacturerData)
    }
    public func matches(peripheralID: UUID, manufacturerData: Data?) -> Bool {
        // An embedded identity survives changes to CoreBluetooth's local UUID.
        if let broadcastIdentity, let incoming = Self.identity(in: manufacturerData) {
            return broadcastIdentity == incoming
        }
        return self.peripheralID == peripheralID
    }
    private static func identity(in data: Data?) -> Data? {
        guard let data, OKOKAdvertisement.recognizes(data) else { return nil }
        let suffix = Data(data.suffix(6))
        guard suffix.contains(where: { $0 != 0 }), suffix.contains(where: { $0 != 0xFF }) else { return nil }
        // Include protocol version, since unrelated protocols can reuse tail bytes.
        return Data(data.prefix(data.first == 0xC0 ? 1 : 2)) + suffix
    }
    public var key: String { broadcastIdentity?.base64EncodedString() ?? peripheralID.uuidString }
}

/// A repeated final broadcast is one weigh-in. A new moving-weight sequence can
/// start a genuine new weigh-in even if the resulting weight is identical.
public struct FinalReadingGate: Sendable {
    public struct Receipt: Codable, Sendable {
        let device: String
        let weightKg: Double
        let fields: [String: String]
        let capturedAt: Date
    }
    public private(set) var receipt: Receipt?
    private var liveDevices: Set<String> = []
    public init(receipt: Receipt? = nil) { self.receipt = receipt }

    public mutating func allows(_ reading: ScaleReading, device: String, now: Date = Date()) -> Bool {
        guard reading.locked else { liveDevices.insert(device); return true }
        let sawLive = liveDevices.remove(device) != nil
        if !sawLive, let receipt, receipt.device == device,
           abs(now.timeIntervalSince(receipt.capturedAt)) < 120,
           abs(receipt.weightKg - reading.weightKg) < 0.0001,
           receipt.fields == reading.fields { return false }
        receipt = Receipt(device: device, weightKg: reading.weightKg, fields: reading.fields, capturedAt: now)
        return true
    }
}
