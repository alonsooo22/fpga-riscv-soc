    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
    .type _start, @function

// External interrupt closure image.
// The host drives only intr_in.  The masked pulse is withdrawn by the host,
// then software clears the latched mip bit with the source already low.  The
// enabled pulse is withdrawn when the first trap-handler instruction commits.
_start:
    la      sp, __stack_top
    la      s2, __signature_start
    la      t0, trap_handler
    csrw    mtvec, t0
    li      s0, 0                  // masked-handler count
    li      s1, 0                  // external-handler count

    // The first host pulse occurs while both MIE and MEIE are disabled.
    .globl  masked_trigger
masked_trigger:
    nop
    .globl  masked_clear
masked_clear:
    nop

    // Withdrawn external levels do not erase a latched mip bit in this CSR
    // implementation; perform the required software cleanup after withdrawal.
    li      t0, 2048               // 1 << MEIP
    csrrc   zero, mip, t0
    bne     s0, zero, fail         // masked source must not enter handler

    // Enable machine external interrupts.
    csrw    mie, t0
    csrr    t1, mstatus
    ori     t1, t1, 8              // SR_MIE
    csrw    mstatus, t1

    // The second host pulse starts before this one-time taken branch.  The
    // cold predictor supplies not-taken, so the branch itself also provides a
    // real predicted-NT/actual-T redirect close to interrupt acceptance.
    li      t0, 1
    .globl  enabled_trigger
enabled_trigger:
    nop
branch_interleave:
    beq     t0, t0, branch_taken
    j       fail
branch_taken:
    nop

    // Return from the handler must eventually reach this normal path.
    .globl  after_irq
after_irq:
    li      t0, 1
    bne     s1, t0, fail
    bne     s0, zero, fail
    sw      s0, 0(s2)
    sw      s1, 4(s2)
    li      t0, 0x01000050         // SIM_CTRL_PUTC | 'P'
    csrw    dscratch, t0
    li      t0, 0x0100000a
    csrw    dscratch, t0
done:
    j       done                    // host stops with a bounded cycle count

fail:
    li      s0, 0xdead              // host signature check converts this to FAIL
fail_loop:
    j       fail_loop

    .align  2
    .globl  trap_handler
trap_handler:
    csrr    t0, mcause
    sw      t0, 8(s2)
    li      t1, 0x8000000b         // machine external interrupt
    bne     t0, t1, fail
    csrr    t0, mepc
    sw      t0, 12(s2)
    addi    s1, s1, 1

    // Source is already low here. Clear the pending bit before mret; a CSR
    // write alone is not treated as withdrawal of the external level.
    li      t1, 2048
    csrrc   zero, mip, t1
    mret

    .section .signature, "aw", @progbits
    .align  2
    .globl  __signature_start
__signature_start:
    .word   0                      // masked handler count
    .word   0                      // enabled external handler count
    .word   0                      // observed mcause
    .word   0                      // observed mepc
    .globl  __signature_end
__signature_end:
