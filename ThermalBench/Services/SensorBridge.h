// ThermalBench - Sensor Bridge C header
// Real sensor data via IOHIDEventSystemClient, IOReport, IOPowerSources
#ifndef SENSOR_BRIDGE_H
#define SENSOR_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    double cpu_temp_c;          // CPU temperature, NaN if unavailable
    double gpu_temp_c;          // GPU temperature, NaN if unavailable
    double soc_temp_c;          // SoC temperature, NaN if unavailable
    bool   valid;               // true if at least one temp is valid
} tb_temps_t;

typedef struct {
    double cpu_power_w;         // CPU power in Watts, NaN if unavailable
    double gpu_power_w;
    double package_power_w;
    double p_cluster_freq_mhz;  // P-core frequency
    double e_cluster_freq_mhz;  // E-core frequency
    double cpu_util_pct;        // CPU utilization percent
    bool   power_valid;
    bool   freq_valid;
} tb_power_freq_t;

typedef struct {
    int32_t  battery_percent;   // -1 if unavailable
    bool     ac_connected;
    bool     battery_valid;
} tb_battery_t;

typedef struct {
    int32_t state;  // 0=nominal 1=fair 2=serious 3=critical 4=unknown
} tb_thermal_t;

// Read temperatures via IOHIDEventSystemClient
tb_temps_t tb_read_temperatures(void);

// Read power/frequency via IOReport
tb_power_freq_t tb_read_power_frequency(void);

// Read battery status via IOPowerSources
tb_battery_t tb_read_battery(void);

// Read thermal state
tb_thermal_t tb_read_thermal_state(void);

#endif
