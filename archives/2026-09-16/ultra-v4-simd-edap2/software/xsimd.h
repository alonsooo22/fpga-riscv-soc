#ifndef ULTRA_XSIMD_H
#define ULTRA_XSIMD_H
#include <stdint.h>
#include "encoding.h"
static inline int32_t xs_s16(uint32_t x) { return (x & 32768u) ? (int32_t)(x & 65535u)-65536 : (int32_t)(x & 65535u); }
static inline uint32_t xs_extract_ref(uint32_t x,unsigned start,unsigned width) {
    return (x >> start) & (UINT32_MAX >> (32-width));
}
#ifdef XSIMD_MODEL
#define xs_extract(x,s,w) xs_extract_ref((x),(s),(w))
static inline uint32_t xs_pack(uint32_t a,uint32_t b){return (a&65535u)|(b<<16);}
static inline uint32_t xs_dot(uint32_t a,uint32_t b){
    return (uint32_t)((int64_t)xs_s16(a)*xs_s16(b)+(int64_t)xs_s16(a>>16)*xs_s16(b>>16));
}
static inline uint32_t xs_add(uint32_t a,uint32_t b){return ((a+b)&65535u)|((((a>>16)+(b>>16))&65535u)<<16);}
#else
#define xs_extract(x,s,w) __extension__ ({ \
    _Static_assert((s)>=0 && (s)<32 && (w)>=1 && (w)<=32,"extract immediate range"); \
    uint32_t _r; __asm__(".insn i " XS_OPCODE_STR ", " XS_XBEXTU_F3_STR ", %0, %1, %2" \
      : "=r"(_r) : "r"((uint32_t)(x)),"i"((((w)-1)<<5)|(s))); _r; })
#define XS_R_FUNCTION(fn,f3) static inline uint32_t fn(uint32_t a,uint32_t b){ \
 uint32_t r; __asm__(".insn r " XS_OPCODE_STR ", " f3 ", 0, %0, %1, %2" : "=r"(r):"r"(a),"r"(b));return r; }
XS_R_FUNCTION(xs_pack,XS_XPACK16_F3_STR)
XS_R_FUNCTION(xs_dot,XS_XDOT2H_F3_STR)
XS_R_FUNCTION(xs_add,XS_XADD16_F3_STR)
#endif
#endif
