# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

PixelFit（前身 HiDPIBuddy）是一个原生 macOS 菜单栏 + 主窗口工具：选择 HiDPI 模式、为缺失档位安装物理显示器 Override 配置、可选的实验性虚拟显示器镜像，以及通过 DDC/CI 调节外接屏亮度 / 对比度 / 音量（2026-11 产品定位从「只管理分辨率」扩展为融合 MonitorControl 的硬件控制）。SwiftPM 项目，无 Xcode 工程、无外部依赖，macOS 14+，发布包仅 arm64。

## 常用命令

```bash
swift build                                   # 编译
swift test                                    # 全部测试（Swift Testing，需 Xcode 16+ / Swift 6）
swift test --filter PhysicalHiDPIConfigurationTests          # 单个 Suite
swift test --filter "PhysicalHiDPIConfigurationTests/preservesFieldsAndExistingScaleEntries"  # 单个测试

./script/build_and_run.sh --build             # 只打包 dist/PixelFit.app，不杀/不启动现有 App（开发构建也用 Developer ID 签名，无时间戳）
./script/build_and_run.sh                     # pkill 旧进程 → 打包 → 打开
./script/build_and_run.sh --logs              # 打开并 log stream（--telemetry 按 subsystem 过滤）
./script/build_and_run.sh --release           # 需 SIGN_IDENTITY="Developer ID Application: ..."；只签名不公证

swift run PixelFit diagnose --all --json      # 只读 CLI：help / list / status / get / diagnose
./script/generate_icon.sh                     # 仅改 Resources/AppIcon-artwork.png 后需要（compose_icon.swift 套 macOS 圆角与投影）
```

版本号与 build 号在 `script/build_and_run.sh`（`APP_VERSION` / `APP_BUILD`）里写入 Info.plist，发版时同时更新 README 中的下载链接与版本。

## 架构

`Package.swift` 有两个 executable target：

- **PixelFit**：`path: "."` + 显式 `sources: [App, Views, Models, Stores, Services, Support]`。新增顶层源码目录必须加进 `sources`，新增顶层非源码目录要加进 `exclude`。
- **PixelFitVirtualDisplayHelper**（`NativeVirtualDisplay/main.m`）：独立 ObjC 进程，调用私有 `CGVirtualDisplay`。打包时被复制进 `Contents/MacOS/`，release 签名先签 helper 再签 App。

运行时流程：

- `App/PixelFitApp.swift` 的 `init()` 先跑 `CLIService.runIfNeeded()`（有命令行参数就执行只读 CLI 并 `exit`），再做单实例检查（同 Bundle ID 激活最早实例后退出），最后创建 `DisplayStore`。
- `Stores/DisplayStore.swift`（`@Observable @MainActor`）是唯一状态中心，持有所有 service，View 只调用它。关键安全机制都在这里：
  - 原生模式切换走 `pendingModeChange` + 15 秒 rollback timer，用户不确认就自动恢复；App 退出时也会 rollback 并停止虚拟会话。
  - 确认阶段由 `Support/ResolutionConfirmationPanel.swift` 在目标屏幕上弹出浮动面板（Return 保留 / Esc 恢复），因为菜单栏窗口会在屏幕重配置时关闭。新增进入/退出确认状态的路径时，要同步调用 `confirmationPanel.show/hide`。
  - 预设通过 `DisplayPresetMode.matchingDisplay` 按 VID/PID/序列号匹配屏幕（`CGDirectDisplayID` 重连后可能改变），`DisplayPreset.resolve` 全有或全无。
  - 监听 `didChangeScreenParametersNotification` 自动刷新显示器列表。
- `Services/`：
  - `DisplayDiscoveryService` 枚举显示器与模式：优先私有 CGS API（`CGSDisplayModeAPI`），公开 CoreGraphics 作为回退。
  - `MonitorControlService` 应用模式：有 `cgsModeNumber` 走 CGS，否则走 `CGConfigureDisplayWithDisplayMode`（名字是历史遗留，现在只做分辨率）。
  - `PhysicalHiDPIConfiguration` 是纯函数，生成 Override plist（保留原有字段和 scale-resolutions，追加 8 字节双倍渲染尺寸条目）——主要测试对象。
  - `PhysicalHiDPIService` 负责安装 / 恢复 `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-*/DisplayProductID-*`：通过 `osascript ... with administrator privileges` 运行内嵌在 Swift 里的 `/usr/bin/ruby` 事务脚本，备份与 receipt（含 SHA256 摘要）存于 `/Library/Application Support/HiDPIBuddy`。状态由摘要比对得出 installed / restored / conflict；摘要不符时拒绝覆盖。测试用 `init(testPaths:)` 指向沙盒目录、`authorize: false`，绝不触发管理员授权。
  - `VirtualHiDPIService` 启动 helper 子进程，通过 stdout JSON lines 接收 `ready` / `error` / `stopped` 事件，关闭 stdin（EOF）即通知 helper 停止并恢复原模式。
  - `DDCService`（Apple Silicon，`IOAVService` 私有 API）：按 IORegistry 顺序把每个外接 framebuffer（AppleCLCD2 / IOMobileFramebufferShim）与其后的 `DCPAVServiceProxy` 配对，再用 EDID UUID 字段 + 产品名 + 序列号给 `DisplayDevice` 打分匹配（参照 MonitorControl Arm64DDC）。所有 I2C 都在一条串行队列上；`DDCCodec` 是纯函数，测试在 `Tests/DDCCodecTests.swift`。`DisplayStore.hardware` 只在物理屏集合变化时重新探测（模式切换不触发），菜单栏打开时节流重读；滑块写入按（屏幕, 控制项）合并，只发最新值。
  - `MediaKeyService`：`CGEventTap` 拦截 NSSystemDefined 媒体键，需辅助功能权限（无权限时不建 tap，按键保持系统行为）；按下被消费时对应的抬起也吞掉。`DisplayStore.handleMediaKey` 决定是否接管：亮度键 → 鼠标所在、由 PixelFit 控制亮度的屏；音量 / 静音 → `AudioOutputService` 判定默认输出是该屏的 DP/HDMI 音频。反馈浮层在 `Support/ControlHUDPanel.swift`。开发构建与正式版用同一个 Developer ID 签名（`build_and_run.sh` 自动选唯一的 Developer ID Application 证书，`DEV_SIGN_IDENTITY` 可覆盖），designated requirement 一致，辅助功能授权跨重新打包、跨开发版 / 正式版保留；不要改回取钥匙串「第一个」证书（曾误用 CleanRec 的本地自签证书导致授权失效）。
  - 亮度引擎在 `Stores/DisplayStore+Brightness.swift`：每屏 `BrightnessMode`（hardware / combined / software，nil = 自动：有 DDC 亮度 → combined，否则 software），`BrightnessSplit` 纯函数负责「单一亮度值 ↔ DDC + 软件」换算（combined 分界 0.5）。内建屏和 Apple 显示器走 `AppleBrightnessService`（DisplayServices，dlsym），亮度键交还系统。睡眠时暂停 DDC，唤醒 2 秒后重新匹配并重读；模式切换后只防抖重新 attach，不重读。
  - `DimmingService`（参照 MonitorControl）：gamma 缩放为主（只在本次运行首次 capture 前 `CGDisplayRestoreColorSyncSettings` 一次，之后绝不重新 capture，避免把自己调暗的表当原始表），每次写 gamma 后用 1×1 窗口迫使 WindowServer 重绘；有屏处于 gamma 调暗时每 1.5 秒巡检：被重置成原始曲线 → 直接重放，外来曲线累计 3 次 → 该屏本次运行改用 `CGShieldingWindowLevel` 遮罩窗口（`sharingType = .none`，截图与窗口列表里看不到）。注意：任何改过 gamma 的进程退出时系统都会恢复 ColorSync，包括 PixelFit 自己。日志 category 为 `dimming` / `media-keys`。
  - `PersistenceService` 读写 `~/Library/Application Support/HiDPIBuddy/state.json`（语言、预设、Dock 图标、媒体键开关、每屏 `brightness` 设置；旧版 `softwareDimming` 字段只读迁移）。
- 视图层：主窗口 `ContentView` → `DisplaysView`（`NavigationSplitView`，工具栏只放 `PresetsMenu`；屏幕列表靠通知自动刷新，手动刷新只保留菜单 ⌘R）；`MenuBarControlView` 是菜单栏窗口；`AppSettingsView` 是 `Settings` 场景（语言、`SMAppService` 登录项、Dock 图标）。Dock 图标通过 `DisplayStore.applyActivationPolicy` 在 `.regular` / `.accessory` 间切换，`AppDelegate` 启动时按持久化设置应用。
- 视觉约定：表单行、侧边栏、设置页的图标统一用 `SettingsIcon` + `RowIcon`（系统设置风格彩色圆角图标），新增行时沿用；菜单栏面板滑块是 `CapsuleSlider`（控制中心风格：白色填充、中性轨道，不用强调色）；屏幕排列图 `DisplayArrangementView` 显示各屏桌面壁纸（`WallpaperCache` 降采样）。菜单栏面板无法用脚本打开，debug 构建以 `PIXELFIT_PREVIEW_MENU=1 dist/PixelFit.app/Contents/MacOS/PixelFit` 启动会额外打开一个普通窗口承载同一视图，便于截图核对。
- 强调色用 `Color.accentColor`（`AppTheme.accent`）；不要用 `Color(nsColor: .controlAccentColor)` 做 `.tint`，实测会把 Menu 箭头渲染成红色。显示整数尺寸的 `Text` 用 `verbatim` 或先转成 String，否则会出现千位分隔符（「2,560」）。
- `Support/Localization.swift`：`L10n.t(key, language)` 查手写的 `zh` / `en` 字典（缺失时回退 en，再回退 key 本身）。新增 UI 文案要同时加两个字典。View 外（service）没有 language 参数时用 `L10n.t(key)`，它读 `DisplayStore` 同步的 `L10n.current`；service 错误统一抛 `LocalizedServiceError(key:arguments:detail:)`，文案在展示时才按当前语言生成，`detail` 放不翻译的原始诊断输出。

## 不能随意改的约束

- **兼容性身份**：Bundle ID `cc.ss-data.hidpibuddy`、`HiDPIBuddy` 用户数据目录、管理员备份目录均为改名前遗留，刻意保留以兼容旧预设和恢复记录，不要改成 PixelFit。
- **安全边界**（README 对用户承诺过）：只写 `/Library/.../Overrides`，绝不写 `/System`、不改 EDID 字节或固件、不要求关闭 SIP；不自动断开屏幕 / 模拟拔线 / 重启；物理配置按 VID/PID 匹配，会影响同型号所有屏幕。
- 物理 HiDPI 入口目前只对在线、未旋转、未镜像的 2560×1600 外接屏开放（目标 1600×1000）；唯一实屏验收是 Sculptor。扩大适用范围前需要硬件验证，并更新 `docs/compatibility-matrix.md`。
- `/usr/bin/ruby` 缺失时必须在请求授权前报错，不能回退到 Homebrew 或 PATH 查找。
- 虚拟显示器的尺寸关系（descriptor 为 backing pixels，mode 为逻辑尺寸）见 `docs/display-protocol-references.md`，修改 helper 前先读。
