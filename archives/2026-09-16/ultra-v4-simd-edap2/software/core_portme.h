#ifndef CORE_PORTME_H
#define CORE_PORTME_H

/* Ultra top_tcm_axi bare-metal port.
 * The benchmark sources remain the material version; this file supplies only
 * the target types, timer, seeds, and host-signature output path.
 */
#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif
#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif
#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif
#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif
#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

#ifndef COMPILER_VERSION
#ifdef ULTRA_XPACK_GCC
#define COMPILER_VERSION "riscv-none-elf-gcc " __VERSION__
#else
#define COMPILER_VERSION "riscv64-unknown-elf-gcc " __VERSION__
#endif
#endif
#ifndef COMPILER_FLAGS
#define ULTRA_STRINGIFY_IMPL(x) #x
#define ULTRA_STRINGIFY(x) ULTRA_STRINGIFY_IMPL(x)
#ifndef ULTRA_OPT_LEVEL
#define ULTRA_OPT_LEVEL 2
#endif
#define COMPILER_FLAGS \
    "-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany " \
    "-msmall-data-limit=0 -O" ULTRA_STRINGIFY(ULTRA_OPT_LEVEL) " " \
    "-ffreestanding -fno-builtin -fno-stack-protector -fno-pic " \
    "-fdata-sections -ffunction-sections top_tcm_axi"
#endif
#ifndef MEM_LOCATION
#define MEM_LOCATION "TCM"
#endif

typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef ee_u32         ee_ptr_int;
typedef ee_u32         ee_size_t;

#define NULL ((void *)0)
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0
#endif
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 1
#endif
#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

#ifndef EE_TICKS_PER_SEC
#define EE_TICKS_PER_SEC 100000000U
#endif

#define ULTRA_SIGNATURE_SIZE 4096U
extern volatile unsigned char ultra_signature[ULTRA_SIGNATURE_SIZE];
extern volatile unsigned int ultra_signature_pos;

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

int ee_printf(const char *fmt, ...);

#ifdef ULTRA_PERF_COUNTERS
void ultra_perf_report(void);
#endif

#endif
