#!/bin/bash
# ThermalBench: Full project build script
# Builds Rust TelemetryCore, C CPU workload, Metal shaders, SwiftUI App
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Silemetry"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")

echo "=== ThermalBench Build ==="
echo "Project: $PROJECT_DIR"
echo "SDK: $SDK_PATH"
echo ""

# ─── 1. Rust TelemetryCore (macmon-based) ───────────────────────────────
NEW_TELEMETRY_LIB="$PROJECT_DIR/TelemetryCore/target/aarch64-apple-darwin/release/libthermalbench_telemetry_core.a"
BUILT_TELEMETRY_LIB="$BUILD_DIR/libthermalbench_telemetry_core.a"
if command -v cargo &>/dev/null; then
    echo "--- Building Rust TelemetryCore ---"
    cd "$PROJECT_DIR/TelemetryCore"
    cargo build --release --target aarch64-apple-darwin 2>&1 | tail -3
    if [[ -f "$NEW_TELEMETRY_LIB" ]]; then
        cp "$NEW_TELEMETRY_LIB" "$BUILT_TELEMETRY_LIB"
        echo "✅ libthermalbench_telemetry_core.a ($(du -h "$NEW_TELEMETRY_LIB" | cut -f1))"
    else
        echo "❌ Rust build failed"
        exit 1
    fi
elif [[ -f "$NEW_TELEMETRY_LIB" ]]; then
    cp "$NEW_TELEMETRY_LIB" "$BUILT_TELEMETRY_LIB"
    echo "✅ libthermalbench_telemetry_core.a (prebuilt)"
elif [[ -f "$BUILT_TELEMETRY_LIB" ]]; then
    echo "✅ libthermalbench_telemetry_core.a (already in build dir)"
else
    echo "❌ No Rust toolchain and no prebuilt telemetry core"
    exit 1
fi

# ─── 2. C Sources ─────────────────────────────────────────────────────────
echo "--- Building C Sources ---"
cc -arch arm64 -O2 -c \
    -I"$PROJECT_DIR/WorkloadCore/include" \
    "$PROJECT_DIR/WorkloadCore/cpu_workload.c" \
    -o "$BUILD_DIR/cpu_workload.o"
echo "✅ cpu_workload.o"

cc -arch arm64 -O2 -c \
    -I"$PROJECT_DIR/ThermalBench/Services" \
    -framework CoreFoundation \
    -framework IOKit \
    "$PROJECT_DIR/ThermalBench/Services/SensorBridge.c" \
    -o "$BUILD_DIR/sensor_bridge.o" 2>&1
echo "✅ sensor_bridge.o"

cc -arch arm64 -O2 -c \
    -I"$PROJECT_DIR/ThermalBench/Services" \
    "$PROJECT_DIR/ThermalBench/Services/CoreUtilization.c" \
    -o "$BUILD_DIR/core_utilization.o" 2>&1
echo "✅ core_utilization.o"

# ─── 3. Metal Shaders ────────────────────────────────────────────────────
echo "--- Compiling Metal Shaders ---"
xcrun -sdk macosx metal \
    -c "$PROJECT_DIR/WorkloadCore/metal/thermal_gpu.metal" \
    -o "$BUILD_DIR/thermal_gpu.air"
xcrun -sdk macosx metallib \
    "$BUILD_DIR/thermal_gpu.air" \
    -o "$BUILD_DIR/default.metallib"
echo "✅ default.metallib"

# ─── 4. Swift Compilation ────────────────────────────────────────────────
echo "--- Compiling Swift App ---"

SWIFT_FILES=$(find "$PROJECT_DIR/ThermalBench" -name "*.swift" | sort)
# External C function declarations
C_LIBS=(
    "$BUILD_DIR/cpu_workload.o"
    "$BUILD_DIR/sensor_bridge.o"
    "$BUILD_DIR/core_utilization.o"
    "$BUILD_DIR/libthermalbench_telemetry_core.a"
)

# Build Swift module
SWIFT_FLAGS=(
    -sdk "$SDK_PATH"
    -target arm64-apple-macos14.0
    -O
    -F "$SDK_PATH/System/Library/Frameworks"
    -framework SwiftUI
    -framework SwiftData
    -framework Charts
    -framework AppKit
    -framework Metal
    -framework MetalKit
    -framework IOKit
    -framework CoreFoundation
    -lIOReport
    -import-objc-header "$PROJECT_DIR/ThermalBench/App/Bridging-Header.h"
    -I"$PROJECT_DIR/ThermalBench/Services"
    -I"$PROJECT_DIR/WorkloadCore/include"
    -I"$PROJECT_DIR/TelemetryCore/include"
    -I"$BUILD_DIR"
    -o "$BUILD_DIR/$APP_NAME"
    -parse-as-library
    -module-name ThermalBench
)

echo "Compiling $(echo $SWIFT_FILES | wc -w) Swift files..."
swiftc "${SWIFT_FLAGS[@]}" \
    $SWIFT_FILES \
    "${C_LIBS[@]}" \
    2>&1

if [[ -f "$BUILD_DIR/$APP_NAME" ]]; then
    echo "✅ Swift binary built"
else
    echo "⚠️  Swift compilation had issues—creating app bundle manually"
fi

# ─── 5. Create .app Bundle ───────────────────────────────────────────────
echo "--- Creating .app Bundle ---"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>Silemetry</string>
    <key>CFBundleName</key><string>Silemetry</string>
    <key>CFBundleIdentifier</key><string>com.leecdiang.Silemetry</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleExecutable</key><string>Silemetry</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>Silemetry</string>
</dict>
</plist>
PLIST

# Copy binary
if [[ -f "$BUILD_DIR/$APP_NAME" ]]; then
    cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
    chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

# Copy Metal library
cp "$BUILD_DIR/default.metallib" "$APP_BUNDLE/Contents/Resources/"

# Copy app icon
if ! cp "$PROJECT_DIR/Resources/ThirdParty/Streamline/Silemetry.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null; then
    echo "⚠️  Icon file not found — skipping"
fi

# Ad-hoc sign
if command -v codesign &>/dev/null; then
    codesign --force --sign - "$APP_BUNDLE" || echo "⚠️  codesign failed"
fi

echo "✅ $APP_BUNDLE"

# ─── 6. Verify ───────────────────────────────────────────────────────────
echo "--- Verification ---"
echo "Bundle size: $(du -sh "$APP_BUNDLE" 2>/dev/null | cut -f1)"
echo "Libraries:"
ls -la "$BUILD_DIR"/*.a "$BUILD_DIR"/*.o 2>/dev/null || true
echo ""
echo "App: $APP_BUNDLE"
echo "Run: open $APP_BUNDLE"
echo "=== Build Complete ==="
