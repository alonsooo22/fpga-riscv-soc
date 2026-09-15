#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#elif PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#else
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* The Ultra RTL exposes its cycle counter at CSR 0xc00 (the standard `cycle`
 * alias). Its standalone ISA simulator does not model this CSR, so the
 * host-only reference run must use a separate compatibility mode. */
static inline ee_u32 ultra_read_mcycle(void)
{
    ee_u32 value;
    __asm__ volatile ("csrr %0, cycle" : "=r"(value));
    return value;
}

#ifdef ULTRA_PERF_COUNTERS
/* The RTL exposes these read-only diagnostic aliases at the standard HPM
 * counter addresses. Keep all reads outside the timed CoreMark interval. */
#define ULTRA_READ_CSR(_name)                         \
    static inline ee_u32 ultra_read_##_name(void)     \
    {                                                  \
        ee_u32 value;                                  \
        __asm__ volatile ("csrr %0, " #_name           \
                          : "=r"(value));             \
        return value;                                  \
    }

ULTRA_READ_CSR(minstret)
ULTRA_READ_CSR(mhpmcounter3)
ULTRA_READ_CSR(mhpmcounter4)
ULTRA_READ_CSR(mhpmcounter5)
ULTRA_READ_CSR(mhpmcounter6)
ULTRA_READ_CSR(mhpmcounter7)
ULTRA_READ_CSR(mhpmcounter8)
ULTRA_READ_CSR(mhpmcounter9)
ULTRA_READ_CSR(mhpmcounter10)
ULTRA_READ_CSR(mhpmcounter11)

#undef ULTRA_READ_CSR

typedef struct
{
    ee_u32 instret;
    ee_u32 scoreboard;
    ee_u32 lsu;
    ee_u32 pipe;
    ee_u32 div;
    ee_u32 csr;
    ee_u32 branch_request;
    ee_u32 branch_redirect;
    ee_u32 branch_flush;
    ee_u32 fetch_starve;
} ultra_perf_snapshot;

static inline void ultra_read_perf_snapshot(ultra_perf_snapshot *snapshot)
{
    snapshot->instret          = ultra_read_minstret();
    snapshot->scoreboard      = ultra_read_mhpmcounter3();
    snapshot->lsu             = ultra_read_mhpmcounter4();
    snapshot->pipe            = ultra_read_mhpmcounter5();
    snapshot->div             = ultra_read_mhpmcounter6();
    snapshot->csr             = ultra_read_mhpmcounter7();
    snapshot->branch_request  = ultra_read_mhpmcounter8();
    snapshot->branch_redirect = ultra_read_mhpmcounter9();
    snapshot->branch_flush    = ultra_read_mhpmcounter10();
    snapshot->fetch_starve    = ultra_read_mhpmcounter11();
}
#endif

CORETIMETYPE barebones_clock(void)
{
    return (CORETIMETYPE)ultra_read_mcycle();
}

#define GETMYTIME(_t)              (*(_t) = barebones_clock())
#define MYTIMEDIFF(fin, ini)       ((fin) - (ini))
#define TIMER_RES_DIVIDER          1
#define SAMPLE_TIME_IMPLEMENTATION 1

static CORETIMETYPE start_time_val;
static CORETIMETYPE stop_time_val;

#ifdef ULTRA_PERF_COUNTERS
static ultra_perf_snapshot start_perf_val;
static ultra_perf_snapshot stop_perf_val;
#endif

void start_time(void)
{
#ifdef ULTRA_PERF_COUNTERS
    /* All diagnostic reads precede the cycle timestamp. */
    ultra_read_perf_snapshot(&start_perf_val);
#endif
    GETMYTIME(&start_time_val);
}

void stop_time(void)
{
    GETMYTIME(&stop_time_val);
#ifdef ULTRA_PERF_COUNTERS
    /* The cycle timestamp is taken first; all diagnostic reads follow it. */
    ultra_read_perf_snapshot(&stop_perf_val);
#endif
}

CORE_TICKS get_time(void)
{
    return (CORE_TICKS)MYTIMEDIFF(stop_time_val, start_time_val);
}

#ifdef ULTRA_PERF_COUNTERS
void ultra_perf_report(void)
{
    ee_u32 cycles = (ee_u32)MYTIMEDIFF(stop_time_val, start_time_val);
    ee_u32 retired = stop_perf_val.instret - start_perf_val.instret;

    ee_printf("cycle_start     : %lu\n", (long unsigned)start_time_val);
    ee_printf("cycle_end       : %lu\n", (long unsigned)stop_time_val);
    ee_printf("instret_start   : %lu\n", (long unsigned)start_perf_val.instret);
    ee_printf("instret_end     : %lu\n", (long unsigned)stop_perf_val.instret);
    ee_printf("cycles          : %lu\n", (long unsigned)cycles);
    ee_printf("instructions retired: %lu\n", (long unsigned)retired);
    ee_printf("scoreboard_stall_cycles : %lu\n",
              (long unsigned)(stop_perf_val.scoreboard - start_perf_val.scoreboard));
    ee_printf("lsu_stall_cycles        : %lu\n",
              (long unsigned)(stop_perf_val.lsu - start_perf_val.lsu));
    ee_printf("pipe_stall_cycles       : %lu\n",
              (long unsigned)(stop_perf_val.pipe - start_perf_val.pipe));
    ee_printf("div_wait_cycles         : %lu\n",
              (long unsigned)(stop_perf_val.div - start_perf_val.div));
    ee_printf("csr_wait_cycles         : %lu\n",
              (long unsigned)(stop_perf_val.csr - start_perf_val.csr));
    ee_printf("branch_request_events   : %lu\n",
              (long unsigned)(stop_perf_val.branch_request - start_perf_val.branch_request));
    ee_printf("branch_redirect_cycles  : %lu\n",
              (long unsigned)(stop_perf_val.branch_redirect - start_perf_val.branch_redirect));
    ee_printf("branch_flush_cycles     : %lu\n",
              (long unsigned)(stop_perf_val.branch_flush - start_perf_val.branch_flush));
    ee_printf("fetch_starve_cycles     : %lu\n",
              (long unsigned)(stop_perf_val.fetch_starve - start_perf_val.fetch_starve));
}
#endif

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)(((ee_u32)ticks) / (ee_u32)EE_TICKS_PER_SEC);
}

ee_u32 default_num_contexts = 1;

/* Captured by isa_sim's -p/-j/-k post-run dump. */
volatile unsigned char ultra_signature[ULTRA_SIGNATURE_SIZE]
    __attribute__((section(".signature"), aligned(4), used)) = {0};
volatile unsigned int ultra_signature_pos;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! pointer type is not 32-bit\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! ee_u32 is not 32-bit\n");
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
}

/* These are unused for MEM_STATIC, but keep the port complete. */
void *portable_malloc(ee_size_t size)
{
    (void)size;
    return NULL;
}

void portable_free(void *p)
{
    (void)p;
}
