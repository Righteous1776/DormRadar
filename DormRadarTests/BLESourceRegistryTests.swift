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

    func testCatalogNamesAndModelEvidence() throws {
        let catalog = DeviceCatalog.bundled
        XCTAssertEqual(catalog.companyName(0x004C), "Apple")
        XCTAssertEqual(catalog.companyName(0x0001), "Nokia Mobile Phones")
        XCTAssertEqual(catalog.serviceName("0000180F-0000-1000-8000-00805f9b34fb"), "Battery Service")

        let payload = Data([0x00, 0x20, 0x5B, 0x05, 0x01])
        let model = try XCTUnwrap(catalog.model(miBeaconPayload: payload, broadcastName: nil))
        XCTAssertTrue(model.name.contains("LYWSD03MMC"))
        XCTAssertNil(catalog.model(miBeaconPayload: Data(payload.prefix(4)), broadcastName: nil))
        XCTAssertNil(catalog.model(miBeaconPayload: Data([0x10, 0x20, 0x5B, 0x05, 0x01]),
                                   broadcastName: nil))
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: "Govee_H5074_01")?.name,
                       "Govee H5074")
        XCTAssertNil(catalog.model(miBeaconPayload: nil, broadcastName: "Govee_H0000"))

        var headphones = Data([0x4C, 0x00, 0x07, 0x19, 0x01, 0x24, 0x20])
        headphones.append(Data(repeating: 0, count: 22))
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: nil,
                                     manufacturerData: headphones)?.name, "AirPods Pro（第 2 代，USB-C）")
        headphones[2] = 0x10
        XCTAssertNil(catalog.model(miBeaconPayload: nil, broadcastName: nil, manufacturerData: headphones))
    }

    func testHardwareCodesRequireAnExactName() {
        let catalog = DeviceCatalog.bundled
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: "SAMSUNG-SM-S938B")?.name,
                       "Galaxy S25 Ultra")
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: "24031PN0DC")?.name,
                       "Xiaomi 14 Ultra")
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: "CPH2581")?.name,
                       "OnePlus 12")
        XCTAssertNil(catalog.model(miBeaconPayload: nil, broadcastName: "Zeo SM-S938B"))
        XCTAssertNil(catalog.model(miBeaconPayload: nil, broadcastName: "SM-S938"))
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: "iPhone14,2")?.name,
                       "iPhone 13 Pro")
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: nil,
                                     systemName: "Watch7,8")?.strength, .systemName)
    }

    func testSwitchBotAndShellyServiceEvidence() {
        let catalog = DeviceCatalog.bundled
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: nil,
                                     switchBotPayload: Data([0xFB, 0x00]))?.name, "SwitchBot Curtain 3")
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: nil,
                                     switchBotPayload: Data([0, 0, 1, 16, 83, 176, 2]))?.name,
                       "SwitchBot Weather Station")
        XCTAssertNil(catalog.model(miBeaconPayload: nil, broadcastName: nil,
                                   switchBotPayload: Data([0xFB])))
        XCTAssertEqual(catalog.model(miBeaconPayload: nil, broadcastName: "SBBT-002C",
                                     hasBTHome: true)?.name, "Shelly BLU Button1")
        XCTAssertNil(catalog.model(miBeaconPayload: nil, broadcastName: "SBBT-002C"))
    }

    func testRegistryPreservesStrongerModelEvidence() {
        let registry = BLESourceRegistry()
        let device = UUID()
        let now = Date()
        var first = sample(device, now, -60)
        first.model = AdvertisedModel(name: "SwitchBot Curtain 3", evidence: "service data")
        _ = registry.ingest(first)
        var second = sample(device, now.addingTimeInterval(1), -59)
        second.model = AdvertisedModel(name: "Galaxy S25 Ultra", evidence: "broadcast name",
                                       strength: .broadcastName)
        XCTAssertEqual(registry.ingest(second).model, first.model)
    }

    func testSQLiteBookmarkMigrationAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("marks.sqlite3")
        let original = DeviceBookmark(systemID: UUID(), fallbackSignature: "same model",
                                      customName: "桌上的耳机", alertEnabled: true)
        let other = DeviceBookmark(systemID: UUID(), fallbackSignature: "same model",
                                   customName: "包里的耳机")
        var changed = original
        changed.customName = "已重命名"
        do {
            let store = try BookmarkStore(url: url)
            try store.migrateLegacy([original, other])
            try store.save(changed)
            try store.migrateLegacy([original, other])
        }
        let reopened = try BookmarkStore(url: url)
        XCTAssertEqual(Set(try reopened.loadBookmarks().map { $0.id }), [original.id, other.id])
        XCTAssertEqual(try reopened.loadBookmarks().first { $0.id == original.id }, changed)
        try reopened.remove(id: other.id)
        XCTAssertEqual(try reopened.loadBookmarks(), [changed])
    }
}
