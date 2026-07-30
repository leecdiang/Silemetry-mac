# FIX_LIVE_UI_DATA_REPORT

## Four Issue Root Cause Analysis

### Issue 1: Data not displayed (top metrics "--", charts empty)

**Root cause**: `TelemetryService.readSample()` creates `TelemetrySample` structs where most fields are never populated:
- Temperature: `IOHIDEventSystemClient` wrapper is a private stub class whose `copyTemperatureEvents()` returns `(0, 0)`
- Power/Frequency: The Rust `TelemetryCore::read_sample()` sets `power_valid = true` but doesn't extract actual IOReport channel values into the sample - all numeric fields remain `i32::MIN` (unavailable marker)
- Battery: Uses `@_silgen_name` extern C declarations that may not properly bridge `IOPowerSources` on all macOS versions
- The bridging header includes C headers but Swift's C function bridge may not auto-import IOKit function declarations
- TestCoordinator's sampling loop calls `telemetry.readSample()` but receives structs with all nil fields
- The data path: Rust Engine → C ABI → Swift C-call → nil struct → Chart gets nothing

### Issue 2: Can't return to Home after test

**Root cause**: `ContentView` has no separate navigation state. It switches entirely on `coordinator.state`:
- When state == .finished, it shows `ResultsView` permanently
- `ResultsView` has no "Done" or "Back to Home" button
- The sidebar "Home" click doesn't reset coordinator state because there's no `resetForNewRun()` method
- Navigation state (which page to show) and Run lifecycle state (was test completed) are conflated into one enum

### Issue 3: Power status not updating

**Root cause**: `HomeView` device header hard-codes labels at build time, with no `PowerSourceMonitor`:
- No IOKit power source notification subscription
- No periodic refresh of `IOPowerSources` data
- No `@Published` power source property that triggers UI re-render when AC/Battery changes

### Issue 4: UI quality

**Root cause**: Home layout uses basic GroupBox+VStack with no adaptive spacing. Charts have no proper axis labels, empty states, or phase markers. Test preset buttons are undifferentiated gray rectangles.

## Fix Plan

### Fix 1: TelemetryService → Real Sensor Data (TelemetryService.swift, plus TelemetrySample model changes)

Replace the broken IOKit bridge with direct system API calls:
- Import `IOKit/pwr_mgt_private.h` or use IOPowerSources via `CF` bridge properly
- Add IOHIDEventSystemClient temperature reading via `IOKit/hid/IOHIDEventSystemClient.h`
- Read IOReport power/frequency values via `libIOReport.dylib` C dylib
- Ensure all fields are populated from real data

### Fix 2: Navigation State Machine (ContentView.swift, TestCoordinator.swift)

- Add `AppRoute` enum for navigation state
- Add `resetForNewRun()` to TestCoordinator
- Add "Done" button to ResultsView
- Ensure sidebar Home click resets to home route

### Fix 3: PowerSourceMonitor (PowerSourceMonitor.swift, new file)

- Create an ObservableObject PowerSourceMonitor
- Use IOPSNotificationCreateRunLoopSource
- Subscribe to power source changes
- Update `@Published var powerSource` property
- HomeView reads from AppModel's monitor

### Fix 4: UI improvements (HomeView.swift, TestView.swift, ResultsView.swift)

- HomeView: balanced layout, device summary with real-time data, only one Custom entry, test cards with SF Symbols
- TestView: phase progress bar, proper metric strip, chart axes/labels, empty chart states, destructive Stop button
- ResultsView: Done button, key metrics, data quality
