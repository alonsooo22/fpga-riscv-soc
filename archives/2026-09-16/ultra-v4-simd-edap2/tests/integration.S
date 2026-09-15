.option norvc
.section .text.init
.global _start
_start:
 la sp,__stack_top
 la t0,trap
 csrw mtvec,t0
 li s10,0
 li s11,0
 li t0,0x12348000
 li t1,0x5678ffff
 .insn r 11,1,0,t0,t0,t1
 li t2,0xffff8000
 bne t0,t2,fail
 .insn r 11,2,0,t0,t0,t0
 li t2,0x40000001
 bne t0,t2,fail
 .insn r 11,2,0,x0,t0,t0
 bnez zero,fail
 li t0,0xffffffff
 li t1,0x00010001
 .insn r 11,3,0,t0,t0,t1
 bnez t0,fail
 li t0,0x87654321
 .insn i 11,0,t0,t0,0x3e0
 li t2,0x87654321
 bne t0,t2,fail
 .insn i 11,0,t0,t0,0x0c5
 li t2,0x19
 bne t0,t2,fail
 // Back-to-back load, PACK, DOT and scalar MUL/ADD: real pipeline hazards.
 la s0,inputs
 lw t0,0(s0)
 lw t1,4(s0)
 .insn r 11,2,0,t2,t0,t1
 li t3,23
 bne t2,t3,fail
 mul t2,t2,t3
 li t3,529
 bne t2,t3,fail
 .insn r 11,1,0,t1,t0,t1
 li t3,0x00040002
 bne t1,t3,fail
 .insn r 11,2,0,t2,t1,t1
 addi t2,t2,1
 li t3,21
 bne t2,t3,fail
 // Illegal reserved encodings must trap even with every extension enabled.
 .word 0x4000000b
 .word 0x0200200b
 li t0,2
 bne s10,t0,fail
 bnez s11,fail
 la t0,signature
 li t1,0x50415353
 sw t1,0(t0)
 sw s10,4(t0)
 j done
fail:
 la t0,signature
 li t1,0x4641494c
 sw t1,0(t0)
 sw s10,4(t0)
done:
 j done
.balign 4
trap:
 csrr t4,mcause
 li t5,2
 beq t4,t5,1f
 addi s11,s11,1
1: addi s10,s10,1
 csrr t4,mepc
 addi t4,t4,4
 csrw mepc,t4
 mret
.section .data
.balign 4
inputs: .word 0x00030002,0x00050004
.section .signature,"aw"
.global signature
signature: .space 32
