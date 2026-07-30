// ThermalBench TelemetryCore — C ABI Header
// Embedded Rust telemetry via macmon library
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    TB_OK = 0,
    TB_ERR_INVALID_ARGUMENT = 1,
    TB_ERR_ALREADY_STARTED = 2,
    TB_ERR_NOT_STARTED = 3,
    TB_ERR_INITIALIZATION = 4,
    TB_ERR_TIMEOUT = 5,
    TB_ERR_STOPPED = 6,
    TB_ERR_UNSUPPORTED = 7,
    TB_ERR_INTERNAL = 8
} TBErrorCode;

typedef struct {
    uint64_t sequence_id;
    uint64_t monotonic_timestamp_ns;
    int64_t  wall_clock_unix_ns;

    double cpu_temperature_avg_c;
    double cpu_temperature_hottest_c;
    double gpu_temperature_avg_c;
    double gpu_temperature_hottest_c;

    uint32_t cpu_temperature_sensor_count;
    uint32_t gpu_temperature_sensor_count;
    uint32_t _reserved1;

    double cpu_power_w;
    double gpu_power_w;
    double ane_power_w;
    double dram_power_w;
    double package_power_w;

    double p_cluster_frequency_mhz;
    double e_cluster_frequency_mhz;

    double p_cluster_utilization_ratio;
    double e_cluster_utilization_ratio;
    double cpu_utilization_ratio;
    double gpu_utilization_ratio;

    uint64_t available_mask;
    uint64_t valid_mask;
    uint64_t derived_mask;
    uint64_t warning_mask;
} TBTelemetrySample;

// Availability mask constants (must be static const for Swift import)
static const uint64_t TB_AVAIL_CPU_TEMP      = UINT64_C(1) << 0;
static const uint64_t TB_AVAIL_GPU_TEMP      = UINT64_C(1) << 1;
static const uint64_t TB_AVAIL_CPU_POWER     = UINT64_C(1) << 2;
static const uint64_t TB_AVAIL_GPU_POWER     = UINT64_C(1) << 3;
static const uint64_t TB_AVAIL_ANE_POWER     = UINT64_C(1) << 4;
static const uint64_t TB_AVAIL_DRAM_POWER    = UINT64_C(1) << 5;
static const uint64_t TB_AVAIL_PACKAGE_POWER = UINT64_C(1) << 6;
static const uint64_t TB_AVAIL_P_FREQ        = UINT64_C(1) << 7;
static const uint64_t TB_AVAIL_E_FREQ        = UINT64_C(1) << 8;
static const uint64_t TB_AVAIL_P_USAGE       = UINT64_C(1) << 9;
static const uint64_t TB_AVAIL_E_USAGE       = UINT64_C(1) << 10;
static const uint64_t TB_AVAIL_CPU_USAGE     = UINT64_C(1) << 11;
static const uint64_t TB_AVAIL_GPU_USAGE     = UINT64_C(1) << 12;
static const uint64_t TB_AVAIL_CPU_TEMP_HOTTEST = UINT64_C(1) << 13;
static const uint64_t TB_AVAIL_GPU_TEMP_HOTTEST = UINT64_C(1) << 14;
static const uint64_t TB_AVAIL_CPU_SENSOR_COUNT = UINT64_C(1) << 15;
static const uint64_t TB_AVAIL_GPU_SENSOR_COUNT = UINT64_C(1) << 16;

// Handle type
typedef void *TBTelemetryHandle;

// --- Core API ---

TBTelemetryHandle tb_telemetry_create(void);

TBErrorCode tb_telemetry_start(
    TBTelemetryHandle handle,
    uint32_t interval_ms
);

TBErrorCode tb_telemetry_wait_next(
    TBTelemetryHandle handle,
    uint64_t after_sequence_id,
    uint32_t timeout_ms,
    TBTelemetrySample *out_sample
);

uint64_t tb_telemetry_capabilities(
    TBTelemetryHandle handle
);

TBErrorCode tb_telemetry_last_error(
    TBTelemetryHandle handle,
    char *buffer,
    uint32_t buffer_len
);

TBErrorCode tb_telemetry_stop(
    TBTelemetryHandle handle
);

void tb_telemetry_destroy(
    TBTelemetryHandle handle
);

const char *tb_telemetry_core_version(void);

#ifdef __cplusplus
}
#endif
