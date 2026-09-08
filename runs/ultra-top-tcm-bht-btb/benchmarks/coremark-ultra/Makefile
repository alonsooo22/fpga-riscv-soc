SHELL := /bin/bash

CROSS ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc
OBJDUMP := $(CROSS)objdump
SIZE    := $(CROSS)size

ITERATIONS ?= 16
SMOKE_ITERATIONS ?= 476
TOTAL_DATA_SIZE ?= 2000
OPT_LEVEL ?= 2
CONFIG ?= opt$(OPT_LEVEL)
PERF_COUNTERS ?= 1
OUT_DIR := build/$(CONFIG)-iter-$(ITERATIONS)
ELF := $(OUT_DIR)/coremark.elf

ARCH ?= rv32im_zicsr
ABI  ?= ilp32

COMMON_FLAGS := -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany \
                -msmall-data-limit=0 -O$(OPT_LEVEL) -ffreestanding -fno-builtin \
                -fno-stack-protector -fno-pic -fdata-sections \
                -ffunction-sections -std=gnu11 -Wall -Wextra -I.
CPPFLAGS := -DTOTAL_DATA_SIZE=$(TOTAL_DATA_SIZE) -DMEM_METHOD=MEM_STATIC \
            -DMULTITHREAD=1 -DITERATIONS=$(ITERATIONS) -DHAS_FLOAT=0 \
            -DHAS_STDIO=0 -DHAS_PRINTF=0 -DMAIN_HAS_NOARGC=1 \
            -DMAIN_HAS_NORETURN=0 -DSEED_METHOD=SEED_VOLATILE \
            -DMEM_LOCATION=\"TCM\" -DULTRA_OPT_LEVEL=$(OPT_LEVEL)
ifeq ($(PERF_COUNTERS),1)
CPPFLAGS += -DULTRA_PERF_COUNTERS
endif
CFLAGS := $(COMMON_FLAGS)
LDFLAGS := $(COMMON_FLAGS) -nostdlib -Wl,--gc-sections \
           -Wl,-T,linker.ld -Wl,-Map,$(OUT_DIR)/coremark.map

SRCS := startup.S core_main.c core_list_join.c core_matrix.c core_state.c \
        core_util.c core_portme.c ee_printf.c
OBJS := $(patsubst %.c,$(OUT_DIR)/%.o,$(filter %.c,$(SRCS))) \
        $(patsubst %.S,$(OUT_DIR)/%.o,$(filter %.S,$(SRCS)))

.PHONY: all quick smoke full clean

all: $(ELF) $(OUT_DIR)/coremark.dis

$(OUT_DIR):
	mkdir -p $@

$(OUT_DIR)/%.o: %.c | $(OUT_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OUT_DIR)/%.o: %.S | $(OUT_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(ELF): $(OBJS) linker.ld | $(OUT_DIR)
	$(CC) $(LDFLAGS) $(OBJS) -lgcc -o $@
	$(SIZE) $@

$(OUT_DIR)/coremark.dis: $(ELF)
	$(OBJDUMP) -d -S $< > $@

quick:
	$(MAKE) ITERATIONS=16 CONFIG=opt$(OPT_LEVEL) all

smoke:
	$(MAKE) ITERATIONS=$(SMOKE_ITERATIONS) CONFIG=opt$(OPT_LEVEL) all

full:
	$(MAKE) ITERATIONS=18000 CONFIG=opt$(OPT_LEVEL) all

clean:
	rm -rf build
