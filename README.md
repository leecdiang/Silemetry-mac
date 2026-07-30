# Silemetry [![Version](https://img.shields.io/badge/version-0.2.0-2F81F7?labelColor=30363D&style=flat-square)](https://github.com/leecdiang/Silemetry-mac/releases/latest) [![Downloads](https://img.shields.io/github/downloads/leecdiang/Silemetry-mac/total?label=downloads&labelColor=30363D&color=8B5CF6&style=flat-square)](https://github.com/leecdiang/Silemetry-mac/releases) [![English](https://img.shields.io/badge/Language-English-4B5563?style=flat-square)](README_EN.md)

Silemetry 是一款原生 macOS 性能遥测工具，用于观察 Apple Silicon 在持续负载下的真实表现。

它不只记录某个瞬时峰值，而是连续采集：

- 温度
- 功耗
- 频率
- 每核心负载
- 测试阶段
- 电源与设备信息

测试完成后，数据会保存到 History，可重新查看、重命名、删除或进行 A/B 对比。

---

## ✨ 核心功能

| 功能 | 说明 |
|---|---|
|  **CPU / GPU 压力测试** | 支持 CPU Only、GPU Only 和 CPU + GPU |
|  **Metal GPU Workload** | Moderate 与 Maximum 两档 GPU 负载 |
|  **核心类型选择** | 可选择全部核心、P-Cores 或 E-Cores |
|  **Custom Test** | 自定义负载类型、阶段时长、采样间隔与环境温度 |
|  **实时遥测** | 温度、功耗、频率、核心利用率与测试阶段 |
|  **Monitor Only** | 不启动内部负载，只记录外部应用运行数据 |
|  **History** | 本地保存测试记录，支持重命名和删除 |
|  **Compare** | 对两个有效 Run 进行指标和曲线对比 |
|  **动态设备识别** | 自动读取当前 Mac 的芯片、核心、内存与系统信息 |
|  **电源状态** | 区分充电、电池供电、Low Power Mode 与不可用状态 |

---

## 🚀 测试模式

| 模式 | 适用场景 | 特点 |
|---|---|---|
| **Quick Check** | 快速确认遥测与负载是否正常 | 时间短，不用于判断稳态性能 |
| **Standard Test** | 日常性能与散热测试 | 时长适中 |
| **Sustained Test** | 观察持续功耗与降频 | 更接近热稳定状态 |
| **Extended Test** | 长时间热性能分析 | 适合深入测试 |
| **Custom Test** | 自定义实验 | 可配置 CPU/GPU、核心类型和阶段时长 |
| **Monitor Only** | Cinebench、Blender、Xcode、AI 推理等 | 只采集，不创建内部负载 |

---

## 🧪 Custom Test

自定义测试目前支持：

| 配置项 | 可选值 |
|---|---|
| **Stress Type** | CPU Only / GPU Only / CPU + GPU |
| **Core Target** | All / Performance / Efficiency |
| **GPU Level** | Moderate / Maximum |
| **Baseline** | 自定义 |
| **Load** | 自定义 |
| **Cooldown** | 自定义 |
| **Sampling Interval** | 自定义 |
| **Ambient Temperature** | 可选填写 |

> Core Target 使用 macOS QoS 进行调度倾向，不是不可迁移的硬件级 CPU affinity。  
> GPU Level 是负载预设，不保证在所有 M 系列 GPU 上得到完全相同的利用率。

---

## 📊 采集指标

| 类别 | 指标 |
|---|---|
| 🌡 **温度** | CPU Hottest、CPU Average、GPU Hottest、GPU Average |
| ⚡️ **功耗** | CPU、GPU、Package，以及系统可用的其他功耗域 |
| ⏱ **频率** | P-Cluster、E-Cluster |
| 🧩 **核心活动** | 每核心 CPU 利用率、P/E Cluster 汇总 |
| 🌡 **系统热状态** | Nominal / Fair / Serious / Critical |
| 🔋 **电源** | 充电、电池电量、Low Power Mode |
| 💻 **设备信息** | Model Identifier、芯片、核心拓扑、内存、macOS、Metal Device |
| ✅ **数据质量** | 样本数量、持续时间、覆盖率与缺失数据 |

不可用字段会显示为 `Unavailable`，不会用 `0` 冒充有效读数。

### 温度口径

**CPU Hottest** 是遥测后端可读取的 CPU thermal-zone 传感器中的最高值。

它不等同于 Apple 官方公布的结温，也不代表固定的 TjMax。

**Thermal State** 是 macOS 报告的系统级热压力状态。即使个别温度传感器较高，它仍可能保持 `Nominal`。

### 频率口径

P-Cluster 与 E-Cluster 是集群级频率指标，不应解释为每个核心各自独立的瞬时频率。

---

## 💻 动态设备识别

从 `v0.2.0-preview` 开始，Silemetry 不再假设所有设备都是 Apple M4。

应用会动态读取并保存：

| 字段 | 示例 |
|---|---|
| Model Identifier | `Mac16,13` |
| Chip Name | `Apple M4` |
| CPU Topology | `10 cores · 4P + 6E` |
| Memory | `24 GB` |
| macOS | `macOS 26.5.2` |
| Metal Device | `Apple M4` |

每个 Run 会保存测试开始时的设备快照，因此在另一台 Mac 上打开或比较时，不会被当前机器的信息覆盖。

---

## 📥 下载与安装

前往 [GitHub Releases](../../releases/latest) 下载：

```text
Silemetry-v0.2.0-preview-arm64.dmg
Silemetry-v0.2.0-preview-arm64.zip
Silemetry-v0.2.0-preview-SHA256SUMS.txt
```

### DMG 安装

1. 打开 DMG
2. 将左侧的 **Silemetry** 拖到右侧 **Applications**
3. 从“应用程序”文件夹启动

如果 Preview 版本尚未公证：

1. 在“应用程序”中右键 Silemetry
2. 选择 **打开**
3. 确认启动

也可以前往：

```text
系统设置 → 隐私与安全性
```

不要全局关闭 Gatekeeper。

---

## 🔒 隐私

Silemetry 的测试与分析均在本机完成：

- 不需要账号
- 不上传遥测数据
- 不包含广告 SDK
- 不包含分析 SDK
- 不依赖云端计算
- 不需要后台守护进程

History 数据保存在本机，并可在应用内删除。

---

## ⚠️ 使用提示

Silemetry 会主动创建持续 CPU 或 GPU 负载。

- 机身升温属于正常现象
- macOS 的硬件热保护始终保持启用
- Silemetry 不修改电压、时钟、功耗限制、风扇策略或 SMC
- 如果系统出现异常，请立即停止测试
- 有风扇的 Mac 请勿遮挡进出风口

---

## v0.2.0 

### 本次重点

- Metal GPU 压力测试
- CPU Only / GPU Only / CPU + GPU
- P-Core / E-Core 调度倾向
- 完整 Custom Test
- 动态设备识别
- 电池状态与 Low Power Mode
- 自适应 Status Pill
- 新 App 图标

详细内容见：

- [Release](../../releases/latest)
- [`RELEASE_v0.2.0-preview.md`](RELEASE_v0.2.0-preview.md)
- [`RELEASE_NOTES_v0.2.0-preview.md`](RELEASE_NOTES_v0.2.0-preview.md)

---

## 🧱 技术架构

| 模块 | 技术 |
|---|---|
| UI | SwiftUI + Swift Charts |
| Telemetry | Embedded Rust core |
| CPU Workload | Native C |
| GPU Workload | Metal Compute |
| Persistence | SwiftData + local sample files |
| Device Detection | sysctl / ProcessInfo / Metal |
| Packaging | Drag-to-Applications DMG |

运行 Release 版本不需要：

```text
Homebrew · Python · sudo · kext · 关闭 SIP
```

---

## 🛠 从源码构建

### 环境

- Apple Silicon Mac
- Xcode
- Rust stable toolchain
- Git

```bash
git clone https://github.com/leecdiang/Silemetry.git
cd Silemetry

./Scripts/build_telemetry_core.sh

xcodebuild \
  -project ThermalBench.xcodeproj \
  -scheme ThermalBench \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

内部 Xcode project / scheme 可能暂时保留旧名称 `ThermalBench`，公开应用名称为 **Silemetry**。

---

## 🗺 Roadmap

- [x] CPU 压力测试
- [x] Metal GPU 压力测试
- [x] CPU + GPU 双负载
- [x] Monitor Only
- [x] History 与 Compare
- [x] 动态设备信息
- [ ] 更多 Apple Silicon 型号验证
- [ ] 更完整的报告导出
- [ ] 更严格的跨设备可比性分析
- [ ] UI 本地化与窄窗口完善
- [ ] Developer ID 签名与公证
- [ ] 自动化 Release Pipeline

---

## 🎨 App 图标

Silemetry 使用 Streamline Flex Color 图标集中的 `ai-chip-robot-flat`：

| 项目 | 信息 |
|---|---|
| Author | Streamline |
| License | CC BY 4.0 |
| Source | https://icon-sets.iconify.design/streamline-flex-color/ai-chip-robot-flat/ |
| License Text | https://creativecommons.org/licenses/by/4.0/ |

图形未进行视觉修改，仅转换并缩放为 macOS AppIcon 所需格式。

---

## 📄 License

Silemetry 自有源码采用 MIT License，第三方组件与图标许可见：

- [`LICENSE`](LICENSE)
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)

---

## 🙏 Acknowledgements

感谢以下开源项目与开发者：

- `macmon` 及其贡献者
- Streamline
- Iconify
- Swift、Rust 与 Apple 开发者社区

---

## ✍️ Author

Built by [LEEcDiang](https://github.com/leecdiang).

如果 Silemetry 对你有帮助，欢迎提交 Issue、改进建议或测试结果。
- GPU average temperature
- CPU power
- GPU power
- package power
- P-cluster frequency
- E-cluster frequency
- per-core CPU utilization
- macOS Thermal State
- battery, charging, and Low Power Mode state

Unavailable metrics are shown as unavailable rather than being replaced with zero.

### Temperature semantics

**CPU Hottest** is the maximum among the readable CPU thermal-zone sensors used by the telemetry backend.

It is not claimed to be Apple's official junction temperature or TjMax.

**Thermal State** is the system-level pressure state reported by macOS. It may remain Nominal even when an individual readable temperature sensor is hot.

### Frequency semantics

P-cluster and E-cluster values are cluster-level frequency metrics. They should not be interpreted as ten independent instantaneous core clocks.

## Device detection

Silemetry reads the current device dynamically, including:

- model identifier
- Apple chip name
- CPU core count and P/E topology
- memory size
- macOS version
- Metal device name

Each saved run stores a device snapshot, so imported or compared runs keep the identity of the Mac on which they were recorded.

## Results and comparison

Each completed run can include:

- temperature, power, and frequency timelines
- per-core CPU utilization
- phase timing
- peak and average metrics
- sampling coverage and data-quality information
- device and software metadata

Saved runs can be reopened after restarting the app.

A/B comparison is most useful when both runs use the same device, workload, duration, power source, ambient conditions, and Silemetry version.

## Installation

1. Download the latest DMG from GitHub Releases.
2. Open the DMG.
3. Drag **Silemetry** into **Applications**.
4. Launch Silemetry.

Release asset:

```text
Silemetry-v0.2.0-preview-arm64.dmg
```

If the preview is not notarized, macOS may block the first launch. Use Control-click → **Open**, or approve it in **System Settings → Privacy & Security**.

Do not disable Gatekeeper globally.

## Safety

Silemetry intentionally creates sustained computational load.

- The Mac may become hot.
- macOS thermal protection remains enabled.
- Silemetry does not change voltage, clocks, power limits, fan policy, or SMC settings.
- Stop a test if the Mac behaves unexpectedly.
- Keep fan vents unobstructed on Macs that have fans.

## Privacy

Silemetry works locally.

- No account
- No telemetry upload
- No analytics SDK
- No advertising SDK
- No cloud processing
- No background daemon

Saved runs are stored locally and can be deleted from History.

## Current preview

**Version:** `0.2.0-preview`

Primary validation machine:

- 15-inch MacBook Air
- Apple M4
- 24 GB unified memory
- macOS 26.5.2

Other Apple Silicon Macs are supported through dynamic device detection, but not all models have received equal validation.

## Known limitations

- Apple does not expose stable public APIs for every Apple Silicon telemetry field.
- Sensor availability can change between chips and macOS versions.
- GPU core count may be unavailable when it cannot be read reliably.
- Short tests do not establish steady state.
- Compare results depend heavily on matching test conditions.
- Some UI and export details may still change during the preview period.

## Build from source

Requirements:

- Apple Silicon Mac
- Xcode
- Rust toolchain
- Git

```bash
git clone https://github.com/OWNER/silemetry.git
cd silemetry

./Scripts/build_telemetry_core.sh

xcodebuild \
  -project ThermalBench.xcodeproj \
  -scheme ThermalBench \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

The internal Xcode project may temporarily retain the older `ThermalBench` name. The installed product and public branding use **Silemetry**.

## Application icon

Silemetry uses `ai-chip-robot-flat` from the Streamline Flex Color icon collection.

- Author: Streamline
- License: CC BY 4.0
- Source: https://icon-sets.iconify.design/streamline-flex-color/ai-chip-robot-flat/
- License text: https://creativecommons.org/licenses/by/4.0/

The artwork is used without visual modification and is only converted and resized for the macOS AppIcon asset catalog.

## License

Silemetry's own source is released under the MIT License unless a file states otherwise.

See:

- `LICENSE`
- `THIRD_PARTY_NOTICES.md`

## Disclaimer

Silemetry is an independent open-source project and is not affiliated with or endorsed by Apple, Streamline, Iconify, or the maintainers of its telemetry dependencies.
