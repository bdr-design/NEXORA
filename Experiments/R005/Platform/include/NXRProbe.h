#ifndef NXR_PROBE_H
#define NXR_PROBE_H
#include <stdint.h>
typedef struct {
    uint64_t begin_ns, end_ns, instructions, cycles, runnable_raw;
    int32_t status, error; /* 0=call succeeded, 1=unsupported OS, 2=syscall failed */
} NXRUsage;
uint64_t nxr_now_ns(void);
NXRUsage nxr_usage(void);
#endif
