// ThermalBench - CPU workload engine (C/pthread)
// License: MIT
#ifndef CPU_WORKLOAD_H
#define CPU_WORKLOAD_H

#include <stdint.h>
#include <stdbool.h>

#define CPU_WORKLOAD_VERSION 2

/// Target core type for thread scheduling.
typedef enum {
    CPU_CORE_TYPE_ALL         = 0,  // All cores (default, no QoS override)
    CPU_CORE_TYPE_PERFORMANCE = 1,  // P-cores (QoS → User Interactive)
    CPU_CORE_TYPE_EFFICIENCY  = 2,  // E-cores (QoS → Background)
} cpu_core_type_t;

typedef struct cpu_workload_config {
    uint32_t         num_threads;   // 0 = auto-detect
    bool             use_fma;       // Use NEON FMA instructions
    bool             validate;      // Compute validation checksum
    cpu_core_type_t  core_type;     // Target core type for QoS affinity
} cpu_workload_config_t;

typedef struct cpu_workload_status {
    uint32_t requested_threads;
    uint32_t started_threads;
    uint32_t alive_threads;
    double   worker_start_time;
    double   worker_stop_time;
    uint32_t load_kernel_version;
    uint64_t validation_checksum;
} cpu_workload_status_t;

// Detect number of logical CPUs
uint32_t cpu_workload_logical_cpus(void);

// Start worker threads. Returns 0 on success.
int cpu_workload_start(cpu_workload_config_t *config);

// Stop all workers. Thread-safe, may be called from any thread or signal handler.
void cpu_workload_stop(void);

// Get current status
void cpu_workload_status(cpu_workload_status_t *out);

// Returns true if workers are running
bool cpu_workload_is_running(void);

#endif
