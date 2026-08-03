# Silemetry [![Version](https://img.shields.io/badge/version-0.2.1-2F81F7?labelColor=30363D&style=flat-square)](https://github.com/leecdiang/Silemetry-mac/releases/latest) [![Downloads](https://img.shields.io/github/downloads/leecdiang/Silemetry-mac/total?label=downloads&labelColor=30363D&color=8B5CF6&style=flat-square)](https://github.com/leecdiang/Silemetry-mac/releases) [![English](https://img.shields.io/badge/Language-English-4B5563?style=flat-square)](README_EN.md)

Silemetry 是一款原生 macOS 性能遥测工具，专为观察 Apple Silicon 在持续负载下的真实表现而设计。

它不满足于记录一个瞬时峰值，而是在整个测试期间连续采集温度、功耗、频率、每核心活动、测试阶段和电源状态。测试结束后数据保存在本地 History 中，可随时查看、重命名、删除或进行 A/B 对比——方便你对比不同散热条件、系统版本或工作负载下的实际表现。

<p align="center">
  <img src="Docs/images/screenshot-home.png" width="720" alt="Silemetry Home">
</p>

---

#### 核心功能

🔥 **CPU / GPU 压力测试**

支持 CPU Only、GPU Only 和 CPU + GPU 三种独立模式。GPU 端通过 Metal compute 提供 Moderate（约 30%）与 Maximum（约 100%）两档强度，CPU 端可通过 Core Target 选择全部核心、P-Cores 或 E-Cores。P/E 核心的调度倾向基于 macOS QoS 机制，不依赖 SIP 关闭或内核扩展。

⚙️ **Custom Test**

完全自定义的测试配置：Stress Type、Core Target、GPU Level、Baseline/Load/Cooldown 各阶段时长、采样间隔和环境温度。适合有明确实验设计的场景。

📊 **实时遥测**

测试过程中实时显示 CPU/GPU Hottest 与 Average 温度、CPU/GPU/Package 功耗、P/E-Cluster 集群频率、每核心利用率曲线，以及 macOS 系统热状态（Nominal / Fair / Serious / Critical）。所有图表随测试推进动态更新。

👁️ **Monitor Only**

不启动任何内部负载，仅采集遥测。适合搭配外部应用使用——Cinebench、Blender、Xcode 编译、本地 AI 推理、视频导出等，凡是你能稳定复现的工作负载都可以。

📁 **History & Compare**

每次测试完成后自动保存到本地历史，支持重命名、删除和 A/B 对比。对比时会校验两轮 Run 的设备、模式和基本条件是否可比，并给出兼容性提示。

💻 **动态设备识别**

不再硬编码设备信息。应用通过 sysctl / ProcessInfo / Metal 动态读取当前 Mac 的 model identifier、芯片名称、CPU P/E 拓扑、内存大小、macOS 版本和 Metal 设备名。每个 Run 保存测试时的设备快照，换机打开或跨设备对比不会被当前机器信息覆盖。

🔋 **电源感知**

区分交流充电、电池放电、Low Power Mode 和不可用四种状态，在 Home 页和测试页实时显示。Low Power Mode 开启时额外标注提醒。

<p align="center">
  <img src="Docs/images/screenshot-custom.png" width="640" alt="Custom Test">
</p>

---

#### 测试模式与采集指标

| | |
|---|---|
| 🔬 Quick Check | 快速确认遥测与负载正常，时长不足以建立热稳定 |
| 🔬 Standard | 日常性能与散热对比测试 |
| 🔥 Sustained | 观察持续功耗与频率衰减，更接近热稳定状态 |
| 🔥 Extended | 长时间深入分析，适合评估极限散热能力 |
| ⚙️ Custom | 完全自定义负载类型、核心目标、各阶段时长和采样参数 |
| 👁️ Monitor Only | 仅采集遥测，不创建内部负载——搭配任意外部应用使用 |
| **指标** | |
| 🌡 CPU Hottest | CPU thermal-zone 传感器可读最高值，非 Apple 官方结温或 TjMax |
| 🌡 CPU Average | 同组传感器算术平均 |
| 🌡 GPU Hottest | GPU thermal-zone 传感器可读最高值 |
| 🌡 GPU Average | GPU thermal-zone 传感器算术平均 |
| ⚡ CPU Power | CPU 功耗。不可用时显示 Unavailable，不以 0 冒充 |
| ⚡ GPU Power | GPU 功耗 |
| ⚡ Package Power | 封装功耗及系统暴露的其他功耗域 |
| ⏱ P-Cluster Freq | P 核集群频率——集群级指标，非每核心独立瞬时值 |
| ⏱ E-Cluster Freq | E 核集群频率 |
| 🧩 Per-Core Util | 每逻辑核 CPU 利用率，P/E 分别汇总 |
| 🌡 Thermal State | macOS 系统热压力等级：Nominal → Fair → Serious → Critical |
| ✅ Data Quality | 样本总数、有效覆盖时长、覆盖率及缺失/异常样本统计 |

<p align="center">
  <img src="Docs/images/screenshot-compare.png" width="640" alt="Compare View">
</p>

---

#### 下载与安装

前往 [Releases](https://github.com/leecdiang/Silemetry-mac/releases/latest) 下载 `Silemetry-v0.2.1-arm64.dmg`。

打开 DMG，将 Silemetry 拖入 Applications 即可。当前预览版使用 ad-hoc 签名，首次启动时需右键 → **打开** 确认，或前往 **系统设置 → 隐私与安全性** 手动放行。不要全局关闭 Gatekeeper。

Release 版不需要 Homebrew、Python、sudo、kext，也不需要关闭 SIP。

---

#### 隐私

Silemetry 完全在本地运行：不需要账号、不会上传遥测数据、不含广告或分析 SDK、不依赖云端计算、不安装后台守护进程。所有测试记录保存在本机 Application Support 目录下，可在应用内随时删除。

---

#### 使用提示

Silemetry 会主动创建持续的 CPU 或 GPU 计算负载，机身升温属于正常现象。macOS 的硬件热保护始终处于启用状态——Silemetry 不会修改电压、时钟频率、功耗限制、风扇策略或 SMC 参数。如果系统出现异常，请立即停止测试。有风扇的 Mac 注意不要遮挡进出风口。

---

#### v0.2.1

本次更新重点：遥测句柄生命周期与并发安全修复、逐指标有效性掩码、Stop / Discard / 失败终结路径、JSONL 归档完整性校验与流式摘要、Compare 可比性与损坏数据检查、SwiftData 回滚与文件事务、动态设备/电源变化感知与真实 startedAt、70/70 测试通过（CI #15）。

完整变更清单见 [Release](https://github.com/leecdiang/Silemetry-mac/releases/latest)。

---

#### 技术栈

SwiftUI + Swift Charts · Embedded Rust Telemetry Core · C CPU Workload · Metal GPU Compute · SwiftData Persistence · sysctl + ProcessInfo + Metal Device Detection

内部工程名暂为 `ThermalBench`，公开产品名为 **Silemetry**。从源码构建需 Apple Silicon Mac + Xcode + Rust stable toolchain + Git。

---

#### Roadmap

- [x] CPU 压力测试
- [x] Metal GPU 压力测试
- [x] CPU + GPU 双负载
- [x] Monitor Only 外部负载记录
- [x] History 持久化与 Compare 对比
- [x] 动态设备信息读取
- [ ] 更多 Apple Silicon 型号验证
- [ ] 更完整的报告导出
- [ ] 跨设备可比性分析
- [ ] UI 本地化与窄窗口完善
- [ ] Developer ID 签名与公证
- [ ] 自动化 Release Pipeline

---

#### App 图标

使用 Streamline Flex Color 图标集中的 `ai-chip-robot-flat`（CC BY 4.0），仅做格式转换和尺寸缩放。

来源：https://icon-sets.iconify.design/streamline-flex-color/ai-chip-robot-flat/

---

#### License

源码 MIT License。第三方组件与图标授权详见 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。

Built by [LEEcDiang](https://github.com/leecdiang).
