#!/bin/bash
# ThermalBench: build TelemetryCore Rust static library
set -euo pipefail
cd "$(dirname "$0")/../TelemetryCore"

echo "=== Building TelemetryCore ==="
cargo build --release --target aarch64-apple-darwin

# Verify
LIB="target/aarch64-apple-darwin/release/libtelemetry_core.a"
if [[ -f "$LIB" ]]; then
    echo "✅ $LIB ($(du -h "$LIB" | cut -f1))"
else
    echo "❌ build failed"
    exit 1
fi

# Copy to build directory
mkdir -p ../build
cp "$LIB" ../build/libTelemetryCore.a
cp include/telemetry_core.h ../build/
echo "✅ Copied to ../build/"
