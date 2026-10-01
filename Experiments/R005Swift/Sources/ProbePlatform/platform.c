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
#ifdef __APPLE__
#include <dlfcn.h>
#include <pthread.h>
static pthread_once_t observer_once=PTHREAD_ONCE_INIT;
static void (*observer_begin)(void)=NULL;
static NXRAlloc (*observer_end)(void)=NULL;
static void lookup_observer(void){
 observer_begin=(void (*)(void))dlsym(RTLD_DEFAULT,"nx_observer_begin");
 observer_end=(NXRAlloc (*)(void))dlsym(RTLD_DEFAULT,"nx_observer_end");
}
#endif
void nx_alloc_begin(void){
#ifdef __APPLE__
 pthread_once(&observer_once,lookup_observer);
 if(observer_begin&&observer_end)observer_begin();
#endif
}
NXRAlloc nx_alloc_end(void){
#ifdef __APPLE__
 pthread_once(&observer_once,lookup_observer);
 if(observer_begin&&observer_end)return observer_end();
#endif
 NXRAlloc absent={0,0,0};return absent;
}
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

NXRHash nx_hash_bytes(const unsigned char *bytes,size_t count){
 NXRHash result={0,0,0,0,1};unsigned char digest[32];
 if(count>0&&!bytes)return result;
#ifdef __APPLE__
 CC_SHA256(bytes,(CC_LONG)count,digest);
#else
 unsigned digest_length=0;
 EVP_MD_CTX *ctx=EVP_MD_CTX_new();if(!ctx)return result;
 if(EVP_DigestInit_ex(ctx,EVP_sha256(),NULL)!=1||
    EVP_DigestUpdate(ctx,bytes,count)!=1||
    EVP_DigestFinal_ex(ctx,digest,&digest_length)!=1||digest_length!=32){
   EVP_MD_CTX_free(ctx);return result;
 }
 EVP_MD_CTX_free(ctx);
#endif
 uint64_t words[4]={0};for(unsigned i=0;i<32;i++)words[i/8]=(words[i/8]<<8)|digest[i];
 result.a=words[0];result.b=words[1];result.c=words[2];result.d=words[3];result.status=0;return result;
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
