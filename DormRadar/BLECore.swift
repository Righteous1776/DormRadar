import Foundation

enum PowerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case adaptive, ultraEco, balanced, responsive, custom
    var id: Self { self }
    var title: String {
        switch self {
        case .adaptive: return "智能"
        case .ultraEco: return "超级省电"
        case .balanced: return "均衡"
        case .responsive: return "高响应"
        case .custom: return "自定义"
        }
    }
    var summary: String {
        switch self {
        case .adaptive: return "根据设备内存、电量与温度自动调整"
        case .ultraEco: return "间歇扫描，适合长时间运行"
        case .balanced: return "稳定性、响应与耗电的平衡"
        case .responsive: return "更快刷新，适合短时间观察"
        case .custom: return "使用设置页中的高级参数"
        }
    }
}

enum FilterStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case light, standard, strong
    var id: Self { self }
    var title: String {
        switch self {
        case .light: return "灵敏"
        case .standard: return "标准"
        case .strong: return "稳定"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case midnight, oledBlack, graphite, redNight
    var id: Self { self }
    var title: String {
        switch self {
        case .midnight: return "深海蓝"
        case .oledBlack: return "OLED 黑"
        case .graphite: return "石墨灰"
        case .redNight: return "夜视红"
        }
    }
}

struct UserSettings: Equatable, Sendable {
    var mode: PowerMode = .adaptive
    var filterStrength: FilterStrength = .standard
    var hapticsEnabled = true
    var automaticLowPower = true
    var automaticThermalProtection = true
    var customScanSeconds = 8
    var customPauseSeconds = 12
    var customRefreshInterval = 0.5
    var customStaleAfter = 30
    var customMaxSources = 128
    var customDisplayLimit = 48
    var distanceReferenceRSSI = -59
    var pathLossExponent = 2.2
    var theme: AppTheme = .midnight
    var extraDim = 0.0
    var animationsEnabled = true
    var backgroundMonitoringEnabled = true

    static let defaults = UserSettings()

    mutating func normalize() {
        customScanSeconds = min(30, max(3, customScanSeconds))
        customPauseSeconds = min(60, max(0, customPauseSeconds))
        customRefreshInterval = min(3, max(0.15, customRefreshInterval))
        customStaleAfter = min(180, max(10, customStaleAfter))
        customMaxSources = min(256, max(32, customMaxSources))
        customDisplayLimit = min(100, max(12, customDisplayLimit))
        customDisplayLimit = min(customDisplayLimit, customMaxSources)
        distanceReferenceRSSI = min(-40, max(-85, distanceReferenceRSSI))
        pathLossExponent = min(4, max(1.6, pathLossExponent))
        extraDim = min(0.72, max(0, extraDim))
    }
}

extension UserSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, filterStrength, hapticsEnabled, automaticLowPower
        case automaticThermalProtection, customScanSeconds, customPauseSeconds
        case customRefreshInterval, customStaleAfter, customMaxSources, customDisplayLimit
        case distanceReferenceRSSI, pathLossExponent
        case theme, extraDim, animationsEnabled, backgroundMonitoringEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = UserSettings.defaults
        mode = try values.decodeIfPresent(PowerMode.self, forKey: .mode) ?? base.mode
        filterStrength = try values.decodeIfPresent(FilterStrength.self, forKey: .filterStrength) ?? base.filterStrength
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? base.hapticsEnabled
        automaticLowPower = try values.decodeIfPresent(Bool.self, forKey: .automaticLowPower) ?? base.automaticLowPower
        automaticThermalProtection = try values.decodeIfPresent(Bool.self, forKey: .automaticThermalProtection) ?? base.automaticThermalProtection
        customScanSeconds = try values.decodeIfPresent(Int.self, forKey: .customScanSeconds) ?? base.customScanSeconds
        customPauseSeconds = try values.decodeIfPresent(Int.self, forKey: .customPauseSeconds) ?? base.customPauseSeconds
        customRefreshInterval = try values.decodeIfPresent(Double.self, forKey: .customRefreshInterval) ?? base.customRefreshInterval
        customStaleAfter = try values.decodeIfPresent(Int.self, forKey: .customStaleAfter) ?? base.customStaleAfter
        customMaxSources = try values.decodeIfPresent(Int.self, forKey: .customMaxSources) ?? base.customMaxSources
        customDisplayLimit = try values.decodeIfPresent(Int.self, forKey: .customDisplayLimit) ?? base.customDisplayLimit
        distanceReferenceRSSI = try values.decodeIfPresent(Int.self, forKey: .distanceReferenceRSSI) ?? base.distanceReferenceRSSI
        pathLossExponent = try values.decodeIfPresent(Double.self, forKey: .pathLossExponent) ?? base.pathLossExponent
        theme = try values.decodeIfPresent(AppTheme.self, forKey: .theme) ?? base.theme
        extraDim = try values.decodeIfPresent(Double.self, forKey: .extraDim) ?? base.extraDim
        animationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? base.animationsEnabled
        backgroundMonitoringEnabled = try values.decodeIfPresent(Bool.self, forKey: .backgroundMonitoringEnabled) ?? base.backgroundMonitoringEnabled
        normalize()
    }
}

struct ScanProfile: Sendable, Equatable {
    let refreshInterval: TimeInterval
    let staleAfter: TimeInterval
    let maxSources: Int
    let displayLimit: Int
    let duplicates: Bool
    let scanSeconds: UInt64?
    let pauseSeconds: UInt64?
}

struct FilterProfile: Sendable {
    let stableAlpha: Double
    let dynamicAlpha: Double
    let dynamicThreshold: Double
    let maximumJump: Double
}

enum TuningConfig {
    static func profile(settings: UserSettings, forcedEco: Bool) -> ScanProfile {
        if forcedEco { return preset(.ultraEco) }
        if settings.mode == .custom {
            let paused = settings.customPauseSeconds > 0
            return .init(refreshInterval: settings.customRefreshInterval,
                staleAfter: Double(settings.customStaleAfter),
                maxSources: settings.customMaxSources,
                displayLimit: settings.customDisplayLimit,
                duplicates: !paused,
                scanSeconds: paused ? UInt64(settings.customScanSeconds) : nil,
                pauseSeconds: paused ? UInt64(settings.customPauseSeconds) : nil)
        }
        return preset(settings.mode)
    }

    static func filter(_ strength: FilterStrength) -> FilterProfile {
        switch strength {
        case .light: return .init(stableAlpha: 0.28, dynamicAlpha: 0.50,
                                  dynamicThreshold: 6, maximumJump: 24)
        case .standard: return .init(stableAlpha: 0.18, dynamicAlpha: 0.38,
                                     dynamicThreshold: 7, maximumJump: 18)
        case .strong: return .init(stableAlpha: 0.10, dynamicAlpha: 0.25,
                                   dynamicThreshold: 8, maximumJump: 12)
        }
    }

    private static func preset(_ mode: PowerMode) -> ScanProfile {
        switch mode {
        case .ultraEco:
            return .init(refreshInterval: 2, staleAfter: 90, maxSources: 64,
                         displayLimit: 24, duplicates: false,
                         scanSeconds: 6, pauseSeconds: 24)
        case .responsive:
            return .init(refreshInterval: 0.15, staleAfter: 12, maxSources: 192,
                         displayLimit: 80, duplicates: true,
                         scanSeconds: nil, pauseSeconds: nil)
        case .adaptive:
            let olderDevice = ProcessInfo.processInfo.physicalMemory < 3_200_000_000
            return olderDevice
                ? .init(refreshInterval: 0.7, staleAfter: 30, maxSources: 96,
                        displayLimit: 36, duplicates: true, scanSeconds: nil, pauseSeconds: nil)
                : .init(refreshInterval: 0.35, staleAfter: 22, maxSources: 160,
                        displayLimit: 64, duplicates: true, scanSeconds: nil, pauseSeconds: nil)
        default:
            return .init(refreshInterval: 0.5, staleAfter: 20, maxSources: 128,
                         displayLimit: 48, duplicates: true,
                         scanSeconds: nil, pauseSeconds: nil)
        }
    }
}

struct BLEObservation: Sendable {
    let systemID: UUID
    let timestamp: Date
    let rssi: Int
    let txPower: Int?
    let isConnectable: Bool?
    let localName: String?
    let manufacturerID: UInt16?
    let serviceUUIDs: [String]
    let motionAvailable: Bool
    let receiverMoving: Bool
    let relativeYawDegrees: Double?
}

struct BLESource: Identifiable, Sendable, Equatable {
    let id: UUID
    let systemID: UUID
    let alias: Int
    var firstSeen: Date
    var lastSeen: Date
    var rawRSSI: Int
    var stableRSSI: Double
    var sampleCount: Int
    var suppressedSpikeCount: Int
    var noiseEMA: Double
    var trendEMA: Double
    var txPower: Int?
    var isConnectable: Bool?
    var localName: String?
    var manufacturerID: UInt16?
    var serviceUUIDs: [String]
    var stationarySampleCount: Int
    var movingSampleCount: Int
    var orientationRSSI: [Double]
    var orientationSampleCounts: [Int]

    var displayName: String { "Source \(alias)" }
    var primaryName: String {
        guard let name = localName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return displayName }
        return String(name.prefix(48))
    }
    var manufacturerLabel: String {
        guard let id = manufacturerID else { return "未广播厂商编号" }
        switch id {
        case 0x004C: return "Apple"
        case 0x0006: return "Microsoft"
        case 0x0075: return "Samsung"
        case 0x00E0: return "Google"
        case 0x0059: return "Nordic Semiconductor"
        default: return String(format: "厂商 0x%04X", id)
        }
    }
    var deviceTypeLabel: String {
        let name = primaryName.lowercased()
        if name.contains("airpods") || name.contains("buds") { return "可能是无线耳机" }
        if name.contains("watch") { return "可能是智能手表" }
        if name.contains("keyboard") || serviceUUIDs.contains("1812") { return "可能是输入设备" }
        if serviceUUIDs.contains("180D") { return "可能是心率设备" }
        if manufacturerID == 0x004C { return "Apple 设备或配件" }
        if localName != nil { return "具名 BLE 设备" }
        return "匿名 BLE 广播源"
    }
    var stabilityLabel: String {
        if sampleCount < 4 { return "采样中" }
        if noiseEMA < 3 { return "稳定" }
        if noiseEMA < 7 { return "轻微波动" }
        return "干扰较多"
    }
    func ageLabel(now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(lastSeen)))
        if seconds < 2 { return "刚刚" }
        if seconds < 60 { return "\(seconds)秒前" }
        return "\(seconds / 60)分钟前"
    }
    func estimatedDistance(referenceRSSI: Int, pathLossExponent: Double) -> Double {
        let exponent = max(1.6, min(4, pathLossExponent))
        return pow(10, (Double(referenceRSSI) - stableRSSI) / (10 * exponent))
    }
    func proximityLabel(referenceRSSI: Int, pathLossExponent: Double) -> String {
        let distance = estimatedDistance(referenceRSSI: referenceRSSI,
                                         pathLossExponent: pathLossExponent)
        if distance < 0.7 { return "非常近" }
        if distance < 2 { return "附近" }
        if distance < 5 { return "中等距离" }
        return "较远"
    }
    var trendLabel: String {
        guard sampleCount >= 6 else { return "采样中" }
        if trendEMA > 0.18 { return "可能靠近" }
        if trendEMA < -0.18 { return "可能远离" }
        return "相对稳定"
    }
    var confidenceLabel: String {
        if sampleCount < 8 || noiseEMA >= 8 || stationaryRatio < 0.35 { return "低" }
        if sampleCount >= 20 && noiseEMA < 3 && stationaryRatio > 0.70 { return "较高" }
        return "中等"
    }
    var stationaryRatio: Double {
        let counted = stationarySampleCount + movingSampleCount
        return counted == 0 ? 0 : Double(stationarySampleCount) / Double(counted)
    }
    func estimatedDistanceRange(referenceRSSI: Int,
                                pathLossExponent: Double) -> ClosedRange<Double> {
        let center = estimatedDistance(referenceRSSI: referenceRSSI,
                                       pathLossExponent: pathLossExponent)
        let movementPenalty = (1 - stationaryRatio) * 0.7
        let noisePenalty = min(1.4, noiseEMA / 10)
        let factor = 1.30 + movementPenalty + noisePenalty
        return max(0.1, center / factor) ... min(99, center * factor)
    }
    var relativeDirectionDegrees: Int? {
        let candidates = orientationSampleCounts.indices.compactMap { index -> (Int, Double)? in
            guard orientationSampleCounts[index] >= 2 else { return nil }
            return (index, orientationRSSI[index])
        }.sorted { $0.1 > $1.1 }
        guard candidates.count >= 6 else { return nil }
        guard candidates.count == 1 || candidates[0].1 - candidates[1].1 >= 1 else { return nil }
        return candidates[0].0 * 30 + 15
    }
    var directionLabel: String {
        guard let degrees = relativeDirectionDegrees else {
            return "证据不足，原地缓慢转一圈"
        }
        return "相对开始朝向约 +\(degrees)°"
    }
    var serviceLabels: [String] {
        serviceUUIDs.map {
            switch $0 {
            case "180A": return "设备信息 (180A)"
            case "180D": return "心率 (180D)"
            case "180F": return "电池 (180F)"
            case "1812": return "人机接口 (1812)"
            case "FEAA": return "Eddystone 信标 (FEAA)"
            case "FE2C": return "Fast Pair (FE2C)"
            default: return $0
            }
        }
    }
    var persistentSignature: String? {
        guard let name = localName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty, manufacturerID != nil || !serviceUUIDs.isEmpty else { return nil }
        return ([name, manufacturerID.map(String.init) ?? "-"] + serviceUUIDs.sorted()).joined(separator: "|")
    }
}

@MainActor
final class BLESourceRegistry {
    private var links: [UUID: UUID] = [:]
    private var records: [UUID: BLESource] = [:]
    private var nextAlias = 1

    var count: Int { records.count }
    var sources: [BLESource] {
        records.values.sorted {
            if $0.stableRSSI != $1.stableRSSI { return $0.stableRSSI > $1.stableRSSI }
            return $0.alias < $1.alias
        }
    }

    @discardableResult
    func ingest(_ sample: BLEObservation, filter: FilterProfile = TuningConfig.filter(.standard)) -> BLESource {
        if let localID = links[sample.systemID], var source = records[localID] {
            source.sampleCount += 1
            source.firstSeen = min(source.firstSeen, sample.timestamp)
            if sample.timestamp >= source.lastSeen {
                let raw = Double(sample.rssi)
                let delta = raw - source.stableRSSI
                let deviation = abs(delta)
                source.noiseEMA = source.sampleCount == 2
                    ? deviation : 0.15 * deviation + 0.85 * source.noiseEMA
                let clipped = source.stableRSSI + max(-filter.maximumJump,
                                                       min(filter.maximumJump, delta))
                let baseAlpha = deviation >= filter.dynamicThreshold
                    ? filter.dynamicAlpha : filter.stableAlpha
                let alpha = sample.receiverMoving ? baseAlpha * 0.35 : baseAlpha
                if deviation > filter.maximumJump { source.suppressedSpikeCount += 1 }
                let previousStableRSSI = source.stableRSSI
                source.stableRSSI += alpha * (clipped - source.stableRSSI)
                let stableDelta = source.stableRSSI - previousStableRSSI
                source.trendEMA = 0.20 * stableDelta + 0.80 * source.trendEMA
                source.rawRSSI = sample.rssi
                source.lastSeen = sample.timestamp
                source.txPower = sample.txPower ?? source.txPower
                source.isConnectable = sample.isConnectable ?? source.isConnectable
                source.localName = sample.localName ?? source.localName
                source.manufacturerID = sample.manufacturerID ?? source.manufacturerID
                if !sample.serviceUUIDs.isEmpty { source.serviceUUIDs = sample.serviceUUIDs }
                if sample.motionAvailable {
                    if sample.receiverMoving {
                        source.movingSampleCount += 1
                    } else {
                        source.stationarySampleCount += 1
                    }
                }
                if let yaw = sample.relativeYawDegrees {
                    let normalized = yaw.truncatingRemainder(dividingBy: 360) + (yaw < 0 ? 360 : 0)
                    let bin = min(11, max(0, Int(normalized / 30)))
                    let count = source.orientationSampleCounts[bin]
                    source.orientationRSSI[bin] = count == 0
                        ? raw : 0.25 * raw + 0.75 * source.orientationRSSI[bin]
                    source.orientationSampleCounts[bin] = count + 1
                }
            }
            records[localID] = source
            return source
        }

        let localID = UUID()
        let source = BLESource(id: localID, systemID: sample.systemID, alias: nextAlias,
            firstSeen: sample.timestamp, lastSeen: sample.timestamp,
            rawRSSI: sample.rssi, stableRSSI: Double(sample.rssi), sampleCount: 1,
            suppressedSpikeCount: 0, noiseEMA: 0, trendEMA: 0,
            txPower: sample.txPower, isConnectable: sample.isConnectable,
            localName: sample.localName, manufacturerID: sample.manufacturerID,
            serviceUUIDs: sample.serviceUUIDs,
            stationarySampleCount: sample.motionAvailable && !sample.receiverMoving ? 1 : 0,
            movingSampleCount: sample.motionAvailable && sample.receiverMoving ? 1 : 0,
            orientationRSSI: Array(repeating: -110, count: 12),
            orientationSampleCounts: Array(repeating: 0, count: 12))
        nextAlias += 1
        links[sample.systemID] = localID
        records[localID] = source
        return source
    }

    func trim(to limit: Int) {
        guard records.count > limit else { return }
        let keep = Set(sources.prefix(limit).map(\.id))
        records = records.filter { keep.contains($0.key) }
        links = links.filter { keep.contains($0.value) }
    }

    @discardableResult
    func removeStale(now: Date = .now, after timeout: TimeInterval) -> Int {
        let stale = Set(records.values.filter {
            now.timeIntervalSince($0.lastSeen) > timeout
        }.map(\.id))
        records = records.filter { !stale.contains($0.key) }
        links = links.filter { !stale.contains($0.value) }
        return stale.count
    }

    func reset() {
        links.removeAll(keepingCapacity: true)
        records.removeAll(keepingCapacity: true)
        nextAlias = 1
    }
}
