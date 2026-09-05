import Foundation

enum MarkerColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case cyan, green, orange, pink, purple
    var id: Self { self }
    var title: String {
        switch self {
        case .cyan: return "青色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .pink: return "粉色"
        case .purple: return "紫色"
        }
    }
}

enum MarkerIcon: String, CaseIterable, Identifiable, Codable, Sendable {
    case star = "star.fill"
    case shield = "shield.fill"
    case key = "key.fill"
    case bag = "bag.fill"
    case sensor = "dot.radiowaves.left.and.right"
    var id: Self { self }
    var title: String {
        switch self {
        case .star: return "星标"
        case .shield: return "重要"
        case .key: return "钥匙"
        case .bag: return "物品"
        case .sensor: return "传感器"
        }
    }
}

struct DeviceBookmark: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var systemID: UUID
    var fallbackSignature: String? = nil
    var serviceUUIDs: [String] = []
    var customName: String
    var color: MarkerColor = .cyan
    var icon: MarkerIcon = .star
    var alertEnabled = false
    var alertDistance = 3.0
    var soundEnabled = false
    var hapticEnabled = true
    var updatedAt = Date()

    mutating func normalize() {
        customName = String(customName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        alertDistance = min(15, max(0.5, alertDistance))
        serviceUUIDs = Array(Set(serviceUUIDs.map { $0.uppercased() })).sorted().prefix(8).map { $0 }
    }
}

struct ProximityAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let bookmarkID: UUID
    let title: String
    let distance: Double
    let color: MarkerColor
    let icon: MarkerIcon
}

struct AlertGate: Sendable {
    private struct State: Sendable {
        var closeSamples = 0
        var isInside = false
        var lastFired = Date.distantPast
    }
    private var states: [UUID: State] = [:]
    var requiredSamples = 3
    var cooldown: TimeInterval = 60

    mutating func shouldFire(id: UUID, distance: Double, threshold: Double, now: Date) -> Bool {
        var state = states[id] ?? State()
        if distance > threshold * 1.25 {
            state.closeSamples = 0
            state.isInside = false
            states[id] = state
            return false
        }
        guard distance <= threshold else {
            states[id] = state
            return false
        }
        state.closeSamples += 1
        guard !state.isInside, state.closeSamples >= requiredSamples,
              now.timeIntervalSince(state.lastFired) >= cooldown else {
            states[id] = state
            return false
        }
        state.isInside = true
        state.lastFired = now
        states[id] = state
        return true
    }

    mutating func remove(id: UUID) { states.removeValue(forKey: id) }
}
