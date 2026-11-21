import SwiftUI

@MainActor
struct BookmarkListView: View {
    @ObservedObject var scanner: BLEScanner
    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedBookmark: DeviceBookmark?

    var body: some View {
        NavigationView {
            List {
                if scanner.bookmarkStorageUnavailable {
                    Text("标记数据库暂时无法读取。").foregroundColor(.orange)
                }
                if scanner.bookmarks.isEmpty && !scanner.bookmarkStorageUnavailable {
                    Text("从附近信号选择设备，打开详情添加标记。")
                        .foregroundColor(.secondary)
                }
                ForEach(scanner.bookmarks) { bookmark in
                    Button {
                        selectedBookmark = bookmark
                    } label: {
                        HStack {
                            Label(bookmark.customName.isEmpty ? "未命名标记" : bookmark.customName,
                                  systemImage: bookmark.icon.rawValue)
                                .foregroundColor(bookmark.color.swiftUIColor)
                            Spacer()
                            if bookmark.alertEnabled {
                                Image(systemName: "bell.fill")
                                    .accessibilityLabel("接近提醒已开启")
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("设备标记")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(item: $selectedBookmark) { bookmark in
                BookmarkEditorView(scanner: scanner, draft: bookmark, placeholder: "输入设备名称")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .tint(scanner.userSettings.theme.accent)
    }
}
