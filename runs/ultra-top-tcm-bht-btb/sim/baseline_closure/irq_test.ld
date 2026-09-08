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

    .signature 0x0000e000 : ALIGN(4)
    {
        KEEP(*(.signature))
    } > TCM

    __stack_top = ORIGIN(TCM) + LENGTH(TCM);
}

ASSERT(ADDR(.text) + SIZEOF(.text) <= 0x0000e000, "test text overlaps signature")
ASSERT(SIZEOF(.signature) <= 0x1000, "test signature exceeds 4 KiB")

