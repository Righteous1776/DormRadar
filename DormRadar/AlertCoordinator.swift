import Foundation
import UIKit
import AudioToolbox
@preconcurrency import UserNotifications

@MainActor
final class AlertCoordinator {
    private var gate = AlertGate()

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func evaluate(source: BLESource, bookmark: DeviceBookmark,
                  settings: UserSettings) -> ProximityAlert? {
        guard bookmark.alertEnabled, source.sampleCount >= 4 else { return nil }
        let distance = source.estimatedDistance(referenceRSSI: settings.distanceReferenceRSSI,
                                                pathLossExponent: settings.pathLossExponent)
        guard gate.shouldFire(id: bookmark.id, distance: distance,
                              threshold: bookmark.alertDistance, now: source.lastSeen) else { return nil }
        let name = bookmark.customName.isEmpty ? source.primaryName : bookmark.customName
        let alert = ProximityAlert(bookmarkID: bookmark.id, title: name, distance: distance,
                                   color: bookmark.color, icon: bookmark.icon)
        if UIApplication.shared.applicationState == .active {
            if bookmark.soundEnabled { AudioServicesPlaySystemSound(1007) }
            if bookmark.hapticEnabled { Haptics.tap(.heavy) }
        } else {
            let content = UNMutableNotificationContent()
            content.title = "已标记设备接近"
            content.body = "\(name) 进入设定范围"
            content.sound = bookmark.soundEnabled ? .default : nil
            let request = UNNotificationRequest(identifier: "dormradar-\(bookmark.id.uuidString)",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        return alert
    }

    func remove(bookmarkID: UUID) { gate.remove(id: bookmarkID) }
}
