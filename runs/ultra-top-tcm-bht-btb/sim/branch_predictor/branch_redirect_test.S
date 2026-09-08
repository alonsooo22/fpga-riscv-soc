    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
    .type _start, @function

_start:
    la      sp, __stack_top
    la      t0, trap_handler
    csrw    mtvec, t0
    li      s1, 0
    li      s2, 0
    li      s3, 0

    # BEQ taken, BNE not-taken, BLT not-taken, BGE taken.
    li      t0, 1
    li      t1, 1
    beq     t0, t1, 1f
    j       fail
1:
    bne     t0, t1, fail
    blt     t0, t1, fail
    bge     t0, t1, 2f
    j       fail

2:
    # BLTU taken, BGEU not-taken, BNE taken, BEQ not-taken.
    li      t1, 2
    bltu    t0, t1, 3f
    j       fail
3:
    bgeu    t0, t1, fail
    bne     t0, t1, 4f
    j       fail
4:
    beq     t0, t1, fail
    li      t0, 0x01000042       # checkpoint: all conditional branch forms
    csrw    dscratch, t0

    # Execute a direct JAL, then an indirect call and RET.
    jal     t3, jal_target
    j       fail
jal_return:
    la      t0, call_target
    jalr    ra, 0(t0)
    j       call_return
call_return:
    li      t0, 0x0100004a       # checkpoint: JAL/JALR/RET
    csrw    dscratch, t0
    # FENCE.I must invalidate predictor valid state, without changing code.
    fence.i

    # A conditional branch after FENCE.I exercises the post-invalidation path.
    beq     zero, zero, 5f
    j       fail
5:
    # Illegal instruction is handled synchronously and skipped by mepc += 4.
    .word   0xffffffff
after_illegal:
    li      t0, 0x01000045       # checkpoint: illegal instruction trap
    csrw    dscratch, t0

    # Software interrupt: only trap/CSR control redirects, never BTB-trains.
    li      t0, 8
    csrw    mie, t0
    csrr    t1, mstatus
    ori     t1, t1, 8
    csrw    mstatus, t1
    csrw    mip, t0
    li      t0, 0x01000049       # checkpoint: software interrupt trap
    csrw    dscratch, t0

    # Check both trap handlers completed, then publish a small signature.
    li      t0, 1
    bne     s1, t0, fail
    bne     s2, t0, fail
    la      t0, __signature_start
    sw      s1, 0(t0)
    sw      s2, 4(t0)
    li      t1, 0x01000050       # SIM_CTRL_PUTC | 'P'
    csrw    dscratch, t1
    li      t1, 0x0100000a       # newline for an unambiguous PASS marker
    csrw    dscratch, t1
    csrw    dscratch, zero       # SIM_CTRL_EXIT

fail:
    li      t0, 0x01000046       # SIM_CTRL_PUTC | 'F'
    csrw    dscratch, t0
    csrw    dscratch, zero       # SIM_CTRL_EXIT

jal_target:
    addi    s3, s3, 1
    jal     zero, jal_return

call_target:
    addi    s3, s3, 1
    ret

    .align  2
trap_handler:
    csrr    t0, mcause
    li      t1, 2
    beq     t0, t1, handle_illegal
    li      t1, 0x80000003
    beq     t0, t1, handle_software_irq
    j       fail

handle_illegal:
    addi    s1, s1, 1
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret

handle_software_irq:
    addi    s2, s2, 1
    csrw    mip, zero
    mret

    .section .signature, "aw", @progbits
    .align  2
    .globl  __signature_start
__signature_start:
    .word   0
    .word   0
    .globl  __signature_end
__signature_end:
