// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreBluetooth
import Combine
import OpenScaleCore

struct NearbyScale: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var services: [String]
    var manufacturer: Data?
    var isBroadcast: Bool {
        guard let data = manufacturer else { return false }
        return OKOKAdvertisement.recognizes(data)
    }
    var isUnsupportedChipseaVariant: Bool {
        guard let manufacturer else { return false }
        let b = Array(manufacturer)
        return (b.count >= 2 && b[0] == 0xFF && b[1] == 0xF0)
            || (b.count == 15 && b[0] == 0xC0 && b[4] & 0x80 != 0)
    }
    var isChipsea: Bool { !isUnsupportedChipseaVariant && name.caseInsensitiveCompare("Chipsea-BLE") == .orderedSame }
    var canMeasure: Bool { isBroadcast || isChipsea }
    var protocolName: String { isBroadcast ? "OKOK broadcast" : (isChipsea ? "Chipsea GATT" : (isUnsupportedChipseaVariant ? "Chipsea variant · diagnostics only" : "Protocol not identified")) }
}

// All delegate callbacks use the main queue configured below.
@MainActor final class ScaleCentral: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var devices: [NearbyScale] = []
    @Published private(set) var status = "Search while your scale is awake."
    @Published private(set) var scanning = false
    @Published private(set) var active = false
    @Published private(set) var reading: ScaleReading?
    @Published private(set) var selectedName: String?
    @Published private(set) var log: [String] = []
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var selected: UUID?
    private var parser = ChipseaProtocol()
    private var profile = Profile()
    private var timeout: Timer?
    private var sessionTimeout: Timer?
    private var tx: CBCharacteristic?
    private var profileSent = false
    private var searchRequested = false
    private var lastManufacturer: [UUID: Data] = [:]
    private let service = CBUUID(string: "FFF0"), rx = CBUUID(string: "FFF1"), write = CBUUID(string: "FFF2")

    override init() { super.init() }
    func startSearch() {
        guard reading?.locked != true else { return }
        stop(); reading = nil; devices = []; peripherals = [:]; lastManufacturer = [:]; log = []
        searchRequested = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { beginScan() }
    }
    private func beginScan() {
        guard searchRequested, reading?.locked != true else { return }
        guard central.state == .poweredOn else { centralManagerDidUpdateState(central); return }
        scanning = true; status = "Step on the scale to wake it, then select it below."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.active else { return }
                self.central.stopScan(); self.scanning = false; self.searchRequested = false
                self.status = self.devices.isEmpty ? "No devices found. Wake the scale and search again." : "Search finished. Select your scale or search again."
            }
        }
    }
    func select(_ device: NearbyScale, profile: Profile) {
        guard device.canMeasure else { return }
        timeout?.invalidate(); sessionTimeout?.invalidate()
        if let connected { central.cancelPeripheralConnection(connected) }
        connected = nil; tx = nil; profileSent = false; parser.reset(); reading = nil
        self.profile = profile; selected = device.id; selectedName = device.name; active = true
        status = "Step on the scale and stay still."
        record("Selected \(device.name), \(device.protocolName)")
        sessionTimeout = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.status = "No final reading received. Wake the scale and try again; export diagnostics if it persists." }
        }
        if device.isBroadcast {
            // Keep scanning: cached data may belong to a previous weigh-in.
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            scanning = true
        } else if let p = peripherals[device.id] {
            central.stopScan(); scanning = false; connected = p; p.delegate = self
            status = "Connecting to \(device.name)…"; central.connect(p)
        }
    }
    func stop() {
        timeout?.invalidate(); sessionTimeout?.invalidate()
        if let connected { central?.cancelPeripheralConnection(connected) }
        connected = nil; tx = nil; profileSent = false; selected = nil; active = false
        central?.stopScan(); scanning = false; parser.reset()
        searchRequested = false
        if reading?.locked != true { status = "Session stopped. Search again when you're ready." }
    }
    func clearReading() { reading = nil }
    private func record(_ text: String) {
        if log.count >= 250 { log.removeFirst() }
        log.append(text)
    }
    func diagnostics() -> String {
        (["openScale iOS protocol diagnostics", "Contains nearby device identifiers and Bluetooth packets; review before sharing."] + log).joined(separator: "\n")
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if searchRequested && !scanning && !active { beginScan() }
        case .poweredOff: stop(); status = "Bluetooth is off. Turn it on in Settings, then search again."
        case .unauthorized: stop(); status = "Bluetooth access is denied. Allow openScale in Settings → Privacy & Security → Bluetooth."
        case .unsupported: stop(); status = "Bluetooth is unavailable here. Use a physical iPhone to test your scale."
        case .resetting: stop(); status = "Bluetooth is restarting. Search again in a moment."
        default: status = "Waiting for Bluetooth…"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let previous = devices.first { $0.id == peripheral.identifier }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? previous?.name ?? "Unnamed device"
        let receivedManufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let manufacturer = receivedManufacturer ?? previous?.manufacturer
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? previous?.services ?? []
        let device = NearbyScale(id: peripheral.identifier, name: name, rssi: RSSI.intValue, services: services, manufacturer: manufacturer)
        peripherals[device.id] = peripheral
        if let i = devices.firstIndex(where: { $0.id == device.id }) { devices[i] = device }
        else if devices.count < 100 { devices.append(device); record("Device \(device.id) name=\(name) services=\(services.joined(separator: ","))") }
        if let manufacturer, lastManufacturer[device.id] != manufacturer {
            lastManufacturer[device.id] = manufacturer
            record("ADV \(device.id) \(manufacturer.hex)")
        }
        guard device.id == selected, device.isBroadcast, let receivedManufacturer,
              let value = OKOKAdvertisement.parse(receivedManufacturer) else { return }
        accept(value)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == selected else { return }
        status = "Reading scale services…"; peripheral.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selected else { return }
        stop(); status = "Could not connect. Wake the scale and try again."
        record("Connect error: \(error?.localizedDescription ?? "unknown")")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selected else { return }
        stop(); status = "Scale disconnected. Start a new search to retry."
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == selected else { return }
        guard error == nil, let s = peripheral.services?.first(where: { $0.uuid == service }) else {
            stop(); status = "This scale does not expose the expected Chipsea service. Export diagnostics to identify its protocol."; return
        }
        peripheral.discoverCharacteristics([rx, write], for: s)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == selected else { return }
        guard error == nil, let notify = service.characteristics?.first(where: { $0.uuid == rx }),
              let writeChar = service.characteristics?.first(where: { $0.uuid == write }),
              !notify.properties.intersection([.notify, .indicate]).isEmpty,
              !writeChar.properties.intersection([.write, .writeWithoutResponse]).isEmpty else {
            stop(); status = "Expected Chipsea characteristics are missing. Export diagnostics for protocol analysis."; return
        }
        tx = writeChar; peripheral.setNotifyValue(true, for: notify)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected else { return }
        guard error == nil, characteristic.isNotifying else { stop(); status = "Could not subscribe to measurements. Try again."; return }
        sendProfile(peripheral)
    }
    private func sendProfile(_ peripheral: CBPeripheral) {
        guard let tx, !profileSent else { return }
        let type: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
        let data = ChipseaProtocol.userSync(profile: profile)
        guard data.count <= peripheral.maximumWriteValueLength(for: type) else { stop(); status = "Scale write size is unsupported."; return }
        profileSent = true
        peripheral.writeValue(data, for: tx, type: type); record("Sent Chipsea user/time sync (profile bytes omitted)")
        status = "Step on the scale and stay still."
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral.identifier == selected else { return }; sendProfile(peripheral)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected, let error else { return }
        stop(); status = "Scale setup failed: \(error.localizedDescription)"
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected, characteristic.uuid == rx, error == nil, let data = characteristic.value else { return }
        record("RX \(characteristic.uuid.uuidString) \(data.hex)")
        if let value = parser.feed(data) { accept(value) }
    }
    private func accept(_ value: ScaleReading) {
        reading = value
        if value.locked { stop(); status = "Measurement captured. Review and save it below." }
        else { status = "Measuring… stay still until the weight settles." }
    }
}

private extension Data { var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") } }
