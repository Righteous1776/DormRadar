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
    @Published private(set) var bookmarks: [DeviceBookmark] = []
    @Published private(set) var lastAlert: ProximityAlert?

    let observations: AsyncStream<BLEObservation>
    let motion = MotionMonitor()

    private var continuation: AsyncStream<BLEObservation>.Continuation
    private var central: CBCentralManager!
    private let registry = BLESourceRegistry()
    private let alertCoordinator = AlertCoordinator()
    private var callbackTimes: [Date] = []
    private var maintenanceTimer: Timer?
    private var dutyTask: Task<Void, Never>?
    private var lastPublish = Date.distantPast
    private var alertDismissTask: Task<Void, Never>?
    private var restoredBySystem = false
    private var bookmarkBySystemID: [UUID: Int] = [:]
    private var bookmarkBySignature: [String: Int] = [:]

    private enum StorageKey {
        static let settings = "userSettings"
        static let bookmarks = "deviceBookmarks.v1"
        static let monitoringDesired = "monitoringDesired"
    }

    private var profile = TuningConfig.profile(settings: .defaults, forcedEco: false)

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
        if let data = UserDefaults.standard.data(forKey: StorageKey.settings),
           var saved = try? JSONDecoder().decode(UserSettings.self, from: data) {
            saved.normalize()
            userSettings = saved
        }
        if let data = UserDefaults.standard.data(forKey: StorageKey.bookmarks),
           let saved = try? JSONDecoder().decode([DeviceBookmark].self, from: data) {
            bookmarks = saved.map {
                var item = $0
                item.normalize()
                return item
            }
        }
        super.init()
        rebuildBookmarkIndex()
        refreshProfile()
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "com.righteous1776.DormRadar.central",
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.maintain() }
        }
        timer.tolerance = 0.2
        maintenanceTimer = timer
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        alertDismissTask?.cancel()
        continuation.finish()
    }

    func toggle() {
        if userSettings.hapticsEnabled { Haptics.tap(isRunning ? .light : .medium) }
        isRunning ? stop() : start()
    }

    func setMode(_ newMode: PowerMode) {
        updateSetting(\.mode, to: newMode)
        if userSettings.hapticsEnabled { Haptics.tap(.light) }
    }

    func updateSetting<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>, to value: Value) {
        var next = userSettings
        next[keyPath: keyPath] = value
        next.normalize()
        guard next != userSettings else { return }
        userSettings = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: StorageKey.settings)
        }
        if !next.backgroundMonitoringEnabled {
            UserDefaults.standard.set(false, forKey: StorageKey.monitoringDesired)
        } else if isRunning {
            UserDefaults.standard.set(true, forKey: StorageKey.monitoringDesired)
        }
        let profileChanged = refreshProfile()
        if isRunning, profileChanged { activateProfile() }
    }

    func resetSettings() {
        userSettings = .defaults
        UserDefaults.standard.removeObject(forKey: StorageKey.settings)
        if isRunning { UserDefaults.standard.set(true, forKey: StorageKey.monitoringDesired) }
        let profileChanged = refreshProfile()
        if userSettings.hapticsEnabled { Haptics.tap(.medium) }
        if isRunning, profileChanged { activateProfile() }
    }

    func start() {
        beginSession(persistIntent: true)
    }

    private func beginSession(persistIntent: Bool) {
        guard !isRunning else { return }
        registry.reset()
        callbackTimes.removeAll(keepingCapacity: true)
        sources = []
        activeSourceCount = 0
        lastPublish = .distantPast
        isSystemLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        isThermallyLimited = thermalLimitIsActive()
        refreshProfile()
        isRunning = true
        if persistIntent && userSettings.backgroundMonitoringEnabled {
            UserDefaults.standard.set(true, forKey: StorageKey.monitoringDesired)
        }
        motion.start(updateInterval: motionUpdateInterval)
        activateProfile()
    }

    func stop() {
        isRunning = false
        dutyTask?.cancel()
        dutyTask = nil
        central.stopScan()
        motion.stop()
        isActivelyScanning = false
        callbacksPerSecond = 0
        UserDefaults.standard.set(false, forKey: StorageKey.monitoringDesired)
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
        if central.state == .poweredOn {
            let shouldResume = restoredBySystem ||
                (userSettings.backgroundMonitoringEnabled &&
                 UserDefaults.standard.bool(forKey: StorageKey.monitoringDesired))
            restoredBySystem = false
            if shouldResume && !isRunning {
                beginSession(persistIntent: false)
            } else if isRunning {
                activateProfile()
            }
        }
        if central.state != .poweredOn {
            dutyTask?.cancel()
            central.stopScan()
            isActivelyScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        restoredBySystem = userSettings.backgroundMonitoringEnabled
        bluetoothState = "正在恢复后台监测"
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let value = RSSI.intValue
        guard (-110 ... -20).contains(value), value != 0, value != 127 else { return }
        let sample = BLEObservation(systemID: peripheral.identifier, timestamp: .now,
            rssi: value,
            txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            manufacturerID: Self.manufacturerID(from: advertisementData),
            serviceUUIDs: Self.serviceUUIDs(from: advertisementData),
            motionAvailable: motion.isAvailable,
            receiverMoving: motion.isMoving,
            relativeYawDegrees: motion.relativeYawDegrees)
        continuation.yield(sample)
        let source = registry.ingest(sample, filter: TuningConfig.filter(userSettings.filterStrength))
        registry.trim(to: profile.maxSources)
        if let bookmark = resolveBookmark(for: source),
           let alert = alertCoordinator.evaluate(source: source, bookmark: bookmark,
                                                 settings: userSettings) {
            show(alert)
        }
        callbackTimes.append(sample.timestamp)
        if callbackTimes.count > 2048 { callbackTimes.removeFirst(1024) }
        if sample.timestamp.timeIntervalSince(lastPublish) >= profile.refreshInterval {
            publish(now: sample.timestamp)
        }
    }

    func bookmark(for source: BLESource) -> DeviceBookmark? {
        if let index = bookmarkBySystemID[source.systemID] { return bookmarks[index] }
        guard let signature = source.persistentSignature else { return nil }
        return bookmarkBySignature[signature].map { bookmarks[$0] }
    }

    func draftBookmark(for source: BLESource) -> DeviceBookmark {
        bookmark(for: source) ?? DeviceBookmark(systemID: source.systemID,
            fallbackSignature: source.persistentSignature,
            serviceUUIDs: source.serviceUUIDs,
            customName: source.primaryName == source.displayName ? "" : source.primaryName)
    }

    func saveBookmark(_ bookmark: DeviceBookmark) {
        var normalized = bookmark
        normalized.normalize()
        normalized.updatedAt = .now
        if let index = bookmarks.firstIndex(where: { $0.id == normalized.id }) {
            bookmarks[index] = normalized
        } else {
            bookmarks.append(normalized)
        }
        rebuildBookmarkIndex()
        persistBookmarks()
        if normalized.alertEnabled { alertCoordinator.requestPermissionIfNeeded() }
        if userSettings.hapticsEnabled { Haptics.tap(.medium) }
    }

    func removeBookmark(_ bookmark: DeviceBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        rebuildBookmarkIndex()
        alertCoordinator.remove(bookmarkID: bookmark.id)
        persistBookmarks()
        if userSettings.hapticsEnabled { Haptics.tap(.light) }
    }

    func displayName(for source: BLESource) -> String {
        guard let name = bookmark(for: source)?.customName, !name.isEmpty else { return source.primaryName }
        return name
    }

    func dismissAlert() {
        alertDismissTask?.cancel()
        lastAlert = nil
    }

    private func resolveBookmark(for source: BLESource) -> DeviceBookmark? {
        if let index = bookmarkBySystemID[source.systemID] { return bookmarks[index] }
        guard let signature = source.persistentSignature,
              let index = bookmarkBySignature[signature] else { return nil }
        bookmarks[index].systemID = source.systemID
        bookmarks[index].updatedAt = .now
        rebuildBookmarkIndex()
        persistBookmarks()
        return bookmarks[index]
    }

    private func rebuildBookmarkIndex() {
        bookmarkBySystemID.removeAll(keepingCapacity: true)
        bookmarkBySignature.removeAll(keepingCapacity: true)
        for (index, bookmark) in bookmarks.enumerated() {
            bookmarkBySystemID[bookmark.systemID] = index
            if let signature = bookmark.fallbackSignature { bookmarkBySignature[signature] = index }
        }
    }

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: StorageKey.bookmarks)
        }
    }

    private func show(_ alert: ProximityAlert) {
        lastAlert = alert
        alertDismissTask?.cancel()
        alertDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastAlert = nil
        }
    }

    @objc private func appDidEnterBackground() {
        guard isRunning else { return }
        dutyTask?.cancel()
        dutyTask = nil
        motion.stop()
        guard userSettings.backgroundMonitoringEnabled,
              central.state == .poweredOn else {
            central.stopScan()
            isActivelyScanning = false
            return
        }
        beginHardwareScan(duplicates: false, preferMarkedServices: true)
    }

    @objc private func appDidBecomeActive() {
        guard isRunning else { return }
        motion.start(updateInterval: motionUpdateInterval)
        activateProfile()
    }

    private func activateProfile() {
        dutyTask?.cancel()
        central.stopScan()
        isActivelyScanning = false
        motion.configure(updateInterval: motionUpdateInterval)
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

    private func beginHardwareScan(duplicates: Bool, preferMarkedServices: Bool = false) {
        let markedServices = bookmarks.filter(\.alertEnabled).flatMap(\.serviceUUIDs)
        let services: [CBUUID]? = preferMarkedServices && !markedServices.isEmpty
            ? Array(Set(markedServices)).map { CBUUID(string: $0) }
            : nil
        central.scanForPeripherals(withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: duplicates])
        isActivelyScanning = true
    }

    private static func manufacturerID(from advertisementData: [String: Any]) -> UInt16? {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 2 else { return nil }
        let start = data.startIndex
        return UInt16(data[start]) | (UInt16(data[data.index(after: start)]) << 8)
    }

    private static func serviceUUIDs(from advertisementData: [String: Any]) -> [String] {
        var values = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        values += (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            values.append(contentsOf: serviceData.keys)
        }
        return Array(Set(values.map { $0.uuidString.uppercased() })).sorted().prefix(8).map { $0 }
    }

    @discardableResult
    private func refreshProfile() -> Bool {
        let next = TuningConfig.profile(settings: userSettings, forcedEco: conservationForced)
        guard next != profile else { return false }
        profile = next
        return true
    }

    private var motionUpdateInterval: TimeInterval {
        isUsingUltraEco ? 0.25 : 0.10
    }

    private func maintain() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = thermalLimitIsActive()
        if lowPower != isSystemLowPowerMode || thermal != isThermallyLimited {
            isSystemLowPowerMode = lowPower
            isThermallyLimited = thermal
            let profileChanged = refreshProfile()
            if isRunning, profileChanged { activateProfile() }
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
