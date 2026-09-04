# DormRadar V1.3（Milestone 0–1）

这是工程方案规定的第一阶段：真机 BLE 扫描、会话级匿名源、实时 RSSI 列表、诊断和登记表测试。没有测距公式、联网、麦克风、相机、数据库或 App 内第三方依赖。

最低支持 iOS 15，目标设备为 iPhone，覆盖 iPhone 7、7 Plus 及所有能够运行 iOS 15 的更新机型。提供智能、超级省电、均衡、高响应、自定义五种模式，并支持触觉反馈、低电量自动保护和温度自动保护。

V1.3 新增可持久保存的设置页。自定义模式可调整扫描/休眠时长、UI 刷新间隔、信号过期时间、内存源上限、屏幕显示上限和滤波强度。智能模式依据设备内存级别、电量与温度选取参数，不写死具体型号。

异步观测缓存限制为最新 256 条，维护 Timer 设置 20% 容差，列表使用惰性布局并限制显示数量；设置中不影响扫描参数的开关不会触发蓝牙重启。

## 源码规模

- 正式源码：5 个 Swift 文件
- 测试：1 个 Swift 文件，8 项测试
- 第三方依赖：0

## 手工录入顺序

1. 在 Xcode 新建 iOS App：Product Name `DormRadar`，Interface `SwiftUI`，Language `Swift`，勾选 Include Tests。
2. Deployment Target 设为 iOS 15.0。
3. 用本包 `DormRadar` 文件夹中的同名文件替换模板；再新增 `BLECore.swift`、`BLEScanner.swift`、`SettingsView.swift`。
4. 将 `BLESourceRegistryTests.swift` 放进 `DormRadarTests` target。
5. Target → Info → Custom iOS Target Properties 新增：
   - Key：`Privacy - Bluetooth Always Usage Description`
   - Value：`DormRadar uses Bluetooth to show anonymous nearby BLE activity.`
6. 在真机运行。首次打开允许蓝牙，然后点“开始监测”。
7. Product → Test 运行八项测试。

## 录入时必须检查 Target Membership

- `DormRadarApp.swift`、`BLECore.swift`、`BLEScanner.swift`、`ContentView.swift`、`SettingsView.swift`：只勾选 `DormRadar`。
- `BLESourceRegistryTests.swift`：只勾选 `DormRadarTests`。

## 验收

- 蓝牙状态显示“蓝牙就绪”。
- 点开始后能持续出现多个 `Source 1/2/3…`。
- RSSI、最后出现时间、样本数会更新。
- 过期源会按当前模式或自定义参数自动移除。
- 首页显示活动源数量与回调率；设置在重新启动后仍保留。
- 八项单元测试全部通过。

模拟器通常无法提供真实 BLE 扫描结果，必须以 iPhone 真机为准。本阶段的 RSSI 只是原始信号，不代表距离。
