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

struct UserSettings: Codable, Equatable, Sendable {
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

    static let defaults = UserSettings()

    mutating func normalize() {
        customScanSeconds = min(30, max(3, customScanSeconds))
        customPauseSeconds = min(60, max(0, customPauseSeconds))
        customRefreshInterval = min(3, max(0.15, customRefreshInterval))
        customStaleAfter = min(180, max(10, customStaleAfter))
        customMaxSources = min(256, max(32, customMaxSources))
        customDisplayLimit = min(100, max(12, customDisplayLimit))
        customDisplayLimit = min(customDisplayLimit, customMaxSources)
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
}

struct BLESource: Identifiable, Sendable, Equatable {
    let id: UUID
    let alias: Int
    var firstSeen: Date
    var lastSeen: Date
    var rawRSSI: Int
    var stableRSSI: Double
    var sampleCount: Int
    var suppressedSpikeCount: Int
    var noiseEMA: Double
    var txPower: Int?
    var isConnectable: Bool?

    var displayName: String { "Source \(alias)" }
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
                let alpha = deviation >= filter.dynamicThreshold
                    ? filter.dynamicAlpha : filter.stableAlpha
                if deviation > filter.maximumJump { source.suppressedSpikeCount += 1 }
                source.stableRSSI += alpha * (clipped - source.stableRSSI)
                source.rawRSSI = sample.rssi
                source.lastSeen = sample.timestamp
                source.txPower = sample.txPower ?? source.txPower
                source.isConnectable = sample.isConnectable ?? source.isConnectable
            }
            records[localID] = source
            return source
        }

        let localID = UUID()
        let source = BLESource(id: localID, alias: nextAlias,
            firstSeen: sample.timestamp, lastSeen: sample.timestamp,
            rawRSSI: sample.rssi, stableRSSI: Double(sample.rssi), sampleCount: 1,
            suppressedSpikeCount: 0, noiseEMA: 0, txPower: sample.txPower,
            isConnectable: sample.isConnectable)
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
