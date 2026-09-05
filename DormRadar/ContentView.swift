import SwiftUI

private enum ActiveSheet: Identifiable {
    case settings
    case source(BLESource)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .source(let source): return source.id.uuidString
        }
    }
}

@MainActor
struct ContentView: View {
    @StateObject private var scanner = BLEScanner()
    @State private var activeSheet: ActiveSheet?
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationView {
            ZStack {
                scanner.userSettings.theme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                        scannerButton
                        modePicker
                        if scanner.conservationForced { conservationNotice }
                        diagnostics
                        fusionStatus
                        sourceList
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                if let alert = scanner.lastAlert {
                    AlertBanner(alert: alert, dismiss: scanner.dismissAlert)
                        .padding(.horizontal, 16).frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                }
                ExtraDimOverlay(amount: scanner.userSettings.extraDim).zIndex(3)
            }
            .navigationBarHidden(true)
            .tint(scanner.userSettings.theme.accent)
            .animation(animation, value: scanner.lastAlert?.id)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings: SettingsView(scanner: scanner)
            case .source(let source):
                DeviceDetailView(scanner: scanner, source: source)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DormRadar").font(.system(.title, design: .rounded).weight(.bold))
                    Text("匿名近场活动监测").font(.caption).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Button {
                    let next = scanner.userSettings.extraDim > 0.1 ? 0.0 : 0.55
                    scanner.updateSetting(\.extraDim, to: next)
                    if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                } label: {
                    Image(systemName: scanner.userSettings.extraDim > 0.1 ? "moon.fill" : "moon")
                        .font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08)).clipShape(Circle())
                }
                .buttonStyle(PhysicalPressStyle()).accessibilityLabel("快速夜间加暗")
                Button {
                    if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                    activeSheet = .settings
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PhysicalPressStyle())
                .accessibilityLabel("设置")
            }
            HStack {
                Label(scanner.bluetoothState,
                      systemImage: scanner.bluetoothState == "蓝牙就绪" ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(scanner.bluetoothState == "蓝牙就绪" ? .mint : .orange)
                Spacer()
                Text(scanner.userSettings.mode.title).foregroundColor(scanner.userSettings.theme.accent)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.top, 18)
    }

    private var scannerButton: some View {
        Button(action: scanner.toggle) {
            ZStack {
                if scanner.isRunning && scanner.userSettings.animationsEnabled && !reduceMotion && !scanner.isUsingUltraEco {
                    Circle().stroke(scanner.userSettings.theme.accent.opacity(0.28), lineWidth: 2)
                        .scaleEffect(pulse ? 1.24 : 0.92).opacity(pulse ? 0 : 0.8)
                }
                Circle().fill(scanner.isRunning ? Color.red.opacity(0.16) : scanner.userSettings.theme.accent.opacity(0.12))
                Circle().stroke(scanner.isRunning ? Color.red : scanner.userSettings.theme.accent, lineWidth: 2)
                VStack(spacing: 8) {
                    Image(systemName: scanner.isRunning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 34, weight: .semibold))
                    Text(scanner.isRunning ? "停止监测" : "开始监测").font(.headline)
                    if scanner.isRunning && scanner.isUsingUltraEco {
                        Text(scanner.isActivelyScanning ? "采集中" : "省电休眠")
                            .font(.caption2).foregroundColor(.white.opacity(0.6))
                    }
                }
                .foregroundColor(scanner.isRunning ? .red : scanner.userSettings.theme.accent)
            }
            .frame(width: 150, height: 150)
        }
        .buttonStyle(PhysicalPressStyle())
        .contentShape(Circle())
        .accessibilityLabel(scanner.isRunning ? "停止监测" : "开始监测")
        .accessibilityHint("双击切换蓝牙扫描状态")
        .padding(.vertical, 4)
        .onAppear { updatePulse() }
        .onChange(of: scanner.isRunning) { _ in updatePulse() }
        .onChange(of: scanner.userSettings.animationsEnabled) { _ in updatePulse() }
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "speedometer").foregroundColor(scanner.userSettings.theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(scanner.userSettings.mode.title).font(.subheadline.weight(.semibold))
                Text(modeDescription).font(.caption).foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Menu {
                ForEach(PowerMode.allCases) { mode in
                    Button(mode.title) { scanner.setMode(mode) }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
        }
        .foregroundColor(.white)
        .card()
    }

    private var diagnostics: some View {
        HStack(spacing: 10) {
            MetricCard(value: "\(scanner.activeSourceCount)", title: "活动源", icon: "antenna.radiowaves.left.and.right",
                       color: scanner.userSettings.theme.accent)
            MetricCard(value: scanner.callbacksPerSecond.formatted(.number.precision(.fractionLength(1))),
                       title: "每秒回调", icon: "waveform.path.ecg", color: scanner.userSettings.theme.accent)
        }
    }

    private var conservationNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(scanner.conservationReason).font(.subheadline.weight(.semibold))
                Text("扫描暂时按超级省电参数运行").font(.caption).foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var fusionStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("BLE", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                Label(scanner.motion.isAvailable ? "运动融合" : "仅蓝牙",
                      systemImage: scanner.motion.isAvailable ? "gyroscope" : "exclamationmark.triangle")
            }
            .font(.caption.weight(.semibold)).foregroundColor(scanner.userSettings.theme.accent)
            Text(scanner.motion.isAvailable
                 ? "已用加速度、陀螺仪和旋转角度抑制移动误差；原地缓慢转一圈可积累相对方向证据。"
                 : "当前设备未提供运动数据，距离区间会保持保守。")
                .font(.caption).foregroundColor(.white.opacity(0.52))
        }
        .card()
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("附近信号").font(.headline)
                Spacer()
                Text(scanner.activeSourceCount > scanner.sources.count
                     ? "显示前\(scanner.sources.count)个" : "仅本次会话")
                    .font(.caption).foregroundColor(.white.opacity(0.45))
            }
            if scanner.sources.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 30)).foregroundColor(scanner.userSettings.theme.accent.opacity(0.7))
                    Text(scanner.isRunning ? "正在等待 BLE 广播" : "开始后显示匿名信号源")
                        .font(.subheadline).foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 34)
                .card()
            } else {
                ForEach(scanner.sources) { source in
                    Button {
                        if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                        activeSheet = .source(source)
                    } label: {
                        SourceRow(source: source, settings: scanner.userSettings,
                                  displayName: scanner.displayName(for: source),
                                  bookmark: scanner.bookmark(for: source))
                    }
                    .buttonStyle(PhysicalPressStyle())
                    .accessibilityHint("打开广播信息和距离估算")
                }
            }
        }
    }

    private var modeDescription: String {
        scanner.userSettings.mode.summary
    }

    private var animation: Animation? {
        reduceMotion || !scanner.userSettings.animationsEnabled ? nil : .spring(response: 0.34, dampingFraction: 0.86)
    }

    private func updatePulse() {
        guard scanner.isRunning, scanner.userSettings.animationsEnabled,
              !reduceMotion, !scanner.isUsingUltraEco else { pulse = false; return }
        pulse = false
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
    }
}

private struct MetricCard: View {
    let value: String, title: String, icon: String
    let color: Color
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.bold()).monospacedDigit()
                Text(title).font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity).card()
    }
}

private struct SourceRow: View {
    let source: BLESource
    let settings: UserSettings
    let displayName: String
    let bookmark: DeviceBookmark?
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((bookmark?.color.swiftUIColor ?? signalColor).opacity(0.14))
                Image(systemName: bookmark?.icon.rawValue ?? "antenna.radiowaves.left.and.right")
                    .foregroundColor(bookmark?.color.swiftUIColor ?? signalColor)
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(displayName).font(.headline).lineLimit(1)
                    if bookmark != nil { Image(systemName: "bookmark.fill").font(.caption2).foregroundColor(bookmark?.color.swiftUIColor) }
                }
                Text("\(source.sampleCount)个样本 · \(source.ageLabel())")
                    .font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(distanceText).font(.body.weight(.semibold)).monospacedDigit()
                Text(source.trendLabel).font(.caption2).foregroundColor(.white.opacity(0.45))
            }
        }
        .foregroundColor(.white)
        .card()
    }

    private var signalColor: Color {
        if source.stableRSSI >= -60 { return .green }
        if source.stableRSSI >= -76 { return .orange }
        return .blue
    }

    private var distanceText: String {
        let distance = source.estimatedDistance(referenceRSSI: settings.distanceReferenceRSSI,
                                                pathLossExponent: settings.pathLossExponent)
        if distance < 0.1 { return "≈ <0.1 m" }
        if distance < 10 { return String(format: "≈ %.1f m", distance) }
        if distance > 99 { return "≈ 99+ m" }
        return String(format: "≈ %.0f m", distance)
    }
}

private struct AlertBanner: View {
    let alert: ProximityAlert
    let dismiss: () -> Void
    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 12) {
                Image(systemName: alert.icon.rawValue).foregroundColor(alert.color.swiftUIColor)
                    .frame(width: 36, height: 36).background(alert.color.swiftUIColor.opacity(0.16)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("已标记设备接近").font(.subheadline.bold())
                    Text("\(alert.title) · 约 \(alert.distance, specifier: "%.1f") 米")
                        .font(.caption).foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "xmark").font(.caption)
            }
            .foregroundColor(.white).padding(12)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        }
        .buttonStyle(PhysicalPressStyle())
    }
}

struct PhysicalPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension View {
    func card() -> some View {
        padding(14)
            .background(Color.white.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

@MainActor
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
