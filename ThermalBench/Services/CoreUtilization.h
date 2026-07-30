// Per-core CPU utilization collector
#pragma once
#include <stdint.h>

#define MAX_CORES 20

typedef struct {
    uint32_t logical_index;
    uint32_t kind;               // 0=efficiency, 1=performance, 2=unknown
    double utilization_percent;
    uint32_t valid;
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

CoreUtilSnapshot core_util_snapshot(void);
void core_util_reset(void);
CoreUtilInfo core_util_get_core(CoreUtilSnapshot *snap, uint32_t index);
