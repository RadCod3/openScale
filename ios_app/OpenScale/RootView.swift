// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Charts
import UniformTypeIdentifiers
import OpenScaleCore

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView {
            JournalView().tabItem { Label("Journal", systemImage: "chart.xyaxis.line") }
            ScaleView().tabItem { Label("Weigh in", systemImage: "scalemass") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct JournalView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                if let notice = model.notice {
                    Section { Text(notice).foregroundStyle(.secondary) }
                }
                if model.measurements.isEmpty {
                    ContentUnavailableView {
                        Label("Your first measurement", systemImage: "scalemass")
                    } description: {
                        Text("Take a weigh-in with your scale, add a measurement, or bring your history from openScale on Android.")
                    } actions: {
                        Button("Add measurement") { adding = true }.buttonStyle(.borderedProminent)
                    }.listRowBackground(Color.clear)
                } else {
                    if model.measurements.count > 1 {
                        Section("Weight over time · \(model.unit.rawValue)") {
                            Chart(model.measurements.sorted { $0.date < $1.date }) { m in
                                LineMark(x: .value("Date", m.date), y: .value("Weight", model.unit.display(m.weightKg)))
                                PointMark(x: .value("Date", m.date), y: .value("Weight", model.unit.display(m.weightKg)))
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis(typeSize.isAccessibilitySize ? .hidden : .automatic)
                            .chartYAxis(typeSize.isAccessibilitySize ? .hidden : .automatic)
                            .frame(height: 200)
                            .accessibilityLabel("Weight history in \(model.unit.rawValue)")
                        }
                    }
                    Section("Measurements") {
                        ForEach(model.measurements) { m in
                            NavigationLink { MeasurementDetail(measurement: m) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if typeSize.isAccessibilitySize {
                                        weightLabel(m)
                                        Text(m.source).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        HStack(alignment: .firstTextBaseline) {
                                            weightLabel(m)
                                            Spacer()
                                            Text(m.source).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.delete(m) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("openScale")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add measurement", systemImage: "plus") { adding = true } } }
            .sheet(isPresented: $adding) { MeasurementEditor() }
        }
    }
    private func weightLabel(_ m: WeighIn) -> some View {
        Text("\(model.unit.display(m.weightKg).formatted(.number.precision(.fractionLength(1...2)))) \(model.unit.rawValue)")
            .font(.title2.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
}

struct MeasurementDetail: View {
    @EnvironmentObject private var model: AppModel
    let measurement: WeighIn
    var body: some View {
        List {
            Section {
                LabeledContent("Weight", value: "\(model.unit.display(measurement.weightKg).formatted(.number.precision(.fractionLength(1...2)))) \(model.unit.rawValue)")
                LabeledContent("Date", value: measurement.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Source", value: measurement.source)
                if model.profileConfigured, let bmi = measurement.bmi(heightCm: model.profile.heightCm) {
                    LabeledContent("BMI (current height)", value: bmi.formatted(.number.precision(.fractionLength(1))))
                }
            }
            if !measurement.fields.isEmpty {
                Section {
                    ForEach(measurement.fields.keys.sorted(), id: \.self) { key in
                        LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: measurement.fields[key] ?? "")
                    }
                } header: { Text("Additional values") } footer: { Text("CSV values retain their original units. Scale composition values are estimates reported by the device.") }
            }
        }.navigationTitle("Measurement").navigationBarTitleDisplayMode(.inline)
    }
}

struct MeasurementEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var date = Date()
    @State private var comment = ""
    private var kilograms: Double? {
        // Locale-aware decimal input; grouping is intentionally not accepted.
        let separator = Locale.current.decimalSeparator ?? "."
        guard let n = Double(weight.replacingOccurrences(of: separator, with: ".")), n.isFinite else { return nil }
        let kg = model.unit.kilograms(n); return kg > 0 && kg < 1000 ? kg : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Text("Weight (\(model.unit.rawValue))"); TextField("0.0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("Weight in \(model.unit.rawValue)") }
                    DatePicker("Date", selection: $date, in: ...Date())
                    TextField("Comment (optional)", text: $comment, axis: .vertical)
                } footer: { Text("Saved on this iPhone. Change weight units in Settings.") }
            }
            .navigationTitle("Add measurement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let kg = kilograms else { return }
                        if model.save(WeighIn(date: date, weightKg: kg, fields: comment.isEmpty ? [:] : ["COMMENT": comment])) { dismiss() }
                    }.disabled(kilograms == nil)
                }
            }
        }
    }
}

struct ScaleView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var bluetooth = ScaleCentral()
    @State private var profileSheet = false
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(bluetooth.phase.rawValue, systemImage: bluetooth.phase.symbol).font(.headline)
                        Text(bluetooth.status).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    if bluetooth.scanning || bluetooth.active {
                        Button("Stop") { bluetooth.stop() }
                    } else {
                        Button(bluetooth.rememberedScale == nil ? "Search for my scale" : "Listen for your scale", systemImage: "magnifyingglass") { bluetooth.startSearch() }
                            .disabled(bluetooth.reading?.locked == true)
                    }
                } header: { Text("\(model.profileConfigured ? model.profile.name : "Your") weigh-in") }
                  footer: { Text(bluetooth.rememberedScale == nil ? "Keep this screen open. Wake your scale, select it once, then stand still." : "Your scale is remembered. Opening this screen listens for it automatically. Keep the app in the foreground.") }
                if let saved = model.lastAutomaticMeasurement {
                    Section("Saved automatically") {
                        LabeledContent("Weight", value: weightText(saved.weightKg))
                        Text(saved.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Button("Undo automatic save", systemImage: "arrow.uturn.backward") {
                            if model.undoAutomaticSave() { bluetooth.markUndone() }
                        }
                    }
                }
                if let reading = bluetooth.reading {
                    Section(reading.locked ? "Measurement captured" : "Live weight") {
                        LabeledContent("Weight", value: weightText(reading.weightKg))
                        ForEach(reading.fields.keys.sorted(), id: \.self) { key in
                            LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: reading.fields[key] ?? "")
                        }
                        if reading.locked {
                            Button("Save measurement", systemImage: "checkmark") {
                                guard let m = bluetooth.capturedMeasurement else { return }
                                if model.save(m) { bluetooth.markSaved() }
                            }
                            Button("Discard", role: .destructive) { bluetooth.clearReading() }
                        }
                    }
                }
                if let remembered = bluetooth.rememberedScale {
                    Section("Your scale") {
                        Label(remembered.name, systemImage: "scalemass")
                        Button("Change scale") { bluetooth.changeScale() }.disabled(bluetooth.reading?.locked == true)
                    }
                } else if !bluetooth.devices.isEmpty {
                    Section("Nearby devices") {
                        ForEach(bluetooth.devices.sorted { a, b in a.canMeasure != b.canMeasure ? a.canMeasure : a.rssi > b.rssi }) { device in
                            Button {
                                if device.isChipsea && !device.isBroadcast && !model.profileConfigured { profileSheet = true }
                                else { bluetooth.select(device, profile: model.profile) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.displayName).foregroundStyle(.primary)
                                    Text(device.protocolName).font(.subheadline).foregroundStyle(.secondary)
                                    if !device.services.isEmpty { Text("Services: \(device.services.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 4)
                            }.disabled(!device.canMeasure || bluetooth.active || bluetooth.reading?.locked == true)
                        }
                    }
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-scale") {
                    Button("Simulate weigh-in") { bluetooth.simulateTestReading(liveFirst: true) }
                    Button("Replay final packet") { bluetooth.simulateTestReading(liveFirst: false) }
                }
                #endif
                Section {
                    ShareLink(item: bluetooth.diagnostics()) { Label("Share Bluetooth diagnostics", systemImage: "square.and.arrow.up") }
                        .disabled(bluetooth.log.isEmpty)
                } footer: { Text("Experimental Chipsea / OKOK support. If your scale is unidentified, share diagnostics from a weigh-in to identify its protocol. Diagnostics include nearby device identifiers and packets; review before sharing.") }
            }
            .navigationTitle("Weigh in")
            .sheet(isPresented: $profileSheet) { ProfileEditor() }
            .onAppear {
                isVisible = true
                bluetooth.onCapture = { [model] measurement in model.saveAutomatically(measurement) }
                bluetooth.resumeRemembered(profile: model.profile, profileConfigured: model.profileConfigured)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { bluetooth.stop() }
                else if isVisible { bluetooth.resumeRemembered(profile: model.profile, profileConfigured: model.profileConfigured) }
            }
            .onDisappear { isVisible = false; bluetooth.stop() }
        }
    }
    private func weightText(_ kilograms: Double) -> String {
        "\(model.unit.display(kilograms).formatted(.number.precision(.fractionLength(1...2)))) \(model.unit.rawValue)"
    }
}

struct ProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile = Profile()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $profile.name)
                    Stepper("Height: \(profile.heightCm) cm", value: $profile.heightCm, in: 50...250)
                    Stepper("Age: \(profile.age)", value: $profile.age, in: 6...120)
                    Picker("Scale sex setting", selection: $profile.isMale) {
                        Text("Female").tag(false); Text("Male").tag(true)
                    }
                } footer: { Text("Chipsea scales use age, height and a binary sex setting for body composition estimates. Confirm these values before connecting. This prototype stores one person's history.") }
            }
            .navigationTitle("Your profile").navigationBarTitleDisplayMode(.inline)
            .onAppear { profile = model.profile }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { model.saveProfile(profile); dismiss() }.disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var profileSheet = false
    @State private var importing = false
    @State private var exporting = false
    @State private var importText: String?
    @State private var importUnit: WeightUnit = .kg
    @State private var importPreview: CSVImport?
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal") {
                    Button(model.profileConfigured ? model.profile.name : "Set up your profile") { profileSheet = true }
                    Picker("Weight unit", selection: $model.unit) {
                        ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section {
                    Toggle("Save settled readings automatically", isOn: $model.automaticallySaveReadings)
                } header: { Text("Weigh-in") } footer: { Text("When enabled, final Bluetooth readings are saved to your journal with an Undo option. Moving readings are never saved. Leave this off to review each reading before saving.") }
                Section {
                    Button("Import Android CSV", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Export measurements", systemImage: "square.and.arrow.up") { exporting = true }.disabled(model.measurements.isEmpty)
                } header: { Text("Your data") } footer: { Text("Exports use kilograms for weight; other fields keep their imported values. History stays on this device. Automatic device backup is disabled for the measurement database; export a CSV to keep a copy.") }
                if let text = importText {
                    Section {
                        Picker("Weight unit in source file", selection: $importUnit) {
                            ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.onChange(of: importUnit) { _, _ in updatePreview(text) }
                        if let preview = importPreview {
                            Text("\(preview.measurements.count) measurements ready · \(preview.skippedRows.count) invalid rows")
                            if let sample = preview.measurements.first {
                                LabeledContent("First weight", value: "\(sample.weightKg.formatted(.number.precision(.fractionLength(2)))) kg")
                            }
                            if !preview.skippedRows.isEmpty { Text("Invalid CSV rows: \(preview.skippedRows.prefix(20).map(String.init).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                            Button("Import \(preview.measurements.count) measurements") {
                                model.importCSV(preview); importText = nil; importPreview = nil
                            }.disabled(preview.measurements.isEmpty)
                        }
                        Button("Cancel import", role: .cancel) { importText = nil; importPreview = nil }
                    } header: { Text("Review import") } footer: { Text("Choose the unit used by Android. CSV dates use this iPhone's current time zone. Missing times become noon. Existing timestamps are preserved; duplicates are skipped. Extra columns are retained.") }
                }
                if let notice = model.notice { Section { Text(notice).foregroundStyle(.secondary) } }
                Section("About") {
                    LabeledContent("Version", value: "Native prototype · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")")
                    Text("openScale is free software under GPLv3 or later. No account or cloud service is required. Scale support is experimental until verified on hardware.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $profileSheet) { ProfileEditor() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                do {
                    let url = try result.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) < 10_000_000 else { throw ImportFailure.tooLarge }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    importText = text; importUnit = model.unit; updatePreview(text)
                } catch { model.problem = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: CSVDocument(text: MeasurementCSV.export(model.measurements)), contentType: .commaSeparatedText, defaultFilename: "openScale-kg") { result in
                if case .failure(let error) = result { model.problem = error.localizedDescription }
            }
        }
    }
    private func updatePreview(_ text: String) {
        do { importPreview = try MeasurementCSV.parse(text, weightUnit: importUnit) }
        catch { importPreview = nil; model.problem = error.localizedDescription }
    }
}

private enum ImportFailure: LocalizedError {
    case tooLarge
    var errorDescription: String? { "This prototype accepts CSV files up to 10 MB. Export a smaller date range and retry." }
}
