    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
    .type _start, @function

// Wrong-path side-effect closure image.
//
// The first four branches are cold: predicted not-taken, actually taken.
// Their sequential instruction is the side effect under test.  The next
// four branches are each executed twice: the first iteration trains a
// taken BTB/BHT entry, and the second is actually not-taken.  The target's
// first instruction is then the side effect under test for a predicted-taken
// redirect.  The first target execution is an intentional positive control.

_start:
    la      sp, __stack_top
    la      s2, __signature_start
    la      s3, nt_wrong_tcm
    la      s4, nt_pos_tcm
    la      s5, pt_tcm
    li      s6, 0x10000000          // pred-NT/actual-T MMIO
    li      s7, 0x10000004          // trained-pred-T/actual-NT MMIO
    li      t0, 0x00003000
    csrw    mtvec, t0

    // -------------------------------------------------------------
    // Predicted not-taken, actually taken: wrong path is fall-through.
    // -------------------------------------------------------------
    li      s0, 0
    li      t0, 0

    .align 6
nt_reg_branch:
    beq     t0, t0, nt_reg_target
    addi    s0, s0, 1               // wrong-path register write
nt_reg_target:
    addi    s0, s0, 2               // correct-path positive result = 2

    .align 6
    li      t2, 0xdead1001
nt_tcm_branch:
    beq     t0, t0, nt_tcm_target
    sw      t2, 0(s3)               // wrong-path TCM store
nt_tcm_target:
    li      t2, 0x51aa0001
    sw      t2, 0(s4)               // correct-path positive store

    .align 6
    li      t2, 0xdead2001
nt_csr_branch:
    beq     t0, t0, nt_csr_target
    csrw    mscratch, t2            // wrong-path legal CSR write
nt_csr_target:
    li      t2, 0x00002220
    csrw    mtvec, t2               // correct-path legal CSR write

    .align 6
    li      t2, 0xdead3001
nt_mmio_branch:
    beq     t0, t0, nt_mmio_target
    sw      t2, 0(s6)               // wrong-path test-MMIO write
nt_mmio_target:
    li      t2, 0x11110001
    sw      t2, 0(s6)               // correct-path MMIO positive control

    // Publish the first scenario before the second scenario changes CSR
    // state.  These values also make the non-MMIO checks self-contained.
    sw      s0, 0(s2)
    lw      t0, 0(s3)
    sw      t0, 4(s2)
    lw      t0, 0(s4)
    sw      t0, 8(s2)
    csrr    t0, mscratch
    sw      t0, 12(s2)
    csrr    t0, mtvec
    sw      t0, 16(s2)

    // -------------------------------------------------------------
    // Trained predicted-taken, actually not-taken.  Each target's first
    // store/write is a positive control on iteration one and would change
    // the result or MMIO count on iteration two if it were not squashed.
    // -------------------------------------------------------------
    .align 10
    li      s0, 0
    li      t0, 0

    .align 6
pt_reg_branch:
    beq     t0, zero, pt_reg_target
    jal     zero, pt_reg_done
pt_reg_target:
    addi    s0, s0, 1               // positive first target; wrong second target
    li      t0, 1
    jal     zero, pt_reg_branch
pt_reg_done:

    li      t0, 0
    li      t2, 0x5a550001
    .align 6
pt_tcm_branch:
    beq     t0, zero, pt_tcm_target
    jal     zero, pt_tcm_done
pt_tcm_target:
    sw      t2, 0(s5)               // positive first store; wrong second store
    li      t0, 1
    li      t2, 0xdead4001
    jal     zero, pt_tcm_branch
pt_tcm_done:

    li      t0, 0
    li      t2, 0x0000a501
    .align 6
pt_csr_branch:
    beq     t0, zero, pt_csr_target
    jal     zero, pt_csr_done
pt_csr_target:
    csrw    mscratch, t2            // positive first write; wrong second write
    li      t0, 1
    li      t2, 0x0000bad2
    jal     zero, pt_csr_branch
pt_csr_done:

    li      t0, 0
    li      t2, 0x22220001
    .align 6
pt_mmio_branch:
    beq     t0, zero, pt_mmio_target
    jal     zero, pt_mmio_done
pt_mmio_target:
    sw      t2, 0(s7)               // positive first write; wrong second write
    li      t0, 1
    li      t2, 0xdead5001
    jal     zero, pt_mmio_branch
pt_mmio_done:

    // Check and publish all architectural side effects.  A failed check
    // writes a nonzero sentinel and then stops in a bounded host run.
    li      t0, 1
    bne     s0, t0, side_effect_fail
    lw      t1, 0(s5)
    li      t2, 0x5a550001
    bne     t1, t2, side_effect_fail
    csrr    t1, mscratch
    li      t2, 0x0000a501
    bne     t1, t2, side_effect_fail

    sw      s0, 20(s2)
    lw      t1, 0(s5)
    sw      t1, 24(s2)
    csrr    t1, mscratch
    sw      t1, 28(s2)
    j       side_effect_done

side_effect_fail:
    li      t0, 0xdeadffff
    sw      t0, 0(s2)
side_effect_done:
    j       side_effect_done

    .section .signature, "aw", @progbits
    .align  2
    .globl  __signature_start
__signature_start:
    .word   0                       // pred-NT register result
    .word   0                       // pred-NT wrong TCM location
    .word   0                       // pred-NT positive TCM location
    .word   0                       // pred-NT wrong CSR (mscratch)
    .word   0                       // pred-NT positive CSR (mtvec)
    .word   0                       // trained pred-T register result
    .word   0                       // trained pred-T TCM result
    .word   0                       // trained pred-T CSR result
    .globl  __signature_end
__signature_end:

    .section .storage, "aw", @progbits
    .align  2
nt_wrong_tcm:
    .word   0
nt_pos_tcm:
    .word   0
pt_tcm:
    .word   0
