import SwiftUI

@MainActor
struct BookmarkEditorView: View {
    @ObservedObject var scanner: BLEScanner
    private let placeholder: String
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: DeviceBookmark
    private let existedAtOpen: Bool
    @State private var writeError: String?

    init(scanner: BLEScanner, source: BLESource) {
        let existing = scanner.bookmark(for: source)
        self.init(scanner: scanner, draft: existing ?? scanner.draftBookmark(for: source),
                  placeholder: source.reportedName ?? "输入设备名称", exists: existing != nil)
    }

    init(scanner: BLEScanner, draft: DeviceBookmark, placeholder: String, exists: Bool = true) {
        self.scanner = scanner
        self.placeholder = placeholder
        _draft = State(initialValue: draft)
        existedAtOpen = exists
    }

    private func finish(_ change: () throws -> Void) {
        do {
            try change()
            presentationMode.wrappedValue.dismiss()
        } catch {
            writeError = "无法写入设备标记，请解锁手机后重试。"
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                Section(header: Text("标记名称"),
                        footer: Text("标记保存在本机。再次收到相同的 iOS 设备标识时会显示此标记。")) {
                    TextField(placeholder, text: $draft.customName)
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
                            finish { try scanner.removeBookmark(draft) }
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
                        finish { try scanner.saveBookmark(draft) }
                    }
                }
            }
        }
        .alert("保存标记失败", isPresented: Binding(
            get: { writeError != nil }, set: { if !$0 { writeError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(writeError ?? "")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .tint(scanner.userSettings.theme.accent)
    }
}
