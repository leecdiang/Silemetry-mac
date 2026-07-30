// Stable types for C ABI

#[repr(C)]
#[derive(Default, Clone, Copy)]
pub struct TBTelemetrySample {
    pub sequence_id: u64,
    pub monotonic_timestamp_ns: u64,
    pub wall_clock_unix_ns: i64,

    // Temperatures (°C)
    pub cpu_temperature_avg_c: f64,
    pub cpu_temperature_hottest_c: f64,
    pub gpu_temperature_avg_c: f64,
    pub gpu_temperature_hottest_c: f64,

    // Sensor counts
    pub cpu_temperature_sensor_count: u32,
    pub gpu_temperature_sensor_count: u32,
    pub _reserved1: u32,

    // Power (W)
    pub cpu_power_w: f64,
    pub gpu_power_w: f64,
    pub ane_power_w: f64,
    pub dram_power_w: f64,
    pub package_power_w: f64,

    // Frequencies (MHz)
    pub p_cluster_frequency_mhz: f64,
    pub e_cluster_frequency_mhz: f64,

    // Utilization (0.0-1.0)
    pub p_cluster_utilization_ratio: f64,
    pub e_cluster_utilization_ratio: f64,
    pub cpu_utilization_ratio: f64,
    pub gpu_utilization_ratio: f64,

    // Availability flags
    pub available_mask: u64,
    pub valid_mask: u64,
    pub derived_mask: u64,
    pub warning_mask: u64,
}

// Availability bits
pub const TB_AVAIL_CPU_TEMP: u64 = 1 << 0;
pub const TB_AVAIL_GPU_TEMP: u64 = 1 << 1;
pub const TB_AVAIL_CPU_POWER: u64 = 1 << 2;
pub const TB_AVAIL_GPU_POWER: u64 = 1 << 3;
pub const TB_AVAIL_ANE_POWER: u64 = 1 << 4;
pub const TB_AVAIL_DRAM_POWER: u64 = 1 << 5;
pub const TB_AVAIL_PACKAGE_POWER: u64 = 1 << 6;
pub const TB_AVAIL_P_FREQ: u64 = 1 << 7;
pub const TB_AVAIL_E_FREQ: u64 = 1 << 8;
pub const TB_AVAIL_P_USAGE: u64 = 1 << 9;
pub const TB_AVAIL_E_USAGE: u64 = 1 << 10;
pub const TB_AVAIL_CPU_USAGE: u64 = 1 << 11;
pub const TB_AVAIL_GPU_USAGE: u64 = 1 << 12;
pub const TB_AVAIL_CPU_TEMP_HOTTEST: u64 = 1 << 13;
pub const TB_AVAIL_GPU_TEMP_HOTTEST: u64 = 1 << 14;
pub const TB_AVAIL_CPU_SENSOR_COUNT: u64 = 1 << 15;
pub const TB_AVAIL_GPU_SENSOR_COUNT: u64 = 1 << 16;

#[repr(C)]
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum TBErrorCode {
    Ok = 0,
    InvalidArgument = 1,
    AlreadyStarted = 2,
    NotStarted = 3,
    Initialization = 4,
    Timeout = 5,
    Stopped = 6,
    Unsupported = 7,
    Internal = 8,
}

impl Default for TBErrorCode {
    fn default() -> Self { TBErrorCode::Internal }
}

impl TBErrorCode {
    pub fn as_str(&self) -> &'static str {
        match self {
            TBErrorCode::Ok => "OK",
            TBErrorCode::InvalidArgument => "Invalid argument",
            TBErrorCode::AlreadyStarted => "Already started",
            TBErrorCode::NotStarted => "Not started",
            TBErrorCode::Initialization => "Initialization failed",
            TBErrorCode::Timeout => "Timeout",
            TBErrorCode::Stopped => "Stopped",
            TBErrorCode::Unsupported => "Unsupported",
            TBErrorCode::Internal => "Internal error",
        }
    }
}
