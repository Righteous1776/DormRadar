import Foundation
import SwiftUI

@MainActor
struct DeviceDetailView: View {
    @ObservedObject var scanner: BLEScanner
    let source: BLESource
    @Environment(\.presentationMode) private var presentationMode
    @State private var showBookmarkEditor = false

    private var settings: UserSettings { scanner.userSettings }
    private var bookmark: DeviceBookmark? { scanner.bookmark(for: source) }

    var body: some View {
        NavigationView {
            ZStack {
                settings.theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 14) {
                        identityCard
                        bookmarkCard
                        estimateCard
                        broadcastCard
                        accuracyNotice
                    }
                    .padding(16)
                }
                ExtraDimOverlay(amount: settings.extraDim)
            }
            .navigationTitle("信号详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if settings.hapticsEnabled { Haptics.tap(.light) }
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .tint(settings.theme.accent)
        .sheet(isPresented: $showBookmarkEditor) {
            BookmarkEditorView(scanner: scanner, source: source)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(signalColor.opacity(0.16))
                Image(systemName: deviceIcon)
                    .font(.system(size: 26, weight: .semibold)).foregroundColor(signalColor)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(scanner.displayName(for: source)).font(.title3.bold()).lineLimit(2)
                Text(source.deviceTypeLabel).font(.subheadline).foregroundColor(.white.opacity(0.62))
                Text(source.manufacturerLabel).font(.caption).foregroundColor(.cyan)
            }
            Spacer(minLength: 0)
        }
        .detailCard()
    }

    private var bookmarkCard: some View {
        Button {
            if settings.hapticsEnabled { Haptics.tap(.light) }
            showBookmarkEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: bookmark?.icon.rawValue ?? "bookmark")
                    .foregroundColor(bookmark?.color.swiftUIColor ?? settings.theme.accent)
                    .frame(width: 38, height: 38)
                    .background((bookmark?.color.swiftUIColor ?? settings.theme.accent).opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark == nil ? "标记并自定义" : "编辑设备标记").font(.subheadline.bold())
                    Text(bookmark?.alertEnabled == true ? "接近提醒已开启" : "名称、颜色、图标和提醒")
                        .font(.caption).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.white.opacity(0.4))
            }
            .foregroundColor(.white)
        }
        .buttonStyle(PhysicalPressStyle())
        .detailCard()
    }

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("多传感器位置估算", systemImage: "scope").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(distanceText).font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(source.proximityLabel(referenceRSSI: settings.distanceReferenceRSSI,
                                           pathLossExponent: settings.pathLossExponent))
                    .font(.subheadline.weight(.semibold)).foregroundColor(signalColor)
            }
            SignalBars(level: signalLevel, color: signalColor)
            detailRow("预测区间", distanceRangeText)
            detailRow("变化趋势", source.trendLabel)
            detailRow("相对方向", source.directionLabel)
            detailRow("信号可信度", source.confidenceLabel)
            detailRow("静止样本占比", stationarySampleText)
            detailRow("稳定信号", "\(Int(source.stableRSSI.rounded())) dBm")
            detailRow("原始信号", "\(source.rawRSSI) dBm")
        }
        .detailCard()
    }

    private var broadcastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("广播信息").font(.headline)
            detailRow("会话编号", source.displayName)
            detailRow("广播名称", source.localName ?? "未提供")
            detailRow("厂商", source.manufacturerLabel)
            detailRow("可连接", connectableText)
            detailRow("发射功率", source.txPower.map { "\($0) dBm" } ?? "未提供")
            detailRow("样本数量", "\(source.sampleCount)")
            if !source.serviceLabels.isEmpty {
                Divider().background(Color.white.opacity(0.12))
                Text("服务类型").font(.caption).foregroundColor(.white.opacity(0.5))
                ForEach(source.serviceLabels, id: \.self) { service in
                    Text(service).font(.footnote).textSelection(.enabled)
                }
            }
        }
        .detailCard()
    }

    private var accuracyNotice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("测量边界", systemImage: "info.circle.fill").font(.subheadline.bold())
            Text("融合 BLE 强度、广播发射信息、加速度/陀螺仪和旋转角度。距离以米和区间表达，但墙壁、人体、口袋及目标发射功率仍会造成误差；相对方向需要站在原地缓慢转一圈，不能当作精确方位角。")
                .font(.caption).foregroundColor(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
        }
        .detailCard()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundColor(.white.opacity(0.56))
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var estimatedDistance: Double {
        source.estimatedDistance(referenceRSSI: settings.distanceReferenceRSSI,
                                 pathLossExponent: settings.pathLossExponent)
    }
    private var distanceText: String {
        if estimatedDistance < 0.1 { return "≈ <0.1 m" }
        if estimatedDistance < 10 { return String(format: "≈ %.1f m", estimatedDistance) }
        if estimatedDistance > 99 { return "≈ 99+ m" }
        return String(format: "≈ %.0f m", estimatedDistance)
    }
    private var distanceRangeText: String {
        let range = source.estimatedDistanceRange(referenceRSSI: settings.distanceReferenceRSSI,
                                                  pathLossExponent: settings.pathLossExponent)
        return String(format: "%.1f–%.1f m", range.lowerBound, range.upperBound)
    }
    private var stationarySampleText: String {
        let count = source.stationarySampleCount + source.movingSampleCount
        guard count > 0 else { return "运动传感器无数据" }
        return "\(Int((source.stationaryRatio * 100).rounded()))%"
    }
    private var connectableText: String {
        guard let connectable = source.isConnectable else { return "未知" }
        return connectable ? "是" : "否"
    }
    private var signalLevel: Int {
        if source.stableRSSI >= -55 { return 5 }
        if source.stableRSSI >= -65 { return 4 }
        if source.stableRSSI >= -75 { return 3 }
        if source.stableRSSI >= -88 { return 2 }
        return 1
    }
    private var signalColor: Color {
        if source.stableRSSI >= -60 { return .green }
        if source.stableRSSI >= -76 { return .orange }
        return .blue
    }
    private var deviceIcon: String {
        if source.deviceTypeLabel.contains("耳机") { return "earbuds" }
        if source.deviceTypeLabel.contains("手表") { return "applewatch" }
        if source.deviceTypeLabel.contains("输入") { return "keyboard" }
        return "antenna.radiowaves.left.and.right"
    }
}

private struct SignalBars: View {
    let level: Int
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(1...5, id: \.self) { index in
                Capsule()
                    .fill(index <= level ? color : Color.white.opacity(0.12))
                    .frame(height: CGFloat(6 + index * 5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("信号强度 \(level) 格，共 5 格")
    }
}

private extension View {
    func detailCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
