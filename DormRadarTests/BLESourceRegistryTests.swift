import XCTest
@testable import DormRadar

@MainActor
final class BLESourceRegistryTests: XCTestCase {
    private func sample(_ id: UUID, _ time: Date, _ rssi: Int,
                        motionAvailable: Bool = false, moving: Bool = false,
                        yaw: Double? = nil) -> BLEObservation {
        .init(systemID: id, timestamp: time, rssi: rssi,
              txPower: nil, isConnectable: nil, localName: nil,
              manufacturerID: nil, serviceUUIDs: [], motionAvailable: motionAvailable,
              receiverMoving: moving, relativeYawDegrees: yaw)
    }

    func testIdentityAndOrderingStayStable() {
        let registry = BLESourceRegistry(), id = UUID(), time = Date()
        let first = registry.ingest(sample(id, time, -70))
        let second = registry.ingest(sample(id, time.addingTimeInterval(1), -65))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.sampleCount, 2)
        XCTAssertEqual(second.rawRSSI, -65)
        XCTAssertEqual(registry.sources.count, 1)
        XCTAssertEqual(second.systemID, id)
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

    func testDistanceIsOneMeterAtReferenceSignal() {
        let registry = BLESourceRegistry(), time = Date()
        let source = registry.ingest(sample(UUID(), time, -59))
        XCTAssertEqual(source.estimatedDistance(referenceRSSI: -59,
                                                pathLossExponent: 2.2), 1, accuracy: 0.001)
    }

    func testBroadcastMetadataIsRetained() {
        let registry = BLESourceRegistry(), id = UUID(), time = Date()
        let observation = BLEObservation(systemID: id, timestamp: time, rssi: -62,
            txPower: -8, isConnectable: true, localName: "Desk Sensor",
            manufacturerID: 0x004C, serviceUUIDs: ["180F"], motionAvailable: true,
            receiverMoving: false, relativeYawDegrees: 0)
        let source = registry.ingest(observation)
        XCTAssertEqual(source.primaryName, "Desk Sensor")
        XCTAssertEqual(source.manufacturerLabel, "Apple")
        XCTAssertEqual(source.serviceLabels, ["电池 (180F)"])
        XCTAssertEqual(source.isConnectable, true)
    }

    func testOldSettingsCanMigrateWithoutLosingPreferences() throws {
        let data = Data(#"{"mode":"ultraEco","hapticsEnabled":false}"#.utf8)
        let settings = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(settings.mode, .ultraEco)
        XCTAssertFalse(settings.hapticsEnabled)
        XCTAssertEqual(settings.distanceReferenceRSSI, -59)
        XCTAssertEqual(settings.pathLossExponent, 2.2)
        XCTAssertEqual(settings.theme, .midnight)
        XCTAssertTrue(settings.backgroundMonitoringEnabled)
    }

    func testPhoneMovementReducesRSSIReaction() {
        let id = UUID(), time = Date()
        let stationary = BLESourceRegistry(), moving = BLESourceRegistry()
        stationary.ingest(sample(id, time, -70, motionAvailable: true))
        moving.ingest(sample(id, time, -70, motionAvailable: true))
        let stationaryResult = stationary.ingest(sample(id, time.addingTimeInterval(1), -50,
                                                        motionAvailable: true))
        let movingResult = moving.ingest(sample(id, time.addingTimeInterval(1), -50,
                                                motionAvailable: true, moving: true))
        XCTAssertGreaterThan(stationaryResult.stableRSSI, movingResult.stableRSSI)
    }

    func testDistanceRangeContainsPointEstimate() {
        let source = BLESourceRegistry().ingest(sample(UUID(), Date(), -65,
                                                        motionAvailable: true))
        let point = source.estimatedDistance(referenceRSSI: -59, pathLossExponent: 2.2)
        let range = source.estimatedDistanceRange(referenceRSSI: -59, pathLossExponent: 2.2)
        XCTAssertTrue(range.contains(point))
        XCTAssertGreaterThan(range.upperBound, range.lowerBound)
    }

    func testRotationSamplesProduceRelativeDirection() {
        let registry = BLESourceRegistry(), id = UUID(), time = Date()
        for pass in 0..<2 {
            for bin in 0..<12 {
                let yaw = Double(bin * 30 + 5)
                let rssi = bin == 3 ? -52 : -78
                registry.ingest(sample(id, time.addingTimeInterval(Double(pass * 12 + bin)), rssi,
                                       motionAvailable: true, yaw: yaw))
            }
        }
        XCTAssertEqual(registry.sources.first?.relativeDirectionDegrees, 105)
    }

    func testAlertGateRequiresThreeCloseSamples() {
        var gate = AlertGate()
        let id = UUID(), now = Date()
        XCTAssertFalse(gate.shouldFire(id: id, distance: 2, threshold: 3, now: now))
        XCTAssertFalse(gate.shouldFire(id: id, distance: 2, threshold: 3,
                                       now: now.addingTimeInterval(1)))
        XCTAssertTrue(gate.shouldFire(id: id, distance: 2, threshold: 3,
                                      now: now.addingTimeInterval(2)))
    }

    func testAlertGateUsesHysteresisAndCooldown() {
        var gate = AlertGate()
        let id = UUID(), now = Date()
        for index in 0..<3 {
            _ = gate.shouldFire(id: id, distance: 2, threshold: 3,
                                now: now.addingTimeInterval(Double(index)))
        }
        XCTAssertFalse(gate.shouldFire(id: id, distance: 2, threshold: 3,
                                       now: now.addingTimeInterval(70)))
        XCTAssertFalse(gate.shouldFire(id: id, distance: 4, threshold: 3,
                                       now: now.addingTimeInterval(71)))
        XCTAssertFalse(gate.shouldFire(id: id, distance: 2, threshold: 3,
                                       now: now.addingTimeInterval(72)))
        XCTAssertFalse(gate.shouldFire(id: id, distance: 2, threshold: 3,
                                       now: now.addingTimeInterval(73)))
        XCTAssertTrue(gate.shouldFire(id: id, distance: 2, threshold: 3,
                                      now: now.addingTimeInterval(74)))
    }

    func testBookmarkNormalizationLimitsUserInput() {
        var bookmark = DeviceBookmark(systemID: UUID(), customName: "  " + String(repeating: "A", count: 50),
                                      alertDistance: 99)
        bookmark.normalize()
        XCTAssertEqual(bookmark.customName.count, 32)
        XCTAssertEqual(bookmark.alertDistance, 15)
        XCTAssertFalse(bookmark.soundEnabled)
    }

    func testNamedSourceCreatesFallbackSignature() {
        let observation = BLEObservation(systemID: UUID(), timestamp: Date(), rssi: -60,
            txPower: nil, isConnectable: nil, localName: "Desk Tag", manufacturerID: 0x004C,
            serviceUUIDs: ["180F"], motionAvailable: false, receiverMoving: false,
            relativeYawDegrees: nil)
        let source = BLESourceRegistry().ingest(observation)
        XCTAssertNotNil(source.persistentSignature)
    }
}
