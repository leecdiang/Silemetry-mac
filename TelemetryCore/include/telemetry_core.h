#ifndef TELEMETRY_CORE_H
#define TELEMETRY_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Error codes                                                        */
/* ------------------------------------------------------------------ */
typedef enum {
    TB_OK = 0,
    TB_ERROR_UNKNOWN = -1,
    TB_ERROR_NOT_INITIALIZED = -2,
    TB_ERROR_ALREADY_RUNNING = -3,
    TB_ERROR_INVALID_ARGUMENT = -4,
    TB_ERROR_IO_REPORT_FAILED = -5,
    TB_ERROR_HID_FAILED = -6,
    TB_ERROR_POWER_SOURCE_FAILED = -7,
    TB_ERROR_SAMPLE_UNAVAILABLE = -8,
    TB_ERROR_NO_MEMORY = -9,
    TB_ERROR_INTERNAL = -10,
} tb_error_t;

/* ------------------------------------------------------------------ */
/* Sample structure (fixed-size, ABI-stable)                           */
/* ------------------------------------------------------------------ */
#define TB_MAX_WARNING_LEN 256
#define TB_MAX_SOURCE_LEN  64

typedef struct {
    /* Timestamps */
    uint64_t timestamp_monotonic_ns;
    int64_t  timestamp_wall_clock;     /* unix epoch, microseconds */

    /* Temperatures (Celsius × 1000, or INT32_MIN if unavailable) */
    int32_t  cpu_temperature_c;
    int32_t  gpu_temperature_c;
    int32_t  soc_temperature_c;

    /* Power (Watts × 1000) */
    int32_t  cpu_power_w;
    int32_t  gpu_power_w;
    int32_t  ane_power_w;
    int32_t  dram_power_w;
    int32_t  package_power_w;
    int32_t  p_cluster_power_w;
    int32_t  e_cluster_power_w;

    /* Frequencies (MHz) */
    int32_t  p_cluster_frequency_mhz;
    int32_t  e_cluster_frequency_mhz;

    /* Utilization (percent × 100) */
    int32_t  cpu_utilization_pct;
    int32_t  gpu_utilization_pct;
    int32_t  p_cluster_utilization_pct;
    int32_t  e_cluster_utilization_pct;

    /* Memory */
    int64_t  memory_used_bytes;

    /* Battery */
    int32_t  battery_percent;
    int32_t  battery_power_w;
    bool     ac_connected;
    bool     low_power_mode;

    /* Thermal state: 0=nominal 1=fair 2=serious 3=critical 4=unknown */
    int32_t  thermal_state;

    /* Fan RPM (always 0 on MacBook Air) */
    int32_t  fan_rpm;

    /* Quality metadata per value group */
    bool     temp_valid;
    bool     power_valid;
    bool     freq_valid;
    bool     util_valid;
    bool     battery_valid;

    /* Warning */
    char     warning[TB_MAX_WARNING_LEN];
    char     source[TB_MAX_SOURCE_LEN];
} tb_sample_t;

/* ------------------------------------------------------------------ */
/* Capability probe info                                              */
/* ------------------------------------------------------------------ */
#define TB_MAX_CAPABILITIES 32

typedef struct {
    char name[64];
    bool available;
    char source[64];
    char note[256];
} tb_capability_t;

typedef struct {
    uint32_t count;
    tb_capability_t capabilities[TB_MAX_CAPABILITIES];
} tb_capabilities_t;

/* ------------------------------------------------------------------ */
/* Lifecycle                                                          */
/* ------------------------------------------------------------------ */

/* Create a telemetry instance. Returns opaque handle or NULL. */
void* tb_telemetry_create(void);

/* Probe capabilities without starting collection. */
tb_error_t tb_telemetry_capabilities(void *handle, tb_capabilities_t *caps);

/* Start sampling at given interval_ms. Must be >= 50ms. */
tb_error_t tb_telemetry_start(void *handle, uint32_t interval_ms);

/* Read the latest sample. Returns error if no sample available yet.
   Blocks for at most timeout_ms, or 0 to return immediately. */
tb_error_t tb_telemetry_read(void *handle, tb_sample_t *sample, uint32_t timeout_ms);

/* Get last error message (thread-local). */
const char* tb_telemetry_last_error(void *handle);

/* Stop sampling. Can be called multiple times. */
tb_error_t tb_telemetry_stop(void *handle);

/* Destroy and free all resources. */
tb_error_t tb_telemetry_destroy(void *handle);

/* ------------------------------------------------------------------ */
/* Utility                                                            */
/* ------------------------------------------------------------------ */

/* Return version string. */
const char* tb_telemetry_version(void);

/* Return Rust source commit. */
const char* tb_telemetry_source_commit(void);

#ifdef __cplusplus
}
#endif

#endif /* TELEMETRY_CORE_H */
