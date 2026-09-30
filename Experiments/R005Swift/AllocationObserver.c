// macOS measurement-only dylib: isolated image prevents dyld self-image exclusions.
#include "ProbePlatform.h"
#include <stdlib.h>
#include <malloc/malloc.h>
static _Thread_local unsigned measuring=0,depth=0;
static _Thread_local uint64_t calls=0,requested=0;
void nx_observer_begin(void){calls=0;requested=0;measuring=1;}
NXRAlloc nx_observer_end(void){measuring=0;NXRAlloc r={calls,requested,1};return r;}
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
