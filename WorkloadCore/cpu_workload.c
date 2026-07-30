// ThermalBench - CPU workload engine (C/pthread)
// Performs sustained compute load using NEON FMA instructions.
// License: MIT
#include "cpu_workload.h"
#include <pthread.h>
#include <pthread/qos.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdatomic.h>
#include <time.h>
#include <math.h>
#include <arm_neon.h>

// ─── Globals ──────────────────────────────────────────────────────────────

static pthread_t        *g_workers = NULL;
static uint32_t          g_num_workers = 0;
static _Atomic uint32_t  g_started = 0;
static atomic_bool       g_stop_flag = false;
static atomic_bool       g_running = false;
static atomic_ullong     g_checksum = 0;
static double            g_start_time = 0.0;
static double            g_stop_time = 0.0;
static cpu_workload_config_t g_config = {0};

// ─── Worker kernel (NEON FMA) ────────────────────────────────────────────

static void *cpu_worker(void *arg) {
    uint32_t id = (uint32_t)(uintptr_t)arg;

    // ── Core-type QoS affinity ──────────────────────────────────────────
    // On Apple Silicon, QoS class is the strongest scheduling hint available
    // to user-space for steering threads toward P-cores or E-cores.
    switch (g_config.core_type) {
    case CPU_CORE_TYPE_PERFORMANCE:
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
        break;
    case CPU_CORE_TYPE_EFFICIENCY:
        pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0);
        break;
    default:
        break;  // ALL: inherit process default QoS
    }

    uint64_t local_checksum = 0;

    // Fixed-size compute buffers (cache-resident)
    float32x4_t a[16], b[16], c[16];
    for (int i = 0; i < 16; i++) {
        a[i] = vdupq_n_f32((float)(id + i + 1) * 0.618033f);
        b[i] = vdupq_n_f32((float)(id + i + 1) * 1.618034f);
        c[i] = vdupq_n_f32(0.0f);
    }

    atomic_fetch_add(&g_started, 1);

    while (!atomic_load(&g_stop_flag)) {
        // Unrolled NEON FMA loop
        for (int iter = 0; iter < 1000; iter++) {
            for (int i = 0; i < 16; i++) {
                c[i] = vfmaq_f32(
                    vfmaq_f32(
                        vfmaq_f32(c[i], a[i], b[i]),
                        b[i], c[i]
                    ),
                    a[i], vfmaq_f32(a[i], b[i], c[i])
                );
            }
            // Periodic checksum update
            if ((iter & 0xFF) == 0) {
                float32x4_t sum = vdupq_n_f32(0.0f);
                for (int i = 0; i < 16; i++) { sum = vaddq_f32(sum, c[i]); }
                float cs[4]; vst1q_f32(cs, sum);
                local_checksum += (uint64_t)(cs[0] + cs[1] + cs[2] + cs[3]);
            }
        }
    }

    // Final checksum
    float32x4_t sum = vdupq_n_f32(0.0f);
    for (int i = 0; i < 16; i++) { sum = vaddq_f32(sum, c[i]); }
    float cs[4]; vst1q_f32(cs, sum);
    local_checksum ^= (uint64_t)(cs[0] + cs[1] + cs[2] + cs[3]);
    atomic_fetch_xor(&g_checksum, local_checksum);

    return NULL;
}

// ─── Public API ───────────────────────────────────────────────────────────

uint32_t cpu_workload_logical_cpus(void) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return (n > 0) ? (uint32_t)n : 1;
}

int cpu_workload_start(cpu_workload_config_t *config) {
    if (atomic_load(&g_running)) return -1;

    g_config = *config;
    g_num_workers = config->num_threads ? config->num_threads : cpu_workload_logical_cpus();
    if (g_num_workers < 1) g_num_workers = 1;

    g_workers = (pthread_t *)calloc(g_num_workers, sizeof(pthread_t));
    if (!g_workers) return -2;

    atomic_store(&g_stop_flag, false);
    atomic_store(&g_checksum, 0);
    g_started = 0;

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    g_start_time = ts.tv_sec + ts.tv_nsec * 1e-9;

    for (uint32_t i = 0; i < g_num_workers; i++) {
        if (pthread_create(&g_workers[i], NULL, cpu_worker, (void *)(uintptr_t)i) != 0) {
            cpu_workload_stop();
            return -3;
        }
    }

    atomic_store(&g_running, true);
    return 0;
}

void cpu_workload_stop(void) {
    atomic_store(&g_stop_flag, true);
    if (g_workers) {
        for (uint32_t i = 0; i < g_num_workers; i++) {
            if (g_workers[i]) pthread_join(g_workers[i], NULL);
        }
        free(g_workers);
        g_workers = NULL;
    }
    if (atomic_load(&g_running)) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        g_stop_time = ts.tv_sec + ts.tv_nsec * 1e-9;
    }
    atomic_store(&g_running, false);
}

void cpu_workload_status(cpu_workload_status_t *out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->requested_threads = g_config.num_threads ? g_config.num_threads : cpu_workload_logical_cpus();
    out->started_threads = g_started;
    out->alive_threads = atomic_load(&g_running) ? g_started : 0;
    out->worker_start_time = g_start_time;
    out->worker_stop_time = g_stop_time;
    out->load_kernel_version = CPU_WORKLOAD_VERSION;
    out->validation_checksum = atomic_load(&g_checksum);
}

bool cpu_workload_is_running(void) {
    return atomic_load(&g_running);
}
