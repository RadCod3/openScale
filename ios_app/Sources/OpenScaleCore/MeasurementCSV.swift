// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum CSVError: LocalizedError {
    case malformed, missingColumns, duplicateHeaders
    public var errorDescription: String? {
        switch self {
        case .malformed: "The CSV contains an unfinished or misplaced quote. Export it again and retry."
        case .missingColumns: "The CSV needs DATE (or dateTime) and WEIGHT columns."
        case .duplicateHeaders: "The CSV contains repeated column names. Rename them before importing."
        }
    }
}

public struct CSVImport: Sendable {
    public var measurements: [Measurement]
    public var skippedRows: [Int]
}

public enum MeasurementCSV {
    /// RFC 4180 quoting, embedded newlines, CRLF, BOM, and escaped quotes.
    public static func rows(_ text: String) throws -> [[String]] {
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var result: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false, i = 0
        func finishRow() {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) { result.append(row) }
            row = []; field = ""; closed = false
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" { finishRow() }
            else if c == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed, c != "\"" else { throw CSVError.malformed }
                field.append(c)
            }
            i += 1
        }
        guard !quoted else { throw CSVError.malformed }
        if !field.isEmpty || !row.isEmpty || closed { finishRow() }
        if !result.isEmpty, !result[0].isEmpty { result[0][0] = result[0][0].replacingOccurrences(of: "\u{FEFF}", with: "") }
        return result
    }

    /// Android CSV does not encode units or timezone: callers must choose both explicitly.
    public static func parse(_ text: String, weightUnit: WeightUnit, timeZone: TimeZone = .current) throws -> CSVImport {
        let rows = try rows(text)
        guard let first = rows.first else { throw CSVError.missingColumns }
        let headers = first.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        guard Set(headers).count == headers.count else { throw CSVError.duplicateHeaders }
        guard let weightIndex = headers.firstIndex(of: "WEIGHT"), headers.contains("DATE") || headers.contains("DATETIME") else { throw CSVError.missingColumns }
        var measurements: [Measurement] = [], skipped: [Int] = []
        for (index, row) in rows.dropFirst().enumerated() {
            func value(_ key: String) -> String? {
                guard let i = headers.firstIndex(of: key), row.indices.contains(i) else { return nil }
                return row[i]
            }
            let dateString = value("DATETIME").flatMap { $0.isEmpty ? nil : $0 }
                ?? ((value("DATE") ?? "") + " " + ((value("TIME")?.isEmpty == false ? value("TIME") : nil) ?? "12:00:00"))
            guard row.count == headers.count, row.indices.contains(weightIndex),
                  let raw = Double(row[weightIndex]), raw.isFinite,
                  let date = parseDate(dateString, timeZone: timeZone) else { skipped.append(index + 2); continue }
            let kg = weightUnit.kilograms(raw)
            guard kg > 0, kg < 1000 else { skipped.append(index + 2); continue }
            var fields: [String: String] = [:]
            for (i, key) in headers.enumerated() where !["DATE", "TIME", "DATETIME", "WEIGHT"].contains(key) {
                if !row[i].isEmpty { fields[key] = row[i] }
            }
            measurements.append(Measurement(date: date, weightKg: kg, fields: fields, source: "CSV (\(weightUnit.rawValue))"))
        }
        return CSVImport(measurements: measurements, skippedRows: skipped)
    }

    private static func parseDate(_ text: String, timeZone: TimeZone) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = timeZone; f.isLenient = false
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let base = String(parts[0])
        var fraction: Double = 0
        if parts.count == 2 {
            guard (1...9).contains(parts[1].count), parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Double("0." + parts[1]) else { return nil }
            fraction = value
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = format
            if let date = f.date(from: base), f.string(from: date) == base { return date.addingTimeInterval(fraction) }
        }
        return nil
    }
    public static func export(_ measurements: [Measurement], timeZone: TimeZone = .current) -> String {
        let reserved: Set<String> = ["DATE", "TIME", "DATETIME", "WEIGHT"]
        let extras = Set(measurements.flatMap { $0.fields.keys }).subtracting(reserved).sorted()
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = Calendar(identifier: .gregorian); date.timeZone = timeZone; date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter(); time.locale = date.locale; time.calendar = date.calendar
        time.timeZone = timeZone; time.dateFormat = "HH:mm:ss.SSS"
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = [["DATE", "TIME", "WEIGHT"] + extras]
        rows += measurements.sorted { $0.date < $1.date }.map { m in
            [date.string(from: m.date), time.string(from: m.date), String(m.weightKg)] + extras.map { m.fields[$0] ?? "" }
        }
        return rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
