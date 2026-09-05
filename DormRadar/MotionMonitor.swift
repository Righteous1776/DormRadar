@preconcurrency import CoreMotion
import Combine
import Foundation

@MainActor
final class MotionMonitor: ObservableObject {
    @Published private(set) var isAvailable = false
    @Published private(set) var isMoving = false
    @Published private(set) var relativeYawDegrees: Double?
    @Published private(set) var motionScore = 0.0

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "DormRadar.Motion"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var originYaw: Double?
    private var movingVotes = 0

    func start(updateInterval: TimeInterval) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else {
            isAvailable = manager.isDeviceMotionAvailable
            return
        }
        isAvailable = true
        manager.deviceMotionUpdateInterval = max(0.10, updateInterval)
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xMagneticNorthZVertical)
            ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical
        manager.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] motion, _ in
            guard let motion else { return }
            let acceleration = motion.userAcceleration
            let rotation = motion.rotationRate
            let accelerationMagnitude = sqrt(acceleration.x * acceleration.x +
                                             acceleration.y * acceleration.y +
                                             acceleration.z * acceleration.z)
            let rotationMagnitude = sqrt(rotation.x * rotation.x + rotation.y * rotation.y +
                                         rotation.z * rotation.z)
            let score = min(1, accelerationMagnitude * 5 + rotationMagnitude * 0.35)
            let yaw = motion.attitude.yaw
            Task { @MainActor [weak self] in self?.accept(score: score, yaw: yaw) }
        }
    }

    func configure(updateInterval: TimeInterval) {
        manager.deviceMotionUpdateInterval = max(0.10, updateInterval)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        originYaw = nil
        movingVotes = 0
        isMoving = false
        relativeYawDegrees = nil
        motionScore = 0
    }

    private func accept(score: Double, yaw: Double) {
        if originYaw == nil { originYaw = yaw }
        let origin = originYaw ?? yaw
        var difference = (yaw - origin) * 180 / .pi
        while difference < 0 { difference += 360 }
        while difference >= 360 { difference -= 360 }
        relativeYawDegrees = difference
        motionScore = 0.22 * score + 0.78 * motionScore
        movingVotes = max(0, min(5, movingVotes + (motionScore > 0.16 ? 1 : -1)))
        isMoving = movingVotes >= 3
    }
}
