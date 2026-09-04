import Foundation
import Combine
import UIKit
@preconcurrency import CoreBluetooth

private func thermalLimitIsActive() -> Bool {
    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical: return true
    default: return false
    }
}

enum Haptics {
    @MainActor static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

@MainActor
final class BLEScanner: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    @Published private(set) var sources: [BLESource] = []
    @Published private(set) var bluetoothState = "正在初始化"
    @Published private(set) var isRunning = false
    @Published private(set) var isActivelyScanning = false
    @Published private(set) var callbacksPerSecond = 0.0
    @Published private(set) var activeSourceCount = 0
    @Published private(set) var isSystemLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var isThermallyLimited = thermalLimitIsActive()
    @Published private(set) var userSettings = UserSettings.defaults

    let observations: AsyncStream<BLEObservation>

    private var continuation: AsyncStream<BLEObservation>.Continuation
    private var central: CBCentralManager!
    private let registry = BLESourceRegistry()
    private var callbackTimes: [Date] = []
    private var maintenanceTimer: Timer?
    private var dutyTask: Task<Void, Never>?
    private var lastPublish = Date.distantPast

    private var profile: ScanProfile {
        TuningConfig.profile(settings: userSettings, forcedEco: conservationForced)
    }

    var conservationForced: Bool {
        (userSettings.automaticLowPower && isSystemLowPowerMode) ||
        (userSettings.automaticThermalProtection && isThermallyLimited)
    }
    var isUsingUltraEco: Bool { conservationForced || userSettings.mode == .ultraEco }
    var conservationReason: String {
        userSettings.automaticThermalProtection && isThermallyLimited
            ? "设备温度较高，已自动降低负载" : "已跟随系统低电量模式"
    }
    var effectiveProfileSummary: String {
        let refresh = String(format: "%.2f", profile.refreshInterval)
        if let scan = profile.scanSeconds, let pause = profile.pauseSeconds {
            return "扫描\(scan)秒 / 休眠\(pause)秒 · UI刷新\(refresh)秒"
        }
        return "连续扫描 · UI刷新\(refresh)秒 · 最多\(profile.maxSources)个源"
    }

    override init() {
        let channel = AsyncStream<BLEObservation>.makeStream(bufferingPolicy: .bufferingNewest(256))
        observations = channel.stream
        continuation = channel.continuation
        if let data = UserDefaults.standard.data(forKey: "userSettings"),
           var saved = try? JSONDecoder().decode(UserSettings.self, from: data) {
            saved.normalize()
            userSettings = saved
        }
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.maintain() }
        }
        timer.tolerance = 0.2
        maintenanceTimer = timer
    }

    deinit { continuation.finish() }

    func toggle() {
        if userSettings.hapticsEnabled { Haptics.tap(isRunning ? .light : .medium) }
        isRunning ? stop() : start()
    }

    func setMode(_ newMode: PowerMode) {
        updateSetting(\.mode, to: newMode)
        if userSettings.hapticsEnabled { Haptics.tap(.light) }
    }

    func updateSetting<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>, to value: Value) {
        let previousProfile = profile
        var next = userSettings
        next[keyPath: keyPath] = value
        next.normalize()
        guard next != userSettings else { return }
        userSettings = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: "userSettings")
        }
        if isRunning, previousProfile != profile { activateProfile() }
    }

    func resetSettings() {
        userSettings = .defaults
        UserDefaults.standard.removeObject(forKey: "userSettings")
        if userSettings.hapticsEnabled { Haptics.tap(.medium) }
        if isRunning { activateProfile() }
    }

    func start() {
        guard !isRunning else { return }
        registry.reset()
        callbackTimes.removeAll(keepingCapacity: true)
        sources = []
        activeSourceCount = 0
        lastPublish = .distantPast
        isSystemLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        isThermallyLimited = thermalLimitIsActive()
        isRunning = true
        activateProfile()
    }

    func stop() {
        isRunning = false
        dutyTask?.cancel()
        dutyTask = nil
        central.stopScan()
        isActivelyScanning = false
        callbacksPerSecond = 0
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothState = "蓝牙就绪"
        case .poweredOff: bluetoothState = "蓝牙已关闭"
        case .unauthorized: bluetoothState = "未授权蓝牙"
        case .unsupported: bluetoothState = "设备不支持"
        case .resetting: bluetoothState = "蓝牙重置中"
        case .unknown: bluetoothState = "等待蓝牙"
        @unknown default: bluetoothState = "蓝牙状态未知"
        }
        if central.state == .poweredOn, isRunning { activateProfile() }
        if central.state != .poweredOn {
            dutyTask?.cancel()
            central.stopScan()
            isActivelyScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let value = RSSI.intValue
        guard (-110 ... -20).contains(value), value != 0, value != 127 else { return }
        let sample = BLEObservation(systemID: peripheral.identifier, timestamp: .now,
            rssi: value,
            txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue)
        continuation.yield(sample)
        registry.ingest(sample, filter: TuningConfig.filter(userSettings.filterStrength))
        registry.trim(to: profile.maxSources)
        callbackTimes.append(sample.timestamp)
        if callbackTimes.count > 2048 { callbackTimes.removeFirst(1024) }
        if sample.timestamp.timeIntervalSince(lastPublish) >= profile.refreshInterval {
            publish(now: sample.timestamp)
        }
    }

    private func activateProfile() {
        dutyTask?.cancel()
        central.stopScan()
        isActivelyScanning = false
        guard isRunning, central.state == .poweredOn else { return }
        guard let scan = profile.scanSeconds, let pause = profile.pauseSeconds else {
            beginHardwareScan(duplicates: profile.duplicates)
            return
        }
        dutyTask = Task { @MainActor [weak self] in
            while let self = self, !Task.isCancelled, self.isRunning {
                self.beginHardwareScan(duplicates: false)
                try? await Task.sleep(nanoseconds: scan * 1_000_000_000)
                guard !Task.isCancelled else { break }
                self.central.stopScan()
                self.isActivelyScanning = false
                try? await Task.sleep(nanoseconds: pause * 1_000_000_000)
            }
        }
    }

    private func beginHardwareScan(duplicates: Bool) {
        central.scanForPeripherals(withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: duplicates])
        isActivelyScanning = true
    }

    private func maintain() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = thermalLimitIsActive()
        if lowPower != isSystemLowPowerMode || thermal != isThermallyLimited {
            isSystemLowPowerMode = lowPower
            isThermallyLimited = thermal
            if isRunning { activateProfile() }
        }
        guard isRunning else { return }
        let now = Date()
        registry.removeStale(now: now, after: profile.staleAfter)
        if now.timeIntervalSince(lastPublish) >= profile.refreshInterval { publish(now: now) }
    }

    private func publish(now: Date) {
        let visible = Array(registry.sources.prefix(profile.displayLimit))
        if visible != sources { sources = visible }
        if activeSourceCount != registry.count { activeSourceCount = registry.count }
        callbackTimes.removeAll { now.timeIntervalSince($0) > 10 }
        let rate = Double(callbackTimes.count) / 10
        if abs(callbacksPerSecond - rate) >= 0.05 { callbacksPerSecond = rate }
        lastPublish = now
    }
}
