// Per-core CPU utilization via host_processor_info
// Called from Swift, no Rust FFI needed
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/sysctl.h>

#define MAX_CORES 32

typedef struct {
    uint32_t logical_index;      // OS logical core index
    uint32_t kind;               // 0=efficiency, 1=performance, 2=unknown
    double utilization_percent;  // 0-100
    uint32_t valid;              // 1=valid, 0=waiting for first delta
    uint64_t _reserved;
} CoreUtilInfo;

typedef struct {
    uint32_t core_count;
    uint32_t p_core_count;
    uint32_t e_core_count;
    CoreUtilInfo cores[MAX_CORES];
    uint32_t error_code;
    char error_message[256];
} CoreUtilSnapshot;

static int g_initialized = 0;
static uint32_t g_core_count = 0;
static uint32_t g_p_count = 0;
static uint32_t g_e_count = 0;
static processor_cpu_load_info_data_t g_prev[MAX_CORES];
static int g_has_prev = 0;

/// Read P/E core counts from sysctl hw.perflevelN.logicalcpu (dynamic, no hardcoding).
/// On Apple Silicon logical CPUs are enumerated E-cores first, then P-cores.
/// perflevel0 = P-cores, perflevel1 = E-cores.
static void detect_topology(uint32_t count) {
    g_core_count = count;
    int32_t p = 0, e = 0;
    size_t sz = sizeof(p);
    if (sysctlbyname("hw.perflevel0.logicalcpu", &p, &sz, NULL, 0) == 0) {}
    sz = sizeof(e);
    if (sysctlbyname("hw.perflevel1.logicalcpu", &e, &sz, NULL, 0) == 0) {}

    if (p > 0 && e > 0 && (uint32_t)(p + e) == count) {
        g_p_count = (uint32_t)p;
        g_e_count = (uint32_t)e;
        return;
    }

    // Fallback: topology unknown — do NOT guess a half/half P/E split.
    // All cores are classified as unknown instead of being mislabeled.
    g_p_count = 0;
    g_e_count = 0;
}

CoreUtilSnapshot core_util_snapshot(void) {
    CoreUtilSnapshot snap;
    memset(&snap, 0, sizeof(snap));
    
    host_t host = mach_host_self();
    processor_cpu_load_info_data_t *cpuInfo = NULL;
    natural_t processorCount = 0;
    mach_msg_type_number_t infoCount = 0;
    
    kern_return_t kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                                           &processorCount,
                                           (processor_info_array_t*)&cpuInfo,
                                           &infoCount);
    if (kr != KERN_SUCCESS) {
        snap.error_code = 1;
        snprintf(snap.error_message, sizeof(snap.error_message),
                 "host_processor_info failed: 0x%x", kr);
        return snap;
    }
    
    uint32_t count = (uint32_t)processorCount;
    if (count > MAX_CORES) count = MAX_CORES;
    snap.core_count = count;
    
    if (!g_initialized || g_core_count != count) {
        detect_topology(count);
        g_initialized = 1;
    }
    snap.p_core_count = g_p_count;
    snap.e_core_count = g_e_count;
    
    if (g_has_prev && g_initialized) {
        // Compute delta utilization
        for (uint32_t i = 0; i < count; i++) {
            uint64_t prev_user = g_prev[i].cpu_ticks[CPU_STATE_USER];
            uint64_t prev_sys  = g_prev[i].cpu_ticks[CPU_STATE_SYSTEM];
            uint64_t prev_idle = g_prev[i].cpu_ticks[CPU_STATE_IDLE];
            uint64_t prev_nice = g_prev[i].cpu_ticks[CPU_STATE_NICE];
            uint64_t prev_total = prev_user + prev_sys + prev_idle + prev_nice;
            
            uint64_t cur_user = cpuInfo[i].cpu_ticks[CPU_STATE_USER];
            uint64_t cur_sys  = cpuInfo[i].cpu_ticks[CPU_STATE_SYSTEM];
            uint64_t cur_idle = cpuInfo[i].cpu_ticks[CPU_STATE_IDLE];
            uint64_t cur_nice = cpuInfo[i].cpu_ticks[CPU_STATE_NICE];
            uint64_t cur_total = cur_user + cur_sys + cur_idle + cur_nice;
            
            uint64_t delta_total = cur_total - prev_total;
            uint64_t delta_active = (cur_total - cur_idle) - (prev_total - prev_idle);
            
            snap.cores[i].logical_index = i;
            snap.cores[i].valid = 1;
            if (delta_total > 0) {
                snap.cores[i].utilization_percent = (double)delta_active / (double)delta_total * 100.0;
            }
            
            // Classify by detected topology; unknown when not resolved
            if (i < g_e_count) {
                snap.cores[i].kind = 0; // efficiency
            } else if (i < g_e_count + g_p_count) {
                snap.cores[i].kind = 1; // performance
            } else {
                snap.cores[i].kind = 2; // unknown
            }
        }
    } else {
        // First sample: mark all as waiting
        for (uint32_t i = 0; i < count; i++) {
            snap.cores[i].logical_index = i;
            snap.cores[i].valid = 0; // waiting
            if (i < g_e_count) snap.cores[i].kind = 0;
            else if (i < g_e_count + g_p_count) snap.cores[i].kind = 1;
            else snap.cores[i].kind = 2;
        }
    }
    
    // Save current as previous
    memcpy(g_prev, cpuInfo, count * sizeof(processor_cpu_load_info_data_t));
    g_has_prev = 1;
    
    vm_deallocate(mach_task_self(), (vm_address_t)cpuInfo,
                  infoCount * sizeof(processor_cpu_load_info_data_t));
    
    return snap;
}

void core_util_reset(void) {
    g_has_prev = 0;
}

CoreUtilInfo core_util_get_core(CoreUtilSnapshot *snap, uint32_t index) {
    if (!snap || index >= snap->core_count || index >= MAX_CORES) {
        CoreUtilInfo empty = {0};
        return empty;
    }
    return snap->cores[index];
}
