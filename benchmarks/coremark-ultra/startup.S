    .section .text.init
    .globl _start
    .type _start, @function
_start:
    la   sp, __stack_top
    la   a0, __bss_start
    la   a1, __bss_end
    beq  a0, a1, 2f
1:
    sw   zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, 1b
2:
    call main

    .globl _halt
    .type _halt, @function
_halt:
    j    _halt
    .size _start, .-_start
