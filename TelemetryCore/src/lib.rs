// ThermalBench TelemetryCore — embedded Rust telemetry using macmon
// Runs a background sampler thread, provides C ABI

pub mod sampler;
pub mod types;
pub mod ffi;

pub use sampler::TelemetrySampler;
pub use types::*;
