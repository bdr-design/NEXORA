#ifndef NXR_SWIFT_PLATFORM_H
#define NXR_SWIFT_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
typedef struct { uint64_t bytes; int status; int error; } NXRFootprint;
typedef struct { uint64_t calls, bytes; int available; } NXRAlloc;
typedef struct { uint64_t a,b,c,d; int status; } NXRHash;
uint64_t nx_now(void);
NXRFootprint nx_footprint(void);
void nx_alloc_begin(void);
NXRAlloc nx_alloc_end(void);
uint64_t nx_alloc_calibrate(void);
uint32_t nx_crc(uint32_t crc, const unsigned char *data, size_t count);
NXRHash nx_hash_file(const char *path);
int nx_sync_dir(const char *path);
void nx_kill_point(const char *name);
int nx_replace_file(const char *source, const char *destination);
int nx_open_exclusive(const char *path);
int nx_open_append(const char *path);
#endif
