# Silemetry

> **See what your silicon can sustain.**
<img width="650" alt="image" src="https://github.com/user-attachments/assets/ba420c9e-b658-45d6-be5d-f231fad1777d" />

Silemetry is a native macOS tool for tracing thermal behavior and sustained performance on Apple Silicon. It records temperature, power, frequency, utilization, test phases, and device metadata over time, then turns them into persistent results and comparable runs.

## What it does

- Runs controlled CPU, GPU, or combined stress workloads
- Records CPU/GPU temperature, power, frequency, and utilization
- Shows per-core CPU activity
- Supports external workload recording through **Monitor Only**
- Saves test history locally
- Renames, deletes, reopens, and compares runs
- Detects the current Mac dynamically instead of assuming a fixed model
- Works without Homebrew, Python, `sudo`, kernel extensions, or SIP changes
<img width="650" alt="image" src="https://github.com/user-attachments/assets/9131814a-83f5-416a-add0-ce315732bac5" />

## Test modes

### Quick Check

A short validation run for confirming telemetry, workload startup, charts, and persistence.

It is not intended to establish thermal steady state.

### Standard / Sustained / Extended

Longer controlled tests for observing how power, temperature, and frequency change over time.

### Custom Test

Configure:

- **Stress Type:** CPU Only / GPU Only / CPU + GPU
- **Core Target:** All / Performance / Efficiency
- **GPU Level:** Moderate / Maximum
- Baseline, load, and cooldown duration
- Sampling interval
- Optional ambient temperature

### Monitor Only

Records telemetry without launching Silemetry's own workload.

Useful for Cinebench, Blender, Xcode builds, video export, local AI inference, or any other repeatable workload.

## Telemetry

Depending on the Mac and macOS version, Silemetry may record:

- CPU hottest temperature
- CPU average temperature
- GPU hottest temperature
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
