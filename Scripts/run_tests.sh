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

# Generate build identity (same injection as build_app.sh)
GIT_SHA=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date -u +%H%M%S)
cat > "$BUILD_DIR/BuildIdentityGenerated.swift" <<EOF
enum BuildIdentityGenerated {
    static let gitSHA = "$GIT_SHA"
    static let buildTimestampUTC = "$BUILD_TIME"
}
EOF

# The test binary is a bare command-line tool with no app bundle. SwiftData's
# ModelContainer (needed for @Model inits on macOS 14.x) requires a bundle
# name; embed a minimal Info.plist into the __TEXT section so Bundle.main
# resolves it.
cat > "$BUILD_DIR/TestInfo.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ThermalBenchTests</string>
    <key>CFBundleIdentifier</key><string>com.leecdiang.ThermalBenchTests</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.2.1</string>
</dict>
</plist>
PLIST

SWIFT_SRC=$(find "$PROJECT_DIR/ThermalBench" -name "*.swift" ! -path "*/App/*" | sort)
SWIFT_SRC="$SWIFT_SRC $BUILD_DIR/BuildIdentityGenerated.swift"
TEST_SRC="$PROJECT_DIR/ThermalBenchTests/ThermalBenchTestMain.swift $PROJECT_DIR/ThermalBenchTests/ThermalBenchTestSuite.swift"

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
    -o "$TEST_BIN" \
    -module-name ThermalBenchTests \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$BUILD_DIR/TestInfo.plist" \
    $SWIFT_SRC \
    $TEST_SRC \
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
