import Foundation
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var scanner: BLEScanner
    @Environment(\.presentationMode) private var presentationMode
    @State private var confirmReset = false

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                Section(header: Text("外观与夜间"),
                        footer: Text("额外加暗只覆盖 App 内容，不会修改系统屏幕亮度。OLED 黑与夜视红更适合夜间。")) {
                    Picker("页面主题", selection: binding(\.theme)) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("额外加暗：\(Int(scanner.userSettings.extraDim * 100))%")
                        Slider(value: binding(\.extraDim), in: 0...0.72, step: 0.04)
                    }
                    Toggle("界面动画", isOn: binding(\.animationsEnabled))
                }

                Section(header: Text("运行模式"), footer: Text(scanner.userSettings.mode.summary)) {
                    Picker("性能配置", selection: binding(\.mode)) {
                        ForEach(PowerMode.allCases) { Text($0.title).tag($0) }
                    }
                    Text(scanner.effectiveProfileSummary)
                        .font(.caption).foregroundColor(.secondary)
                }

                Section(header: Text("信号稳定"),
                        footer: Text("灵敏响应更快；稳定模式抑制波动更强，但变化会稍慢。")) {
                    Picker("滤波强度", selection: binding(\.filterStrength)) {
                        ForEach(FilterStrength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("设备保护")) {
                    Toggle("按钮触觉反馈", isOn: binding(\.hapticsEnabled))
                    Toggle("跟随系统低电量模式", isOn: binding(\.automaticLowPower))
                    Toggle("设备过热时自动降载", isOn: binding(\.automaticThermalProtection))
                }

                Section(header: Text("后台监测"),
                        footer: Text("启用后使用 iOS 允许的蓝牙后台模式和状态恢复。系统仍可能降低扫描频率、挂起或终止 App；手动强制退出后不会自动恢复。")) {
                    Toggle("允许后台蓝牙恢复", isOn: binding(\.backgroundMonitoringEnabled))
                    valueRow("后台方式", "Core Bluetooth")
                }

                Section(header: Text("距离估算校准"),
                        footer: Text("参考信号是在约1米无遮挡位置测得的稳定 RSSI；环境系数越大，墙壁和人体遮挡的补偿越强。宿舍建议先使用默认值。")) {
                    Stepper("1米参考信号：\(scanner.userSettings.distanceReferenceRSSI) dBm",
                            value: binding(\.distanceReferenceRSSI), in: -85 ... -40)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("环境系数：\(scanner.userSettings.pathLossExponent, specifier: "%.1f")")
                        Slider(value: binding(\.pathLossExponent), in: 1.6...4, step: 0.1)
                    }
                }

                if scanner.userSettings.mode == .custom { customSection }

                Section(header: Text("设备适配"),
                        footer: Text("不识别手机型号；智能模式根据可用硬件级别、电量与温度选择参数。所有数据仅保存在本机。")) {
                    valueRow("设备内存", memoryDescription)
                    valueRow("最低系统", "iOS 15.0")
                    valueRow("传感器融合", scanner.motion.isAvailable ? "BLE + 运动姿态" : "BLE")
                    valueRow("当前保护", scanner.conservationForced ? "自动降载中" : "正常")
                }

                Section {
                    Button("恢复全部默认设置", role: .destructive) {
                        if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                        confirmReset = true
                    }
                }
                }
                ExtraDimOverlay(amount: scanner.userSettings.extraDim)
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $confirmReset) {
                Alert(title: Text("恢复默认设置？"),
                      message: Text("性能模式、滤波和自定义参数都会重置。"),
                      primaryButton: .destructive(Text("恢复")) { scanner.resetSettings() },
                      secondaryButton: .cancel())
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .tint(scanner.userSettings.theme.accent)
    }

    private var customSection: some View {
        Section(header: Text("自定义扫描参数"),
                footer: Text("休眠时间设为0秒时使用连续扫描。修改后立即生效。")) {
            Stepper("扫描时长：\(scanner.userSettings.customScanSeconds)秒",
                    value: binding(\.customScanSeconds), in: 3...30)
            Stepper("休眠时间：\(scanner.userSettings.customPauseSeconds)秒",
                    value: binding(\.customPauseSeconds), in: 0...60)

            VStack(alignment: .leading, spacing: 8) {
                Text("UI刷新：\(scanner.userSettings.customRefreshInterval, specifier: "%.2f")秒")
                Slider(value: binding(\.customRefreshInterval), in: 0.15...3, step: 0.05)
            }

            Stepper("信号过期：\(scanner.userSettings.customStaleAfter)秒",
                    value: binding(\.customStaleAfter), in: 10...180, step: 5)
            Stepper("内存源上限：\(scanner.userSettings.customMaxSources)",
                    value: binding(\.customMaxSources), in: 32...256, step: 16)
            Stepper("屏幕显示上限：\(scanner.userSettings.customDisplayLimit)",
                    value: binding(\.customDisplayLimit), in: 12...100, step: 4)
        }
    }

    private var memoryDescription: String {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>) -> Binding<Value> {
        Binding(get: { scanner.userSettings[keyPath: keyPath] },
                set: { scanner.updateSetting(keyPath, to: $0) })
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary) }
    }
}
