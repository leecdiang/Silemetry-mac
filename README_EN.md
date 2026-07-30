# Silemetry

<p align="center">
  <strong>See what your silicon can sustain.</strong><br>
  Trace temperature, power, frequency, and core activity under sustained load on Apple Silicon.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-Apple%20Silicon-111111?logo=apple" alt="macOS Apple Silicon">
  <img src="https://img.shields.io/badge/SwiftUI-Native-F05138?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Rust-Telemetry-000000?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/version-0.2.0--preview-2F81F7" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="../../releases/latest">Latest Release</a> ·
  <a href="../../issues">Report an Issue</a>
</p>

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/ba420c9e-b658-45d6-be5d-f231fad1777d"
    alt="Silemetry"
    width="520"
  />
</p>

---

## 🔬 What is Silemetry?

Silemetry is a native macOS telemetry tool for observing what an Apple Silicon Mac can sustain under continuous load.

Instead of recording only a short peak score, it traces:

- temperature
- power
- frequency
- per-core activity
- test phases
- power and device metadata

Completed runs are stored locally and can be reopened, renamed, deleted, or compared.

> ⚠️ Silemetry is preview software. Sensor availability and metric semantics may differ between Apple Silicon generations and macOS releases.

---

## ✨ Core Features

| Feature | Description |
|---|---|
| 🔥 **CPU / GPU Stress Tests** | CPU Only, GPU Only, and CPU + GPU |
| 🎮 **Metal GPU Workload** | Moderate and Maximum GPU presets |
| 🧠 **Core Targeting** | All cores, performance cores, or efficiency cores |
| 🛠 **Custom Test** | Configure workload type, phases, sampling, and ambient temperature |
| 📈 **Live Telemetry** | Temperature, power, frequency, utilization, and phases |
| 👀 **Monitor Only** | Record an external workload without starting an internal load |
| 🗂 **History** | Persist, reopen, rename, and delete runs |
| ⚖️ **Compare** | Compare metrics and curves from two valid runs |
| 💻 **Dynamic Device Detection** | Read the current chip, topology, memory, and system version |
| 🔋 **Power Status** | Charging, battery operation, Low Power Mode, and unavailable states |

---

## 🚀 Test Modes

| Mode | Use case | Notes |
|---|---|---|
| **Quick Check** | Verify telemetry and workload startup | Too short for steady-state analysis |
| **Standard Test** | Routine thermal and performance testing | Medium duration |
| **Sustained Test** | Observe sustained power and frequency | Closer to thermal equilibrium |
| **Extended Test** | Longer thermal characterization | Intended for deeper testing |
| **Custom Test** | Build a controlled experiment | Configurable workload and phases |
| **Monitor Only** | Cinebench, Blender, Xcode, AI inference, and more | Records without internal load |

---

## 🧪 Custom Test

| Setting | Values |
|---|---|
| **Stress Type** | CPU Only / GPU Only / CPU + GPU |
| **Core Target** | All / Performance / Efficiency |
| **GPU Level** | Moderate / Maximum |
| **Baseline** | Configurable |
| **Load** | Configurable |
| **Cooldown** | Configurable |
| **Sampling Interval** | Configurable |
| **Ambient Temperature** | Optional |

> Core Target uses macOS QoS as a scheduling preference, not strict hardware affinity.  
> GPU presets do not guarantee identical utilization percentages across every M-series GPU.

---

## 📊 Telemetry

| Category | Metrics |
|---|---|
| 🌡 **Temperature** | CPU Hottest, CPU Average, GPU Hottest, GPU Average |
| ⚡️ **Power** | CPU, GPU, Package, and other available power domains |
| ⏱ **Frequency** | P-Cluster and E-Cluster |
| 🧩 **Core Activity** | Per-core CPU utilization and P/E summaries |
| 🌡 **Thermal State** | Nominal / Fair / Serious / Critical |
| 🔋 **Power Source** | Charging, battery level, and Low Power Mode |
| 💻 **Device** | Model identifier, chip, topology, memory, macOS, and Metal device |
| ✅ **Data Quality** | Samples, duration, coverage, and missing data |

Unavailable metrics are displayed as unavailable instead of being replaced with zero.

### Temperature semantics

**CPU Hottest** is the maximum value among the readable CPU thermal-zone sensors used by the telemetry backend.

It is not claimed to be Apple's official junction temperature or a documented TjMax.

**Thermal State** is a system-level pressure status reported by macOS. It may remain `Nominal` while an individual readable sensor is hot.

### Frequency semantics

P-Cluster and E-Cluster are cluster-level frequency metrics. They should not be interpreted as independent instantaneous clocks for every CPU core.

---

## 💻 Dynamic Device Detection

Starting with `v0.2.0-preview`, Silemetry no longer assumes every machine is an Apple M4 Mac.

It dynamically reads and stores:

| Field | Example |
|---|---|
| Model Identifier | `Mac16,13` |
| Chip Name | `Apple M4` |
| CPU Topology | `10 cores · 4P + 6E` |
| Memory | `24 GB` |
| macOS | `macOS 26.5.2` |
| Metal Device | `Apple M4` |

Each run stores a device snapshot captured at test time, so imported or compared runs keep the identity of the original Mac.

---

## 📥 Download and Install

Download from [GitHub Releases](../../releases/latest):

```text
Silemetry-v0.2.0-preview-arm64.dmg
Silemetry-v0.2.0-preview-arm64.zip
Silemetry-v0.2.0-preview-SHA256SUMS.txt
```

### DMG installation

1. Open the DMG.
2. Drag **Silemetry** onto **Applications**.
3. Launch it from the Applications folder.

When a preview build is not notarized, use Control-click → **Open**, or approve it in:

```text
System Settings → Privacy & Security
```

Do not disable Gatekeeper globally.

---

## 🔒 Privacy

Silemetry runs locally:

- no account
- no telemetry upload
- no analytics SDK
- no advertising SDK
- no cloud processing
- no background daemon

Saved runs remain on the Mac and can be deleted from History.

---

## ⚠️ Safety

Silemetry intentionally creates sustained CPU and GPU load.

- The enclosure may become hot.
- macOS thermal protection remains enabled.
- Silemetry does not modify voltage, clocks, power limits, fan policy, or SMC settings.
- Stop the test if the system behaves unexpectedly.
- Keep fan vents unobstructed on Macs with active cooling.

---

## 📦 v0.2.0 Preview

### Highlights

- Metal GPU stress testing
- CPU Only / GPU Only / CPU + GPU
- P-Core / E-Core scheduling preference
- Full Custom Test
- Dynamic device detection
- Battery and Low Power Mode status
- Adaptive Status Pill
- New application icon

Details:

- [Release](../../releases/latest)
- [`RELEASE_v0.2.0-preview.md`](RELEASE_v0.2.0-preview.md)
- [`RELEASE_NOTES_v0.2.0-preview.md`](RELEASE_NOTES_v0.2.0-preview.md)

---

## 🧱 Architecture

| Layer | Technology |
|---|---|
| UI | SwiftUI + Swift Charts |
| Telemetry | Embedded Rust core |
| CPU Workload | Native C |
| GPU Workload | Metal Compute |
| Persistence | SwiftData + local sample files |
| Device Detection | sysctl / ProcessInfo / Metal |
| Packaging | Drag-to-Applications DMG |

The release build does not require:

```text
Homebrew · Python · sudo · kext · disabled SIP
```

---

## 🛠 Build from Source

Requirements:

- Apple Silicon Mac
- Xcode
- stable Rust toolchain
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

The internal Xcode project and scheme may temporarily retain the older `ThermalBench` name. The public application name is **Silemetry**.

---

## 🗺 Roadmap

- [x] CPU stress testing
- [x] Metal GPU stress testing
- [x] CPU + GPU combined workload
- [x] Monitor Only
- [x] History and Compare
- [x] Dynamic device information
- [ ] Validation across more Apple Silicon models
- [ ] More complete report export
- [ ] Stricter cross-device comparability analysis
- [ ] UI localization and compact-window refinement
- [ ] Developer ID signing and notarization
- [ ] Automated release pipeline

---

## 🎨 Application Icon

Silemetry uses `ai-chip-robot-flat` from the Streamline Flex Color collection:

| Item | Value |
|---|---|
| Author | Streamline |
| License | CC BY 4.0 |
| Source | https://icon-sets.iconify.design/streamline-flex-color/ai-chip-robot-flat/ |
| License Text | https://creativecommons.org/licenses/by/4.0/ |

The artwork is used without visual modification and is only converted and resized for the macOS AppIcon asset catalog.

---

## 📄 License

Silemetry's own source is released under the MIT License.

See:

- [`LICENSE`](LICENSE)
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)

---

## 🙏 Acknowledgements

Thanks to:

- `macmon` and its contributors
- Streamline
- Iconify
- the Swift, Rust, and Apple developer communities

---

## ✍️ Author

Built by [LEEcDiang](https://github.com/leecdiang).

Issues, test results, and focused contributions are welcome.
