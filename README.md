# Silemetry

> **See what your silicon can sustain.**

Silemetry is a lightweight, native macOS app for recording and comparing the thermal and sustained-performance behavior of Apple Silicon Macs.

It combines controlled workloads, Monitor Only recording, live telemetry, per-core activity, persistent history, detailed results, and A/B comparison in one self-contained application.

> [!WARNING]
> Silemetry is currently an **early preview**. It is already useful, but the interface, hardware compatibility, telemetry semantics, analysis, and export formats may still change. Preview results should not be treated as laboratory certification.

<img width="1077" height="692" alt="image" src="https://github.com/user-attachments/assets/aa042060-0101-45d6-b030-d64f35927fdf" />


## Why Silemetry?

The name combines **silicon** and **telemetry**.

Silemetry is designed to answer a practical question:

> How much performance can this Mac actually sustain after heat, power limits, and workload duration begin to matter?

It records more than a single peak score. It preserves the full timeline so that different runs, cooling setups, room conditions, and workloads can be compared later.

## Highlights

- Native SwiftUI macOS application
- Apple Silicon only
- Embedded Rust telemetry core
- No Homebrew required for release users
- No Python runtime
- No `sudo`
- No kernel extension
- No SIP modification
- No external `mactop` or `macmon` process
- Controlled CPU stress-test presets
- Monitor Only mode for external workloads
- Live temperature, power, frequency, utilization, and phase views
- CPU hottest and average readable thermal-zone temperatures
- GPU hottest and average readable thermal-zone temperatures
- CPU, GPU, and package power where available
- P-cluster and E-cluster frequency
- Per-core CPU utilization
- Persistent test history
- Rename and delete saved runs
- Detailed results and data-quality information
- A/B comparison between compatible saved runs
- Local export formats supported by the current release candidate

## Current release

**Version:** `0.1.0-preview.1`

This preview is being published early because users already need a simple Apple Silicon sustained-performance recorder.

Primary validated configuration:

- 15-inch MacBook Air
- Apple M4
- 10-core CPU: 4 performance cores + 6 efficiency cores
- 24 GB unified memory
- macOS 26.5.2

Other Apple Silicon Macs may work, but have not yet received the same level of validation.

## Test modes

### Quick Check

A short run used to verify telemetry, workload startup, persistence, and charts.

Quick Check is **not long enough to establish thermal steady state**.

### Standard Test

A medium-length controlled run for routine comparison.

### Sustained Test

A longer run intended to reveal sustained power and frequency behavior after the chassis has heated up.

### Extended Test

A long-duration run for deeper thermal and performance analysis.

### Monitor Only

Records telemetry without starting Silemetry's internal workload.

Use it alongside:

- Cinebench
- Blender
- Endurance
- Xcode builds
- compilation workloads
- local AI inference
- video export
- another repeatable application

Monitor Only normally ends when the user chooses **Finish Recording**, unless a fixed duration was configured.

## Telemetry semantics

### CPU Hottest

The maximum temperature among the valid readable CPU thermal-zone sensors used by the embedded telemetry core.

It is **not claimed to be Apple's official junction temperature**, a documented TjMax value, or the only signal used by macOS thermal management.

### CPU Average

The arithmetic mean of the same valid readable CPU thermal-zone sensor group.

### GPU Hottest and GPU Average

The equivalent maximum and arithmetic mean for the valid readable GPU thermal-zone sensor group.

### Thermal State

Thermal State is the system-level thermal-pressure status reported by macOS:

- Nominal
- Fair
- Serious
- Critical

It is not the same as CPU Hottest. Thermal State may remain Nominal while an individual readable sensor is hot.

### Frequency

Silemetry distinguishes:

- P-cluster frequency
- E-cluster frequency
- per-core utilization

Cluster frequency must not be interpreted as ten independently measured instantaneous core clocks.

Any per-core frequency presented by a future build must state its exact source and semantics.

### Power

Power fields may include:

- CPU power
- GPU power
- package power
- additional domains exposed by the telemetry source

Unavailable values are shown as unavailable. Silemetry must not replace missing data with zero.

Derived metrics must be labeled as derived.

## Results, History, and Compare

A completed run can contain:

- temperature curves
- power curves
- P/E-cluster frequency curves
- per-core utilization
- peak and phase-average metrics
- test-phase timing
- sampling coverage
- missing or invalid sample information
- device and software metadata

Saved runs can be:

- reopened after restarting Silemetry
- renamed
- deleted
- selected for A/B comparison
- exported

Comparison results are only meaningful when the two runs are genuinely comparable. Important variables include:

- device and chip
- test mode
- workload configuration
- thread count
- test duration
- sampling interval
- AC or battery power
- Low Power Mode
- ambient temperature
- background activity
- Silemetry version
- telemetry-core version
- data-schema version

## Installation

### Download

1. Open the repository's **Releases** page.
2. Download the latest Apple Silicon DMG:
   `Silemetry-v0.1.0-preview.1-arm64.dmg`
3. Verify the SHA-256 checksum.
4. Open the DMG.
5. Drag **Silemetry.app** into **Applications**.
6. Launch Silemetry.

### Signing and Gatekeeper

The Releases page must state whether the build is:

- Developer ID signed and notarized, or
- ad-hoc signed / unsigned and not notarized

When a preview build is not notarized, macOS may block the first launch.

Use one of the normal macOS methods:

1. Control-click Silemetry in Applications.
2. Choose **Open**.
3. Confirm the launch.

Or approve it in:

`System Settings → Privacy & Security`

Do **not** disable Gatekeeper globally.

## Safety

Silemetry intentionally creates sustained computational load.

- The Mac enclosure may become hot.
- macOS remains responsible for hardware thermal protection.
- Silemetry does not disable thermal management.
- Silemetry does not modify voltage, clocks, power limits, fan policy, or SMC settings.
- Stop a test if the machine behaves unexpectedly.
- Keep fan vents unobstructed on Macs that have fans.
- Avoid placing a hot Mac on heat-sensitive surfaces.

## Privacy

Silemetry works locally.

- No user account
- No telemetry upload
- No analytics SDK
- No advertising SDK
- No cloud processing
- No background daemon
- No network connection required for testing

Saved runs are stored under Silemetry's Application Support directory and can be deleted from History.

## Known limitations

- This is an early preview and may contain bugs.
- Apple does not provide stable public APIs for every Apple Silicon telemetry field.
- A macOS update may change telemetry availability or semantics.
- Sensor sets and names may differ between M-series chips.
- The primary validated configuration is currently an M4 MacBook Air.
- Short tests do not establish steady state.
- Thermal State is not a direct CPU temperature-wall indicator.
- Per-core utilization is supported; per-core frequency semantics require careful validation.
- Compare is only trustworthy when both runs use comparable conditions.
- Some compact-window and localization issues may remain.
- Export coverage may differ by preview build.
- Signing and notarization status may differ between release assets.

## Reporting a bug

Please include:

- Mac model
- chip
- memory size
- macOS version
- Silemetry version and build
- telemetry-core version
- test mode
- reproduction steps
- expected behavior
- actual behavior
- screenshot
- exported Diagnostics, when available

Do not upload private or unrelated files.

## Build from source

### Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode with the macOS SDK
- stable Rust toolchain
- Git

Release users do not need Rust.

### Build

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

The internal Xcode project and scheme may temporarily retain the old `ThermalBench` name to reduce release risk. The installed product and public documentation use **Silemetry**.

Check `Docs/BUILDING.md` for the exact current command.

## Repository structure

```text
Silemetry/
├── ThermalBench/              # SwiftUI application source; internal name may remain temporarily
├── TelemetryCore/             # Embedded Rust telemetry library
├── WorkloadCore/              # Native workload implementation
├── ThermalBenchTests/
├── ThermalBenchUITests/
├── Scripts/
├── Docs/
├── LICENSE
└── THIRD_PARTY_NOTICES.md
```

## Application icon

Silemetry uses the icon:

**`ai-chip-robot-flat`** from the **Streamline Flex Color** icon collection.

- Author: Streamline
- Source: https://icon-sets.iconify.design/streamline-flex-color/ai-chip-robot-flat/
- License: Creative Commons Attribution 4.0 International
- License text: https://creativecommons.org/licenses/by/4.0/

The artwork is used without visual modification. It is only converted and resized into the image formats required by the macOS AppIcon asset catalog.

See `THIRD_PARTY_NOTICES.md` for the complete attribution.

## Third-party software

Silemetry includes vendored open-source components, including telemetry code derived from or based on `macmon`.

See `THIRD_PARTY_NOTICES.md` for:

- upstream project
- version or tag
- source commit
- license
- copyright
- included files
- local modifications

## Contributing

Bug reports and focused pull requests are welcome.

Please:

- keep changes scoped
- preserve the native SwiftUI + embedded Rust architecture
- add tests for telemetry, persistence, analysis, and migration changes
- document metric semantics
- avoid fake telemetry in release paths
- avoid Electron, WebView, Python GUI, or runtime Homebrew dependencies

See `CONTRIBUTING.md`.

## Roadmap

Near-term priorities:

- broader Apple Silicon validation
- responsive-layout fixes
- stronger Monitor Only workflows
- richer Results and export
- stricter comparison-validity checks
- improved thermal-state summaries
- improved localization
- signed and notarized builds
- automated release verification

The roadmap is not a delivery promise.

## License

Silemetry source code is released under the MIT License unless a file states otherwise.

See:

- `LICENSE`
- `THIRD_PARTY_NOTICES.md`

## Disclaimer

Silemetry is an independent open-source project.

It is not affiliated with, sponsored by, or endorsed by Apple Inc., Streamline, Iconify, or the maintainers of any telemetry dependency.

Apple, Mac, macOS, and Apple Silicon are trademarks of Apple Inc.
