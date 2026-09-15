OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    TCM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    .text 0x00002000 : ALIGN(4)
    {
        KEEP(*(.text.init))
        *(.text .text.*)
    } > TCM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > TCM

    .data : ALIGN(4)
    {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > TCM

    .bss : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > TCM

    .signature 0x0000e000 : ALIGN(4)
    {
        __signature_start = .;
        KEEP(*(.signature))
        __signature_end = .;
    } > TCM

    __stack_top = ORIGIN(TCM) + LENGTH(TCM);
}

ASSERT(ADDR(.bss) + SIZEOF(.bss) <= 0x0000e000, "TCM data overlaps signature")
ASSERT(SIZEOF(.signature) <= 0x1000, "signature exceeds 4 KiB")
ASSERT(ADDR(.text) + SIZEOF(.text) <= 0x0000e000, "TCM text overlaps signature")
