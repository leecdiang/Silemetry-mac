#!/bin/bash
# Build and run unit tests. Uses same toolchain as build_app.sh.
# Does not require sensors or Metal device.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
TEST_BIN="$BUILD_DIR/ThermalBenchTests"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "")

echo "=== ThermalBench Unit Tests ==="

mkdir -p "$BUILD_DIR"

SWIFT_SRC=$(find "$PROJECT_DIR/ThermalBench" -name "*.swift" ! -path "*/App/*" | sort)
TEST_SRC="$PROJECT_DIR/ThermalBenchTests/ThermalBenchTestMain.swift"

swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macos14.0 \
    -F "$SDK_PATH/System/Library/Frameworks" \
    -framework SwiftUI -framework SwiftData -framework Charts \
    -framework AppKit -framework Metal -framework MetalKit \
    -framework IOKit -framework CoreFoundation \
    -lIOReport \
    -import-objc-header "$PROJECT_DIR/ThermalBench/App/Bridging-Header.h" \
    -I"$PROJECT_DIR/ThermalBench/Services" \
    -I"$PROJECT_DIR/WorkloadCore/include" \
    -I"$PROJECT_DIR/TelemetryCore/include" \
    -I"$BUILD_DIR" \
    -L"$BUILD_DIR" \
    -lthermalbench_telemetry_core \
    -o "$TEST_BIN" \
    -module-name ThermalBenchTests \
    $SWIFT_SRC \
    "$TEST_SRC" \
    "$BUILD_DIR/cpu_workload.o" \
    "$BUILD_DIR/sensor_bridge.o" \
    "$BUILD_DIR/core_utilization.o" \
    "$BUILD_DIR/libthermalbench_telemetry_core.a" \
    2>&1

if [[ -f "$TEST_BIN" ]]; then
    echo "Test binary built"
    echo "---"
    "$TEST_BIN"
    TEST_EXIT=$?
    echo "---"
    echo "Exit: $TEST_EXIT"
    exit $TEST_EXIT
else
    echo "FAIL: compilation failed"
    exit 1
fi
