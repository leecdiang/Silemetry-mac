# Changelog

All notable changes to Silemetry are documented here.

## [0.2.1] - 2026-08-03

### Fixed (stability & data integrity)

- **Telemetry handle lifecycle & concurrency**: all Rust-handle FFI
  (create/start/wait/stop/destroy) now runs on one serial queue; stop is
  enqueued behind in-flight reads so `wait_next` returns before `destroy` —
  no concurrent alias / use-after-free. The actor never touches the raw
  pointer again. `TBTelemetryHandle` is wrapped in an `@unchecked Sendable`
  box so the safety invariant is type-checked (clears Swift 6-mode
  Sendable warnings).
- **Per-metric validity masks**: Rust `available_mask` is now per-metric
  (sensor count + is_finite + sane range for temps, finite/≥0 power, >0
  freq, 0..1 usage) instead of a blanket valid flag; first sample no longer
  skipped (Rust seq starts at 1).
- **Stop / Discard / failure finalization**: discard after a failed save
  deletes the run from the model context explicitly; failure state and
  archive write errors are surfaced in the UI.
- **JSONL archive integrity & streaming summaries**: `ArchiveLoadResult`
  cross-checks the file on disk (lines/malformed/existence) against the
  stored summary; stored `Complete` degrades to `Partial` at runtime when
  the archive is missing/truncated/corrupt (Results + Compare). JSONL
  decode streams line-by-line in 64 KB chunks — lower peak memory.
- **Compare comparability & corrupt-data checks**: verdict uses disk-
  effective raw status so the top verdict, details table and curve banner
  can never contradict; comparability rules tightened (ambient diff >2 °C,
  both-unknown conditions, both-legacy key metadata now warn).
- **SwiftData rollback & file transactions**: failed inserts roll back
  immediately (Retry re-inserts; Discard removes files only); History
  deletes/renames roll back with files restored / old name kept; sample
  dirs staged in Trash, purged only after the record deletion saves.
- **Dynamic device, power-source changes & true startedAt**: `RunRecord`
  stores power source / Low Power Mode at start+end with change flags;
  Compare warns when a run changed AC↔battery or low-power mid-test;
  `createdAt` reflects the actual test start time; battery-unreadable runs
  stay Unknown instead of being mislabeled Battery; `saveInterrupted`
  finalizes from the streaming accumulator, not the UI ring buffer;
  Monitor Only failure count is consecutive-only.

### Fixed (CI)

- Swift 6 strict-concurrency compatibility: `@MainActor` on views binding
  `AppModel` for Xcode 15.4, in-memory `ModelContainer` + embedded
  `Info.plist` for the standalone test binary (macOS 14 runtime).
- 70/70 tests passing, CI #15 success.

## [0.2.0] - 2026-07-30

### Added

- Metal GPU stress testing (Moderate / Maximum) via `GPUWorkloadManager`
- CPU Only / GPU Only / CPU+GPU independent modes
- P/E-core QoS scheduling preference (all / P / E)
- Full Custom Test configuration (durations, interval, ambient temp)
- Dynamic device profile (model, chip, P/E topology, memory, macOS, Metal)
- Battery status & Low Power Mode awareness (`BatteryStatusIcon`)
- Adaptive phase status (`StatusPill`)
- New application icon

## [0.1.0] - 2026-07-29

### Added

- Initial preview release: CPU stress test, live telemetry (temp / power /
  frequency / per-core utilization / thermal state), History & Compare,
  Monitor Only mode.
