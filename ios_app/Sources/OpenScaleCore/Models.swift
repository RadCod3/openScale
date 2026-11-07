// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg, lb, st
    public var kilogramsPerUnit: Double {
        switch self { case .kg: 1; case .lb: 0.45359237; case .st: 6.35029318 }
    }
    public func kilograms(_ value: Double) -> Double { value * kilogramsPerUnit }
    public func display(_ kilograms: Double) -> Double { kilograms / kilogramsPerUnit }
}

public struct Profile: Codable, Equatable, Sendable {
    public var name = "Me"
    public var heightCm: Int = 170
    public var age: Int = 30
    public var isMale = false
    public init() {}
}

public struct Measurement: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var weightKg: Double
    /// CSV fields retain their original identities and non-weight values.
    public var fields: [String: String]
    public var source: String
    public init(id: UUID = UUID(), date: Date = Date(), weightKg: Double,
                fields: [String: String] = [:], source: String = "Manual") {
        self.id = id
        // Android timestamps and CSV interchange use milliseconds. One precision keeps
        // export/reimport idempotent even for native Date() readings.
        self.date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.weightKg = weightKg
        self.fields = fields; self.source = source
    }
    public func bmi(heightCm: Int) -> Double? {
        guard heightCm > 0 else { return nil }
        return weightKg / pow(Double(heightCm) / 100, 2)
    }
}

public struct ScaleReading: Equatable, Sendable {
    public var weightKg: Double
    public var locked: Bool
    public var fields: [String: String] = [:]
    public var date: Date? = nil
    public init(weightKg: Double, locked: Bool, fields: [String: String] = [:], date: Date? = nil) {
        self.weightKg = weightKg; self.locked = locked; self.fields = fields; self.date = date
    }
}
