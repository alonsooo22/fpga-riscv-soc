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
static inline ee_u32 ultra_read_minstret(void)
{
    ee_u32 value;
    __asm__ volatile ("csrr %0, minstret" : "=r"(value));
    return value;
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
static CORETIMETYPE start_instret_val;
static CORETIMETYPE stop_instret_val;
#endif

void start_time(void)
{
#ifdef ULTRA_PERF_COUNTERS
    /* Read retired instructions before the cycle timestamp so the added
     * diagnostic read is outside the CoreMark cycle interval. */
    start_instret_val = ultra_read_minstret();
#endif
    GETMYTIME(&start_time_val);
}

void stop_time(void)
{
    GETMYTIME(&stop_time_val);
#ifdef ULTRA_PERF_COUNTERS
    /* The cycle timestamp is taken first, keeping this diagnostic read out of
     * the CoreMark cycle interval. */
    stop_instret_val = ultra_read_minstret();
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
    ee_u32 retired = (ee_u32)MYTIMEDIFF(stop_instret_val, start_instret_val);

    ee_printf("cycle_start     : %lu\n", (long unsigned)start_time_val);
    ee_printf("cycle_end       : %lu\n", (long unsigned)stop_time_val);
    ee_printf("instret_start   : %lu\n", (long unsigned)start_instret_val);
    ee_printf("instret_end     : %lu\n", (long unsigned)stop_instret_val);
    ee_printf("cycles          : %lu\n", (long unsigned)cycles);
    ee_printf("instructions retired: %lu\n", (long unsigned)retired);
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
