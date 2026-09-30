/* Disposable R005 storage/kernel experiment; NOT a new production engine. */
#include "Platform/include/NXRProbe.h"
#include <stdint.h>
#include <stddef.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/utsname.h>

typedef struct { uint32_t entity, contract; uint64_t period; int64_t accrued;
                 uint64_t last_operation, invoice_sequence; } Accrual;
_Static_assert(sizeof(Accrual)==40,"unexpected accrual layout");
typedef struct {
    uint32_t *generation,*state,*entity,*policy,*contract,*airport,*origin,*destination,*event_index,*change_epoch;
    uint64_t *operation,*last_accrued,*depart,*fare,*completed;
    uint64_t *due,*sequence;
    uint32_t *event_asset,*event_generation,*next,*sort_a,*sort_b,*metadata;
    Accrual *accrual;
    uint8_t *dirty;
    uint32_t *heads,*tails;
    uint64_t *occupancy,*output;
    size_t count, event_capacity, groups, permutation_step;
    void *allocations[29]; size_t allocation_count, allocated_bytes;
    size_t allocation_calls, fail_after;
} Store;
static void *owned_calloc(Store *s,size_t count,size_t size) {
    if(size && count>SIZE_MAX/size) return NULL;
    if(s->allocation_calls++==s->fail_after) return NULL;
    void *p=calloc(count,size);
    if(!p) return NULL;
    if(s->allocation_count>=29) abort();
    s->allocations[s->allocation_count++]=p; s->allocated_bytes+=count*size;
    return p;
}
static void destroy(Store *s) {
    for(size_t i=0;i<s->allocation_count;i++) free(s->allocations[i]);
    s->allocation_count=0;
}
static size_t gcd(size_t a,size_t b) { while(b) { size_t r=a%b;a=b;b=r; } return a; }
static int create(Store *s,size_t n,size_t events,size_t fail_after) {
    memset(s,0,sizeof(*s));s->fail_after=fail_after;
    if(n<1 || n>2000000 || events<n || events>n*2) return 0;
    s->count=n;s->event_capacity=events;s->groups=(n+15)/16;
    s->permutation_step=104729; while(gcd(s->permutation_step,n)!=1) s->permutation_step+=2;
#define COLUMN(field,type,count) do { s->field=owned_calloc(s,(count),sizeof(type)); if(!s->field) { destroy(s); return 0; } } while(0)
    COLUMN(generation,uint32_t,n);COLUMN(state,uint32_t,n);COLUMN(entity,uint32_t,n);
    COLUMN(policy,uint32_t,n);COLUMN(contract,uint32_t,n);COLUMN(airport,uint32_t,n);
    COLUMN(origin,uint32_t,n);COLUMN(destination,uint32_t,n);COLUMN(event_index,uint32_t,n);COLUMN(change_epoch,uint32_t,n);
    COLUMN(operation,uint64_t,n);COLUMN(last_accrued,uint64_t,n);COLUMN(depart,uint64_t,n);COLUMN(fare,uint64_t,n);COLUMN(completed,uint64_t,n);
    COLUMN(due,uint64_t,events);COLUMN(sequence,uint64_t,events);
    COLUMN(event_asset,uint32_t,events);COLUMN(event_generation,uint32_t,events);
    COLUMN(next,uint32_t,events);COLUMN(sort_a,uint32_t,events);COLUMN(sort_b,uint32_t,events);COLUMN(metadata,uint32_t,events);
    COLUMN(accrual,Accrual,s->groups);COLUMN(dirty,uint8_t,(n+7)/8);
    COLUMN(heads,uint32_t,2048);COLUMN(tails,uint32_t,2048);COLUMN(occupancy,uint64_t,32);COLUMN(output,uint64_t,2048);
#undef COLUMN
    return 1;
}
static void initialize(Store *s) {
    for(size_t i=0;i<s->count;i++) {
        s->generation[i]=1;s->state[i]=1;s->entity[i]=(uint32_t)(i/1024);
        s->policy[i]=1;s->contract[i]=(uint32_t)(i/16);s->airport[i]=1;
        s->origin[i]=1;s->destination[i]=2;s->event_index[i]=(uint32_t)i;s->change_epoch[i]=0;
        s->operation[i]=i+1;s->last_accrued[i]=0;s->depart[i]=0;s->fare[i]=101+i%97;s->completed[i]=0;
        s->due[i]=1+i%600;s->sequence[i]=i+1;s->event_asset[i]=(uint32_t)i;
        s->event_generation[i]=1;s->next[i]=UINT32_MAX;s->sort_a[i]=0;
        s->sort_b[i]=0;s->metadata[i]=1;
    }
    memset(s->accrual,0,s->groups*sizeof(Accrual));memset(s->dirty,0,(s->count+7)/8);
}
/* This intentionally measures just row lookup + accrual + completion + dirty output.
 * It does NOT implement a timing wheel, currency posting, API capability or save. */
static int advance_kernel(Store *s,size_t first,size_t limit,int permutation,size_t *actual) {
    *actual=0;
    for(size_t j=first;j<s->count && *actual<limit;j++) {
        size_t event=permutation ? (j*s->permutation_step)%s->count : j;
        size_t i=s->event_asset[event];
        if(i>=s->count || s->generation[i]!=s->event_generation[event] || s->state[i]!=1 ||
           s->last_accrued[i]>=s->operation[i] || s->contract[i]>=s->groups || s->completed[i]==UINT64_MAX) return 0;
        Accrual *a=&s->accrual[s->contract[i]];
        if(s->fare[i]>INT64_MAX || a->accrued>INT64_MAX-(int64_t)s->fare[i]) return 0;
        a->accrued+=(int64_t)s->fare[i];s->last_accrued[i]=s->operation[i];
        s->state[i]=0;s->airport[i]=s->destination[i];s->completed[i]++;
        s->event_index[i]=UINT32_MAX;s->change_epoch[i]=1;
        s->dirty[i/8]|=(uint8_t)(1u<<(i%8));
        s->output[*actual*2]=i;s->output[*actual*2+1]=s->operation[i];
        (*actual)++;
    }
    return 1;
}
static uint64_t digest(Store *s) {
    uint64_t d=UINT64_C(1469598103934665603);
    for(size_t i=0;i<s->count;i++) {
        d=(d^s->last_accrued[i])*UINT64_C(1099511628211);
        d=(d^s->completed[i])*UINT64_C(1099511628211);
        d=(d^s->airport[i])*UINT64_C(1099511628211);
    }
    for(size_t g=0;g<s->groups;g++) d=(d^(uint64_t)s->accrual[g].accrued)*UINT64_C(1099511628211);
    return d;
}
static int test(void) {
    Store s; if(create(&s,0,0,SIZE_MAX)) return 0;
    if(create(&s,2000001,2000001,SIZE_MAX)) return 0;
    for(size_t f=0;f<29;f++) if(create(&s,64,64,f) || s.allocation_count) return 0;
    if(!create(&s,64,128,SIZE_MAX)) return 0;
    initialize(&s);size_t actual=0;
    s.event_generation[0]=2;
    if(advance_kernel(&s,0,1,0,&actual) || actual || s.accrual[0].accrued) return 0;
    s.event_generation[0]=1;
    if(!advance_kernel(&s,0,1,0,&actual) || actual!=1) return 0;
    if(advance_kernel(&s,0,1,0,&actual) || actual) return 0;
    uint64_t checksums[4];size_t budgets[]={1,7,31,1024};
    for(size_t k=0;k<4;k++) {
        initialize(&s);
        for(size_t i=0;i<s.count;) { if(!advance_kernel(&s,i,budgets[k],1,&actual) || !actual) return 0; i+=actual; }
        checksums[k]=digest(&s);
    }
    for(size_t k=1;k<4;k++) if(checksums[k]!=checksums[0]) return 0;
    destroy(&s);puts("PASS disposable layout tests: invalid capacity, 29 allocation failures, stale/duplicate, 1/7/31/1024 partitions");return 1;
}
static void delta_json(const char *name,uint64_t before,uint64_t after,NXRUsage a,NXRUsage b) {
    printf("\"%s\":",name);
    if(a.status==0 && b.status==0 && before>0 && after>=before)
        printf("{\"status\":\"ok\",\"value\":%"PRIu64"}",after-before);
    else if(a.status==2 || b.status==2) printf("{\"status\":\"readFailure\",\"value\":null,\"errnoBefore\":%d,\"errnoAfter\":%d}",a.error,b.error);
    else if(after<before) printf("{\"status\":\"decreased\",\"value\":null}");
    else printf("{\"status\":\"unsupported\",\"value\":null,\"reason\":\"unavailable-or-zero-policy-not-hardware-proof\"}");
}
int main(int argc,char **argv) {
    if(argc==2 && !strcmp(argv[1],"--selftest")) return test()?0:1;
    if(argc!=4) { fprintf(stderr,"usage: layout_probe assets events-per-asset batch-size\n");return 2; }
    char *e;errno=0;unsigned long n=strtoul(argv[1],&e,10);if(errno || *e || n<1 || n>2000000) return 2;
    unsigned long density=strtoul(argv[2],&e,10);if(*e || density<1 || density>2) return 2;
    unsigned long budget=strtoul(argv[3],&e,10);if(*e || budget<1 || budget>1024) return 2;
    Store s;uint64_t begin=nxr_now_ns();if(!create(&s,n,n*density,SIZE_MAX)) return 3;
    uint64_t allocation_ns=nxr_now_ns()-begin;
    size_t predicted=n*80+n*density*40+((n+15)/16)*40+(n+7)/8+33024;
    if(s.allocated_bytes!=predicted || s.allocation_count!=29) return 4;
    struct utsname os;if(uname(&os)!=0) return 5;
    printf("{\"schema\":\"NXR-R005-LAYOUT-PROBE-1\",\"os\":\"%s\",\"architecture\":\"%s\",\"assets\":%lu,\"eventCapacity\":%lu,\"budget\":%lu,",os.sysname,os.machine,n,n*density,budget);
    printf("\"assetColumnsBytes\":%lu,\"eventColumnsBytes\":%lu,\"accrualBytes\":%zu,\"dirtyBytes\":%lu,\"sharedBytes\":33024,\"ownedAllocatedBytes\":%zu,\"ownedAllocations\":%zu,\"bytesPerAsset\":%.6f,\"setupAllocationNS\":%"PRIu64",\"runs\":[",n*80,n*density*40,s.groups*40,(n+7)/8,s.allocated_bytes,s.allocation_count,(double)s.allocated_bytes/n,allocation_ns);
    uint64_t checksums[2];
    for(int mode=0;mode<2;mode++) {
        uint64_t init=nxr_now_ns();initialize(&s);init=nxr_now_ns()-init;
        NXRUsage before=nxr_usage();uint64_t start=nxr_now_ns();size_t calls=0,processed=0,max_alloc=0,allocated=0;
        while(processed<n) {
            size_t old=s.allocation_calls,actual=0;
            if(!advance_kernel(&s,processed,budget,mode,&actual) || !actual) return 6;
            size_t allocations=s.allocation_calls-old;
            if(allocations>max_alloc) { max_alloc=allocations; }
            allocated+=allocations;processed+=actual;calls++;
        }
        uint64_t wall=nxr_now_ns()-start;NXRUsage after=nxr_usage();checksums[mode]=digest(&s);
        int64_t income=0;for(size_t g=0;g<s.groups;g++) income+=s.accrual[g].accrued;
        int64_t expected=0;for(size_t i=0;i<n;i++) expected+=(int64_t)(101+i%97);
        if(income!=expected || allocated) return 7;
        if(mode) printf(",");
        printf("{\"order\":\"%s\",\"initializationNS\":%"PRIu64",\"hostWallNS\":%"PRIu64",\"processed\":%zu,\"advanceCalls\":%zu,\"ownedAllocationCallsInEvents\":%zu,\"maxOwnedAllocationsPerAdvance\":%zu,\"checksum\":\"%016"PRIx64"\",",mode?"permuted":"sequential",init,wall,processed,calls,allocated,max_alloc,checksums[mode]);
        delta_json("instructions",before.instructions,after.instructions,before,after);printf(",");
        delta_json("cycles",before.cycles,after.cycles,before,after);printf(",");
        delta_json("runnableRaw",before.runnable_raw,after.runnable_raw,before,after);printf("}");
    }
    if(checksums[0]!=checksums[1]) return 8;
    size_t bytes=s.allocated_bytes;begin=nxr_now_ns();destroy(&s);uint64_t release=nxr_now_ns()-begin;
    printf("],\"releaseNS\":%"PRIu64",\"snapshotBytes\":null,\"columnPayloadUpperBoundBytes\":%zu,\"limits\":[\"only storage/update kernel, no scheduler implementation or durable finance\",\"owned allocator counts, not all process/runtime allocations\",\"logical requested bytes, not phys_footprint\",\"host timing observed but never a CI threshold\",\"not iPhone/full-feature acceptance\"]}\n",release,bytes);
    return 0;
}
