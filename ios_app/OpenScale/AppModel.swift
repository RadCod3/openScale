// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import OpenScaleCore

typealias WeighIn = OpenScaleCore.Measurement

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var measurements: [WeighIn] = []
    @Published var problem: String?
    @Published var notice: String?
    @Published var profile = Profile()
    @Published var profileConfigured = false
    @Published var unit: WeightUnit = .kg {
        didSet { if storesPreferences { UserDefaults.standard.set(unit.rawValue, forKey: "weightUnit") } }
    }
    private var storesPreferences = true
    private var store: MeasurementStore?
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            storesPreferences = false
            do {
                store = try MeasurementStore(path: ":memory:")
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed") {
                    let date = Date(timeIntervalSince1970: 1_794_009_600)
                    try store?.insert((0..<5).map { i in WeighIn(date: date.addingTimeInterval(Double(i) * 86400), weightKg: 76 - Double(i) * 0.25, source: "Test fixture") })
                }
                try reload()
            } catch { problem = error.localizedDescription }
            return
        }
        #endif
        unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit") ?? "kg") ?? .kg
        if let data = UserDefaults.standard.data(forKey: "profile"), let saved = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = saved; profileConfigured = true
        }
        do {
            let fm = FileManager.default
            var directory = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("openScale", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            store = try MeasurementStore(path: directory.appendingPathComponent("measurements.sqlite").path)
            try reload()
        } catch { problem = error.localizedDescription }
    }
    func saveProfile(_ value: Profile) {
        do {
            let data = try JSONEncoder().encode(value)
            if storesPreferences { UserDefaults.standard.set(data, forKey: "profile") }
            profile = value; profileConfigured = true
        } catch { problem = error.localizedDescription }
    }
    func save(_ m: WeighIn) -> Bool {
        do {
            guard let store else { throw StoreError.database("Storage is unavailable. Restart the app and retry.") }
            let count = try store.insert([m]); try reload()
            notice = count == 1 ? "Measurement saved." : "A measurement at this time already exists."
            return count == 1
        } catch { problem = error.localizedDescription; return false }
    }
    func delete(_ m: WeighIn) {
        do { try store?.delete(id: m.id); try reload() } catch { problem = error.localizedDescription }
    }
    func importCSV(_ result: CSVImport) {
        do {
            guard let store else { throw StoreError.database("Storage is unavailable.") }
            let count = try store.insert(result.measurements); try reload()
            notice = "Imported \(count). Skipped \(result.measurements.count - count) duplicates and \(result.skippedRows.count) invalid rows."
        } catch { problem = error.localizedDescription }
    }
    private func reload() throws { measurements = try store?.all() ?? [] }
}
