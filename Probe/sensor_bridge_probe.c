// SensorBridgeProbe — standalone C probe, bypasses Swift/TestCoordinator/UI
#include "../ThermalBench/Services/SensorBridge.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void print_temps(const char *label, tb_temps_t r) {
    printf("%s: valid=%d cpu=%.4f gpu=%.4f soc=%.4f\n",
           label, (int)r.valid, r.cpu_temp_c, r.gpu_temp_c, r.soc_temp_c);
}
static void print_power(const char *label, tb_power_freq_t r) {
    printf("%s: power_valid=%d freq_valid=%d\n", label, (int)r.power_valid, (int)r.freq_valid);
    printf("  cpu_power=%.6f gpu_power=%.6f package_power=%.6f\n",
           r.cpu_power_w, r.gpu_power_w, r.package_power_w);
    printf("  p_freq=%.2f e_freq=%.2f cpu_util=%.2f\n",
           r.p_cluster_freq_mhz, r.e_cluster_freq_mhz, r.cpu_util_pct);
}
static void print_battery(const char *label, tb_battery_t r) {
    printf("%s: valid=%d pct=%d ac=%d\n",
           label, (int)r.battery_valid, (int)r.battery_percent, (int)r.ac_connected);
}

int main(void) {
    printf("=== SensorBridgeProbe ===\n");
    printf("sizeof(tb_temps_t)=%zu\n", sizeof(tb_temps_t));
    printf("sizeof(tb_power_freq_t)=%zu\n", sizeof(tb_power_freq_t));
    printf("sizeof(tb_battery_t)=%zu\n", sizeof(tb_battery_t));
    printf("sizeof(tb_thermal_t)=%zu\n", sizeof(tb_thermal_t));
    printf("\n");

    // Field offsets
    #define OFF(s,f) printf("  offsetof(%s, %s)=%zu\n", #s, #f, offsetof(s, f))
    printf("tb_temps_t layout:\n");
    OFF(tb_temps_t, cpu_temp_c);
    OFF(tb_temps_t, gpu_temp_c);
    OFF(tb_temps_t, soc_temp_c);
    OFF(tb_temps_t, valid);
    printf("tb_power_freq_t layout:\n");
    OFF(tb_power_freq_t, cpu_power_w);
    OFF(tb_power_freq_t, gpu_power_w);
    OFF(tb_power_freq_t, package_power_w);
    OFF(tb_power_freq_t, p_cluster_freq_mhz);
    OFF(tb_power_freq_t, e_cluster_freq_mhz);
    OFF(tb_power_freq_t, cpu_util_pct);
    OFF(tb_power_freq_t, power_valid);
    OFF(tb_power_freq_t, freq_valid);
    printf("tb_battery_t layout:\n");
    OFF(tb_battery_t, battery_percent);
    OFF(tb_battery_t, ac_connected);
    OFF(tb_battery_t, battery_valid);
    printf("\n");

    // Collect 10 samples, 1 per second
    for (int i = 1; i <= 12; i++) {
        printf("=== sample=%d ===\n", i);
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        printf("timestamp=%ld.%09ld\n", (long)ts.tv_sec, ts.tv_nsec);

        tb_temps_t temps = tb_read_temperatures();
        print_temps("TEMPS", temps);

        tb_power_freq_t pf = tb_read_power_frequency();
        print_power("POWER_FREQ", pf);

        tb_battery_t batt = tb_read_battery();
        print_battery("BATTERY", batt);

        tb_thermal_t therm = tb_read_thermal_state();
        printf("THERMAL: state=%d\n", therm.state);

        fflush(stdout);
        if (i < 12) sleep(1);
    }

    printf("=== DONE ===\n");
    return 0;
}
