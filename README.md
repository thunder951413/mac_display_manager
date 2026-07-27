# LumaFlow

LumaFlow 是一个原生 macOS 显示器管理应用，提供接近 BetterDisplay 的常用显示器控制体验：平滑分辨率缩放、外接显示器亮度控制、焦点显示器键盘控制，以及按显示器自动恢复设置。

## 功能

### 分辨率与缩放

- 自动检测内建屏幕和外接显示器。
- 仅展示与面板原生宽高比一致的分辨率。
- 自动选用该显示器可用的最高刷新率，例如内建屏可使用 120 Hz，而只支持 60 Hz 的外接屏使用 60 Hz。
- 将 macOS 默认分辨率定义为 `100%`，其他分辨率按相对百分比显示。
- 支持以 `100%` 为锚点的 3% 缩放步进。
- 当系统缺少密集 HiDPI 模式时，可生成、备份并安装显示器 override 配置；需要管理员授权并重启 Mac。
- 切换分辨率时使用淡入淡出过渡，并提供 15 秒确认与自动回滚保护。
- 支持收藏常用分辨率，并从菜单栏快速切换。

> 滑杆只能切换 macOS 实际提供的显示模式。首次启用 3% 灵活缩放后必须重启，新的 HiDPI 模式才会生效。

### 亮度与画面

- 内建屏幕和 Apple 显示器使用系统硬件亮度接口。
- Apple Silicon 外接显示器优先使用 DDC/CI 硬件亮度控制。
- 显示器或连接方式不支持 DDC/CI 时，自动回退为 Gamma 软件调光。
- 提供亮度、对比度和冷暖色温调节。
- 键盘亮度键只修改当前焦点窗口所在的显示器。
- `Option + Shift + 亮度键` 可进行 1% 精细调节，长按支持连续调节。

### 按显示器保存

LumaFlow 根据显示器的厂商、产品和序列号分别保存：

- 分辨率与刷新率
- 亮度
- 对比度
- 色温

显示器重新接入后会自动恢复对应设置，互不影响。

## 系统要求

- macOS 14 或更高版本
- Xcode 及 Swift 5.10 或更高版本
- DDC/CI 硬件控制目前面向 Apple Silicon

外接屏能否进行硬件亮度控制取决于显示器、线缆、扩展坞和连接协议。部分 HDMI 转接器、DisplayLink 设备或关闭了 DDC/CI 的显示器只能使用软件调光。

## 构建与运行

直接运行：

```bash
swift run LumaFlow
```

构建 `.app`：

```bash
./scripts/build-app.sh
open dist/LumaFlow.app
```

运行测试：

```bash
swift test
```

## 首次配置

### 键盘亮度键

1. 打开 LumaFlow。
2. 点击“授权键盘控制”。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中启用 LumaFlow。
4. 返回应用，授权状态会自动刷新。

本地构建使用 ad-hoc 签名。重新构建或替换应用后，macOS 可能要求重新授予辅助功能权限。

### 3% 灵活缩放

点击“一键启用 3% 灵活缩放”后，LumaFlow 会：

1. 备份已有的显示器 override 配置。
2. 合并写入细分 HiDPI 分辨率。
3. 请求管理员权限安装到 `/Library/Displays`。
4. 提示重启 Mac。

应用内可以恢复安装前的配置。

## 项目结构

```text
Sources/LumaFlow/
├── DisplayService.swift              # 显示器枚举、模式切换与状态协调
├── DisplayHardwareController.swift   # Apple 亮度与 DDC/CI 控制
├── BrightnessKeyMonitor.swift        # 全局亮度媒体键监听
├── DisplaySettingsStore.swift        # 按显示器持久化
├── FlexibleScalingInstaller.swift    # 3% HiDPI override 安装与恢复
├── ContentView.swift                 # 主窗口
└── MenuBarView.swift                 # 菜单栏控制
```

## 说明

本项目与 BetterDisplay、MonitorControl 没有关联。DDC/CI 部分参考了 MIT 许可的 [MonitorControl](https://github.com/MonitorControl/MonitorControl)，许可信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
