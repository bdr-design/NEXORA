// Measurement/I/O boundary only. No simulation state is stored through C pointers.
// Apple allocator interposition is separately calibrated with live Swift arrays.
#include "ProbePlatform.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#ifdef __APPLE__
#include <libproc.h>
#include <sys/resource.h>
#include <malloc/malloc.h>
#include <CommonCrypto/CommonDigest.h>
#else
#include <openssl/evp.h>
#endif
uint64_t nx_now(void) {
    struct timespec t={0,0};
#ifdef __APPLE__
    int rc=clock_gettime(CLOCK_UPTIME_RAW,&t);
#else
    int rc=clock_gettime(CLOCK_MONOTONIC,&t);
#endif
    if(rc) abort();
    return (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec;
}
NXRFootprint nx_footprint(void) {
    NXRFootprint out={0,1,0};
#ifdef __APPLE__
    struct rusage_info_v4 r={0}; errno=0;
    if(proc_pid_rusage(getpid(),RUSAGE_INFO_V4,(rusage_info_t *)&r)==0) {out.bytes=r.ri_phys_footprint;out.status=0;}
    else {out.status=2;out.error=errno;}
#endif
    return out;
}
static _Thread_local unsigned measuring=0;
#ifdef __APPLE__
static _Thread_local unsigned depth=0;
#endif
static _Thread_local uint64_t calls=0,requested=0;
void nx_alloc_begin(void){ calls=0;requested=0;measuring=1; }
NXRAlloc nx_alloc_end(void){ measuring=0; NXRAlloc r={calls,requested,0};
#ifdef __APPLE__
    r.available=1;
#endif
    return r;
}
#ifdef __APPLE__
// No polling/net-in-use proxy: count actual allocation ENTRY calls on this thread.
// Recursive entry into another intercepted function is counted once.
static void before(size_t n){if(measuring && depth==0){calls++; requested+=n;} depth++;}
static void after(void){depth--;}
static void *p_malloc(size_t n){before(n);void *p=malloc(n);after();return p;}
static void *p_calloc(size_t n,size_t s){before(n*s);void *p=calloc(n,s);after();return p;}
static void *p_realloc(void *p,size_t n){before(n);void *q=realloc(p,n);after();return q;}
static void *p_valloc(size_t n){before(n);void *p=valloc(n);after();return p;}
static int p_posix(void **p,size_t a,size_t n){before(n);int r=posix_memalign(p,a,n);after();return r;}
static void *p_aligned(size_t a,size_t n){before(n);void *p=aligned_alloc(a,n);after();return p;}
static void *p_zmalloc(malloc_zone_t *z,size_t n){before(n);void *p=malloc_zone_malloc(z,n);after();return p;}
static void *p_zcalloc(malloc_zone_t *z,size_t n,size_t s){before(n*s);void *p=malloc_zone_calloc(z,n,s);after();return p;}
static void *p_zrealloc(malloc_zone_t *z,void *p,size_t n){before(n);void *q=malloc_zone_realloc(z,p,n);after();return q;}
static void *p_zmemalign(malloc_zone_t *z,size_t a,size_t n){before(n);void *p=malloc_zone_memalign(z,a,n);after();return p;}
#define PAIR(replacement,original) { (const void *)(replacement), (const void *)(original) }
__attribute__((used,section("__DATA,__interpose"))) static const struct {const void *replacement,*original;} hooks[]={
 PAIR(p_malloc,malloc),PAIR(p_calloc,calloc),PAIR(p_realloc,realloc),PAIR(p_valloc,valloc),
 PAIR(p_posix,posix_memalign),PAIR(p_aligned,aligned_alloc),PAIR(p_zmalloc,malloc_zone_malloc),
 PAIR(p_zcalloc,malloc_zone_calloc),PAIR(p_zrealloc,malloc_zone_realloc),PAIR(p_zmemalign,malloc_zone_memalign)
};
#endif
// Called through a volatile pointer to forbid folding allocation away.
uint64_t nx_alloc_calibrate(void) {
    void *(*volatile allocate)(size_t)=malloc;
    void (*volatile release)(void *)=free;
    nx_alloc_begin();
    unsigned char *p=allocate(8193); if(!p) abort(); p[0]=1;p[8192]=3;
    uint64_t value=p[0]+p[8192];release(p);
    NXRAlloc r=nx_alloc_end();return value==4?r.calls:0;
}

uint32_t nx_crc(uint32_t crc,const unsigned char *p,size_t n){
 crc=~crc;for(size_t i=0;i<n;i++){crc^=p[i];for(unsigned b=0;b<8;b++)crc=(crc>>1)^(0xedb88320U & (0U-(crc&1U)));}return ~crc;
}
NXRHash nx_hash_file(const char *path){
 NXRHash result={0,0,0,0,1};FILE *f=fopen(path,"rb");if(!f)return result;
 unsigned char block[65536],digest[32]; size_t n;
#ifdef __APPLE__
 CC_SHA256_CTX c;CC_SHA256_Init(&c);
 while((n=fread(block,1,sizeof(block),f))>0)CC_SHA256_Update(&c,block,(CC_LONG)n);
 CC_SHA256_Final(digest,&c);
#else
 EVP_MD_CTX *c=EVP_MD_CTX_new(); if(!c){fclose(f);return result;}
 EVP_DigestInit_ex(c,EVP_sha256(),NULL);
 while((n=fread(block,1,sizeof(block),f))>0)EVP_DigestUpdate(c,block,n);
 unsigned digest_length=0;EVP_DigestFinal_ex(c,digest,&digest_length);EVP_MD_CTX_free(c);if(digest_length!=32){fclose(f);return result;}
#endif
 int bad=ferror(f);fclose(f);if(bad)return result;
 uint64_t words[4]={0};for(unsigned i=0;i<32;i++)words[i/8]=(words[i/8]<<8)|digest[i];
 result.a=words[0];result.b=words[1];result.c=words[2];result.d=words[3];result.status=0;return result;
}
int nx_sync_dir(const char *path){int fd=open(path,O_RDONLY);if(fd<0)return errno;int rc=fsync(fd);int e=rc?errno:0;close(fd);return e;}
void nx_kill_point(const char *name){const char *p=getenv("NXR_KILL_AT");if(p&&strcmp(p,name)==0){
 const char *prefix="KILL_POINT:";write(STDOUT_FILENO,prefix,strlen(prefix));write(STDOUT_FILENO,name,strlen(name));write(STDOUT_FILENO,"\n",1);kill(getpid(),SIGSTOP);
}}
int nx_replace_file(const char *source,const char *destination){return rename(source,destination)==0?0:errno;}

int nx_open_exclusive(const char *path){int fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);return fd<0?-errno:fd;}
int nx_open_append(const char *path){int fd=open(path,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0600);return fd<0?-errno:fd;}
