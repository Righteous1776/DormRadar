import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var scanner: BLEScanner
    @Environment(\.presentationMode) private var presentationMode
    @State private var confirmReset = false

    var body: some View {
        NavigationView {
            Form {
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

                if scanner.userSettings.mode == .custom { customSection }

                Section(header: Text("设备适配"),
                        footer: Text("不识别手机型号；智能模式根据可用硬件级别、电量与温度选择参数。所有数据仅保存在本机。")) {
                    valueRow("设备内存", memoryDescription)
                    valueRow("最低系统", "iOS 15.0")
                    valueRow("当前保护", scanner.conservationForced ? "自动降载中" : "正常")
                }

                Section {
                    Button("恢复全部默认设置", role: .destructive) {
                        if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                        confirmReset = true
                    }
                }
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
