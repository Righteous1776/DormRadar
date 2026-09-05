import SwiftUI

struct BookmarkEditorView: View {
    @ObservedObject var scanner: BLEScanner
    let source: BLESource
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: DeviceBookmark
    private let existedAtOpen: Bool

    init(scanner: BLEScanner, source: BLESource) {
        self.scanner = scanner
        self.source = source
        let existing = scanner.bookmark(for: source)
        _draft = State(initialValue: existing ?? scanner.draftBookmark(for: source))
        existedAtOpen = existing != nil
    }

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                Section(header: Text("标记名称"),
                        footer: Text("标记保存在本机。下次识别到同一设备时继续显示；请只标记你拥有或获授权管理的设备。")) {
                    TextField(source.primaryName, text: $draft.customName)
                        .textInputAutocapitalization(.never)
                }

                Section(header: Text("个性化")) {
                    Picker("颜色", selection: $draft.color) {
                        ForEach(MarkerColor.allCases) { color in
                            Label(color.title, systemImage: "circle.fill")
                                .foregroundColor(color.swiftUIColor).tag(color)
                        }
                    }
                    Picker("图标", selection: $draft.icon) {
                        ForEach(MarkerIcon.allCases) { icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(icon)
                        }
                    }
                }

                Section(header: Text("接近预警"),
                        footer: Text("需连续3次进入范围才触发，并有60秒冷却。距离是信号估算，不代表人员身份或精确位置。")) {
                    Toggle("启用接近提醒", isOn: $draft.alertEnabled)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("触发距离：约 \(draft.alertDistance, specifier: "%.1f") 米")
                        Slider(value: $draft.alertDistance, in: 0.5...15, step: 0.5)
                    }
                    .disabled(!draft.alertEnabled)
                    Toggle("通知声音", isOn: $draft.soundEnabled)
                        .disabled(!draft.alertEnabled)
                    Toggle("前台震动", isOn: $draft.hapticEnabled)
                        .disabled(!draft.alertEnabled)
                }

                Section(footer: Text("默认静音。App 在后台时，震动由 iOS 的通知与静音设置决定，无法保证与声音完全独立。")) {
                    Label(draft.soundEnabled ? "当前允许声音" : "当前为静音预警",
                          systemImage: draft.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(draft.soundEnabled ? .orange : .green)
                }

                if existedAtOpen {
                    Section {
                        Button("删除这个标记", role: .destructive) {
                            scanner.removeBookmark(draft)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                }
                ExtraDimOverlay(amount: scanner.userSettings.extraDim)
            }
            .navigationTitle("设备标记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        scanner.saveBookmark(draft)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .tint(scanner.userSettings.theme.accent)
    }
}
