import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BLEScanner()
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.08),
                                        Color(red: 0.02, green: 0.09, blue: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                        scannerButton
                        modePicker
                        if scanner.conservationForced { conservationNotice }
                        diagnostics
                        sourceList
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(scanner: scanner) }
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
                    if scanner.userSettings.hapticsEnabled { Haptics.tap(.light) }
                    showSettings = true
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
                Text(scanner.userSettings.mode.title).foregroundColor(.cyan)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.top, 18)
    }

    private var scannerButton: some View {
        Button(action: scanner.toggle) {
            ZStack {
                Circle().fill(scanner.isRunning ? Color.red.opacity(0.16) : Color.cyan.opacity(0.12))
                Circle().stroke(scanner.isRunning ? Color.red : Color.cyan, lineWidth: 2)
                VStack(spacing: 8) {
                    Image(systemName: scanner.isRunning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 34, weight: .semibold))
                    Text(scanner.isRunning ? "停止监测" : "开始监测").font(.headline)
                    if scanner.isRunning && scanner.isUsingUltraEco {
                        Text(scanner.isActivelyScanning ? "采集中" : "省电休眠")
                            .font(.caption2).foregroundColor(.white.opacity(0.6))
                    }
                }
                .foregroundColor(scanner.isRunning ? .red : .cyan)
            }
            .frame(width: 150, height: 150)
        }
        .buttonStyle(PhysicalPressStyle())
        .contentShape(Circle())
        .accessibilityLabel(scanner.isRunning ? "停止监测" : "开始监测")
        .accessibilityHint("双击切换蓝牙扫描状态")
        .padding(.vertical, 4)
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "speedometer").foregroundColor(.cyan)
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
        .card()
    }

    private var diagnostics: some View {
        HStack(spacing: 10) {
            MetricCard(value: "\(scanner.activeSourceCount)", title: "活动源", icon: "antenna.radiowaves.left.and.right")
            MetricCard(value: scanner.callbacksPerSecond.formatted(.number.precision(.fractionLength(1))),
                       title: "每秒回调", icon: "waveform.path.ecg")
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
                        .font(.system(size: 30)).foregroundColor(.cyan.opacity(0.7))
                    Text(scanner.isRunning ? "正在等待 BLE 广播" : "开始后显示匿名信号源")
                        .font(.subheadline).foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 34)
                .card()
            } else {
                ForEach(scanner.sources) { SourceRow(source: $0) }
            }
        }
    }

    private var modeDescription: String {
        scanner.userSettings.mode.summary
    }
}

private struct MetricCard: View {
    let value: String, title: String, icon: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.cyan)
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
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(signalColor.opacity(0.14))
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(signalColor)
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.displayName).font(.headline)
                Text("\(source.sampleCount)个样本 · \(source.ageLabel())")
                    .font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(source.stableRSSI.rounded())) dBm").font(.body.weight(.semibold)).monospacedDigit()
                Text(source.stabilityLabel).font(.caption2).foregroundColor(.white.opacity(0.45))
            }
        }
        .card()
    }

    private var signalColor: Color {
        if source.stableRSSI >= -60 { return .green }
        if source.stableRSSI >= -76 { return .orange }
        return .blue
    }
}

private struct PhysicalPressStyle: ButtonStyle {
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
