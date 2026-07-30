# Silemetry [![Version](https://img.shields.io/badge/version-0.2.0-2F81F7?labelColor=30363D&style=flat-square)](https://github.com/leecdiang/Silemetry-mac/releases/latest) [![Downloads](https://img.shields.io/github/downloads/leecdiang/Silemetry-mac/total?label=downloads&labelColor=30363D&color=8B5CF6&style=flat-square)](https://github.com/leecdiang/Silemetry-mac/releases) [![English](https://img.shields.io/badge/Language-English-4B5563?style=flat-square)](README_EN.md)

Silemetry 是一款原生 macOS 性能遥测工具，用于观察 Apple Silicon 在持续负载下的真实表现。它连续采集温度、功耗、频率、每核心负载和测试阶段数据，测试完成后保存到 History，可重新查看、重命名、删除或进行 A/B 对比。

---

### 核心功能

**CPU / GPU 压力测试** — 支持 CPU Only、GPU Only 和 CPU + GPU 三种模式。GPU 提供 Moderate（≈30%）与 Maximum（≈100%）两档 Metal compute 负载。可通过 Core Target 选择全部核心、P-Cores 或 E-Cores（基于 QoS 调度倾向）。

**Custom Test** — 自定义负载类型、阶段时长、采样间隔与环境温度。

**实时遥测** — 温度（CPU/GPU Hottest & Average）、功耗（CPU/GPU/Package）、P/E-Cluster 频率、每核心利用率、系统热状态（Nominal/Fair/Serious/Critical）。

**Monitor Only** — 不启动内部负载，只记录外部应用（Cinebench、Blender、Xcode、AI 推理等）运行时的遥测数据。

**History & Compare** — 本地保存测试记录，支持重命名、删除、双跑 A/B 对比。

**动态设备识别** — 自动读取当前 Mac 的 model identifier、芯片、核心拓扑、内存、macOS 版本和 Metal device。每个 Run 保存设备快照，换机后不会覆盖。

**电源感知** — 区分充电、电池供电、Low Power Mode 与不可用状态。

---

### 测试模式

- **Quick Check** — 快速确认遥测与负载正常，不长到足以建立热稳定
- **Standard Test** — 日常性能与散热测试
- **Sustained Test** — 观察持续功耗与降频
- **Extended Test** — 长时间热性能分析
- **Custom Test** — 完全自定义：Stress Type、Core Target、GPU Level、各阶段时长、采样间隔、环境温度
- **Monitor Only** — 仅采集遥测，不创建内部负载

---

### 采集指标

**温度** — CPU Hottest、CPU Average、GPU Hottest、GPU Average。CPU Hottest 是遥测后端可读取的 CPU thermal-zone 传感器最高值，不等同于 Apple 官方结温或 TjMax。Thermal State 是 macOS 系统级热压力状态，即使个别传感器较高，仍可能保持 Nominal。

**功耗** — CPU、GPU、Package 及系统可用其他功耗域。不可用字段显示为 Unavailable，不用 0 冒充。

**频率** — P-Cluster 与 E-Cluster 集群级指标，不应解释为每核心独立瞬时频率。

**核心活动** — 每核心 CPU 利用率、P/E Cluster 汇总。

**数据质量** — 样本数量、持续时间、覆盖率与缺失数据信息。

---

### 下载与安装

前往 [Releases](https://github.com/leecdiang/Silemetry-mac/releases/latest) 下载 DMG。打开后拖入 Applications 即可。

预览版未公证时，右键 → **打开** 确认启动；或前往 **系统设置 → 隐私与安全性**。不要全局关闭 Gatekeeper。

Release 版不需要 Homebrew、Python、sudo、kext 或关闭 SIP。

---

### 隐私

全程本地：不需要账号、不上传遥测、无广告/分析 SDK、不依赖云端、无后台守护进程。History 数据保存在本机，可在应用内删除。

---

### 使用提示

Silemetry 会主动创建持续负载。机身升温正常，macOS 热保护始终保持启用。不修改电压、时钟、功耗限制、风扇策略或 SMC。系统异常请立即停止，有风扇的 Mac 勿遮挡进出风口。

---

### v0.2.0-preview

Metal GPU 压力测试（Moderate / Maximum）、CPU Only / GPU Only / CPU+GPU、P/E-Core 调度倾向、完整 Custom Test、动态设备识别、电池状态与 Low Power Mode、自适应 Status Pill、新 App 图标。

详见 [Release](https://github.com/leecdiang/Silemetry-mac/releases/latest)。

---

### 技术栈

SwiftUI + Swift Charts · Rust Telemetry Core · C CPU Workload · Metal GPU Workload · SwiftData · sysctl + ProcessInfo + Metal

内部 Xcode project 保留旧名称 `ThermalBench`，公开应用名为 **Silemetry**。构建需 Apple Silicon Mac + Xcode + Rust toolchain + Git。

---

### Roadmap

- [x] CPU 压力测试
- [x] Metal GPU 压力测试
- [x] CPU + GPU 双负载
- [x] Monitor Only
- [x] History 与 Compare
- [x] 动态设备信息
- [ ] 更多 Apple Silicon 型号验证
- [ ] 更完整的报告导出
- [ ] 跨设备可比性分析
- [ ] UI 本地化与窄窗口完善
- [ ] Developer ID 签名与公证
- [ ] 自动化 Release Pipeline

---

### App 图标

使用 Streamline Flex Color 图标集 `ai-chip-robot-flat`，CC BY 4.0，仅转换缩放为 macOS AppIcon 格式。来源：https://icon-sets.iconify.design/streamline-flex-color/ai-chip-robot-flat/

---

### License

源码 MIT License，第三方许可见 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。

Built by [LEEcDiang](https://github.com/leecdiang).
