#include "NXRProbe.h"
#include <errno.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libproc.h>
#include <sys/resource.h>
#endif
uint64_t nxr_now_ns(void) {
    struct timespec ts = {0,0};
#ifdef __APPLE__
    const clockid_t clock = CLOCK_UPTIME_RAW;
#else
    const clockid_t clock = CLOCK_MONOTONIC;
#endif
    if (clock_gettime(clock, &ts) != 0) return UINT64_MAX;
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + (uint64_t)ts.tv_nsec;
}
NXRUsage nxr_usage(void) {
    NXRUsage result = {0};
    result.begin_ns = nxr_now_ns();
#ifdef __APPLE__
    struct rusage_info_v4 info = {0};
    errno = 0;
    int rc = proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&info);
    result.status = rc == 0 ? 0 : 2;
    result.error = rc == 0 ? 0 : errno;
    if (rc == 0) {
        result.instructions = info.ri_instructions;
        result.cycles = info.ri_cycles;
        result.runnable_raw = info.ri_runnable_time;
    }
#else
    result.status = 1;
#endif
    result.end_ns = nxr_now_ns();
    return result;
}
