import XCTest
@testable import DormRadar

@MainActor
final class BLESourceRegistryTests: XCTestCase {
    private func sample(_ id: UUID, _ time: Date, _ rssi: Int) -> BLEObservation {
        .init(systemID: id, timestamp: time, rssi: rssi,
              txPower: nil, isConnectable: nil)
    }

    func testIdentityAndOrderingStayStable() {
        let registry = BLESourceRegistry(), id = UUID(), time = Date()
        let first = registry.ingest(sample(id, time, -70))
        let second = registry.ingest(sample(id, time.addingTimeInterval(1), -65))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.sampleCount, 2)
        XCTAssertEqual(second.rawRSSI, -65)
        XCTAssertEqual(registry.sources.count, 1)
    }

    func testStaleSourceIsRemoved() {
        let registry = BLESourceRegistry(), time = Date()
        registry.ingest(sample(UUID(), time, -70))
        XCTAssertEqual(registry.removeStale(now: time.addingTimeInterval(16), after: 15), 1)
        XCTAssertTrue(registry.sources.isEmpty)
    }

    func testLateSampleCannotReplaceNewestValue() {
        let registry = BLESourceRegistry(), id = UUID(), time = Date()
        registry.ingest(sample(id, time.addingTimeInterval(2), -60))
        let result = registry.ingest(sample(id, time, -90))
        XCTAssertEqual(result.rawRSSI, -60)
        XCTAssertEqual(result.firstSeen, time)
        XCTAssertEqual(result.sampleCount, 2)
    }

    func testSingleSpikeIsSuppressed() {
        let registry = BLESourceRegistry(), id = UUID(), time = Date()
        registry.ingest(sample(id, time, -70))
        let result = registry.ingest(sample(id, time.addingTimeInterval(1), -30))
        XCTAssertLessThan(result.stableRSSI, -60)
        XCTAssertEqual(result.suppressedSpikeCount, 1)
    }

    func testRegistryRespectsMemoryLimit() {
        let registry = BLESourceRegistry(), time = Date()
        for index in 0..<10 {
            registry.ingest(sample(UUID(), time.addingTimeInterval(Double(index)), -80 + index))
        }
        registry.trim(to: 4)
        XCTAssertEqual(registry.sources.count, 4)
    }

    func testSettingsAreClampedToSafeRange() {
        var settings = UserSettings(customScanSeconds: 1, customPauseSeconds: 99,
                                    customRefreshInterval: 0.01, customStaleAfter: 5,
                                    customMaxSources: 12, customDisplayLimit: 300)
        settings.normalize()
        XCTAssertEqual(settings.customScanSeconds, 3)
        XCTAssertEqual(settings.customPauseSeconds, 60)
        XCTAssertEqual(settings.customRefreshInterval, 0.15)
        XCTAssertEqual(settings.customStaleAfter, 10)
        XCTAssertEqual(settings.customMaxSources, 32)
        XCTAssertEqual(settings.customDisplayLimit, 32)
    }

    func testCustomProfileUsesUserParameters() {
        var settings = UserSettings()
        settings.mode = .custom
        settings.customScanSeconds = 9
        settings.customPauseSeconds = 11
        settings.customRefreshInterval = 0.4
        settings.customStaleAfter = 45
        settings.customMaxSources = 144
        settings.customDisplayLimit = 52
        let profile = TuningConfig.profile(settings: settings, forcedEco: false)
        XCTAssertEqual(profile.scanSeconds, 9)
        XCTAssertEqual(profile.pauseSeconds, 11)
        XCTAssertEqual(profile.refreshInterval, 0.4)
        XCTAssertEqual(profile.staleAfter, 45)
        XCTAssertEqual(profile.maxSources, 144)
        XCTAssertEqual(profile.displayLimit, 52)
    }

    func testAutomaticProtectionOverridesCustomMode() {
        var settings = UserSettings()
        settings.mode = .custom
        settings.customRefreshInterval = 0.15
        let profile = TuningConfig.profile(settings: settings, forcedEco: true)
        XCTAssertEqual(profile.refreshInterval, 2)
        XCTAssertEqual(profile.scanSeconds, 6)
        XCTAssertEqual(profile.pauseSeconds, 24)
        XCTAssertFalse(profile.duplicates)
    }
}
