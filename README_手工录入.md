# DormRadar V1.6（Milestone 0–1）

这是工程方案规定的第一阶段：真机 BLE 扫描、匿名源、实时 RSSI 列表、距离趋势、个性化标记、接近提醒和诊断测试。没有联网、麦克风、相机、服务器数据库或 App 内第三方依赖。

最低支持 iOS 15，目标设备为 iPhone，覆盖 iPhone 7、7 Plus 及所有能够运行 iOS 15 的更新机型。提供智能、超级省电、均衡、高响应、自定义五种模式，并支持触觉反馈、低电量自动保护和温度自动保护。

V1.5 在 V1.4 全屏与设备识别基础上加入多传感器融合：蓝牙 RSSI、广播发射信息、加速度计、陀螺仪和旋转姿态同步采样。手机移动时自动降低 RSSI 更新权重，详情页显示米制点估计、保守距离区间、静止样本比例和相对方向证据。

V1.6 加入本机持久化设备标记，可修改名称、图标和颜色；再次扫描到相同 Core Bluetooth 标识时自动恢复标记。具名设备还会使用保守的广播签名辅助恢复。每个标记可以独立设置接近距离、声音和前台震动，默认声音关闭。提醒需连续三次进入阈值，并使用回差和60秒冷却来降低误报。

页面提供深海蓝、OLED 黑、石墨灰、夜视红四种主题，支持0–72%额外加暗、快速月亮按钮和可关闭的轻量动画。超级省电模式与系统“减少动态效果”会关闭持续雷达动画。

后台使用 Apple 允许的 `bluetooth-central` 模式及 Core Bluetooth 状态恢复，不使用静音音频或定位滥用。iOS 仍可能降低后台发现频率、挂起或终止进程，用户手动强制退出后不能自动恢复，所以不承诺永久常驻。

相对方向通过用户站在原地缓慢旋转一圈后比较各角度信号强度获得，只能作为趋势参考。它不是 UWB 方位角，也不能保证任意室内环境达到一米以内误差。

设置页可持久保存扫描/休眠时长、UI 刷新间隔、信号过期时间、内存源上限、屏幕显示上限、滤波强度、1米参考信号和无线环境系数。旧版设置会自动迁移，不会因新增字段全部重置。

异步观测缓存限制为最新 256 条，维护 Timer 设置 20% 容差，列表使用惰性布局并限制显示数量；设置中不影响扫描参数的开关不会触发蓝牙重启。

## 源码规模

- 正式源码：11 个 Swift 文件
- 测试：1 个 Swift 文件，18 项测试
- 第三方依赖：0

## 手工录入顺序

如果使用 GitHub 手机网页，只需把 `DormRadar_iPhone_Source.zip` 上传到仓库根目录，然后等待现有工作流自动解压并构建 V1.6。压缩包不会修改 `.github/workflows`，避免触发机器人权限限制。

1. 在 Xcode 新建 iOS App：Product Name `DormRadar`，Interface `SwiftUI`，Language `Swift`，勾选 Include Tests。
2. Deployment Target 设为 iOS 15.0。
3. 用本包 `DormRadar` 文件夹中的同名文件替换模板；再新增其余 Swift 文件。
4. 将 `BLESourceRegistryTests.swift` 放进 `DormRadarTests` target。
5. Target → Info → Custom iOS Target Properties 新增：
   - Key：`Privacy - Bluetooth Always Usage Description`
   - Value：`DormRadar uses Bluetooth to show anonymous nearby BLE activity.`
   - `Privacy - Motion Usage Description`
   - `Required background modes` → `App communicates using CoreBluetooth`
6. 在真机运行。首次打开允许蓝牙，然后点“开始监测”。
7. Product → Test 运行十八项测试。

## 录入时必须检查 Target Membership

- `DormRadar` 文件夹中的全部 Swift 文件：只勾选 `DormRadar`。
- `BLESourceRegistryTests.swift`：只勾选 `DormRadarTests`。

## 验收

- 蓝牙状态显示“蓝牙就绪”。
- 点开始后能持续出现多个 `Source 1/2/3…`。
- RSSI、最后出现时间、样本数会更新。
- 过期源会按当前模式或自定义参数自动移除。
- 首页显示活动源数量与回调率；设置在重新启动后仍保留。
- 点击任一信号源可以查看广播信息、距离、趋势和可信度。
- 可以标记设备、修改名称/颜色/图标，重启 App 后标记仍在。
- 静音接近提醒默认开启声音为否；连续进入阈值后出现提醒。
- 十八项单元测试全部通过。

模拟器通常无法提供真实 BLE 扫描结果，必须以 iPhone 真机为准。RSSI 距离属于环境模型估算；普通 iPhone 的 Core Bluetooth 扫描不能测得任意设备的精确方位角。
