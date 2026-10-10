# =============================================================
# Makefile – PicoRV32 SD Bootloader + Application
#
# Requirements:
#   riscv32-unknown-elf-gcc  (or riscv64-unknown-elf-gcc -march=rv32i)
#   python3
#   make
# =============================================================

CROSS 	?= riscv64-unknown-elf
CC       = $(CROSS)-gcc
OBJCOPY  = $(CROSS)-objcopy
OBJDUMP  = $(CROSS)-objdump

# Common RISC-V flags for bare-metal RV32I (matches PicoRV32 default)
ARCH_FLAGS = -march=rv32i -mabi=ilp32

CFLAGS_COMMON = $(ARCH_FLAGS) -Os -g \
    -ffreestanding -fno-builtin \
    -Wall -Wextra \
    -ffunction-sections -fdata-sections \
    -nostdlib -nostartfiles

# -------------------------------------------------------
# 1. BOOTLOADER  (runs from Boot BRAM @ 0x0000_0000)
# -------------------------------------------------------
BOOT_SRCS  = boot_crt0.S bootloader.c
BOOT_LD    = bootloader.ld
BOOT_ELF   = bootloader.elf
BOOT_BIN   = bootloader.bin
BOOT_HEX   = bootloader.hex
BOOT_DUMP  = bootloader.dis

.PHONY: bootloader
bootloader: $(BOOT_HEX)

$(BOOT_ELF): $(BOOT_SRCS) $(BOOT_LD)
	$(CC) $(CFLAGS_COMMON) -T $(BOOT_LD) -o $@ $(BOOT_SRCS)
	@echo "[BOOT] Size:"
	@$(CROSS)-size $@

$(BOOT_BIN): $(BOOT_ELF)
	$(OBJCOPY) -O binary $< $@

$(BOOT_HEX): $(BOOT_BIN)
	python3 makehex.py $< > $@
	@echo "[BOOT] bootloader.hex ready → copy to Vivado project as bootloader.hex"

$(BOOT_DUMP): $(BOOT_ELF)
	$(OBJDUMP) -d -S $< > $@

# -------------------------------------------------------
# 1b. ASIC BOOT ROM  (openlane/designs/picosoc/src/boot_rom.v)
#     Bakes bootloader.hex into a registered case-statement ROM that
#     replaces the old u_boot_sram macro (which had no write port wired
#     up and so could never actually be loaded on silicon). Must be
#     regenerated any time bootloader.c/bootloader.ld changes, and
#     OpenLane re-run afterwards.
# -------------------------------------------------------
BOOT_ROM_V = ../openlane/designs/picosoc/src/boot_rom.v

.PHONY: boot_rom
boot_rom: $(BOOT_ROM_V)

$(BOOT_ROM_V): $(BOOT_HEX) gen_boot_rom.py
	python3 gen_boot_rom.py $(BOOT_HEX) $@
	@echo "[BOOT] boot_rom.v ready -> re-run OpenLane synthesis to pick it up"

# -------------------------------------------------------
# 2. APPLICATION FIRMWARE  (loaded into App BRAM @ 0x0001_0000)
# -------------------------------------------------------
# List your application source files here:
APP_SRCS   = app_crt0.S firmware.c
APP_LD     = firmware.ld
APP_ELF    = firmware.elf
APP_BIN    = firmware.bin
APP_DUMP   = firmware.dis

# Skip SD card test to keep firmware within 16 KB App BRAM
APP_CFLAGS = $(CFLAGS_COMMON) -DSKIP_SD_TEST=1 -Wno-unused-function

.PHONY: firmware
firmware: $(APP_BIN)

$(APP_ELF): $(APP_SRCS) $(APP_LD)
	$(CC) $(APP_CFLAGS) -Wl,--gc-sections -T $(APP_LD) -o $@ $(APP_SRCS) -lgcc
	@echo "[APP] Size:"
	@$(CROSS)-size $@

$(APP_BIN): $(APP_ELF)
	python3 wrap_firmware.py $< $@
	@echo "[APP] firmware.bin ready (with 4-byte size header)"
	@echo "      Write to SD card:  dd if=$@ of=/dev/sdX bs=512 seek=2048 conv=notrunc"

$(APP_DUMP): $(APP_ELF)
	$(OBJDUMP) -d -S $< > $@

# -------------------------------------------------------
# 3. Write firmware to SD card
#    WARNING: Replace /dev/sdX with your actual SD device!
# -------------------------------------------------------
# Override: make write-sd SD_DEV=/dev/sdc
SD_DEV ?= /dev/sdb

.PHONY: write-sd write_sd
write_sd: write-sd

write-sd: $(APP_BIN)
	@if [ ! -b "$(SD_DEV)" ]; then \
	    echo "ERROR: $(SD_DEV) khong phai block device (the SD da noi vao VM chua?)"; \
	    lsblk -d -o NAME,SIZE,TRAN,RM,MODEL; \
	    exit 1; \
	fi
	@if findmnt -rno SOURCE / | grep -q "^$(SD_DEV)"; then \
	    echo "ERROR: $(SD_DEV) chua root filesystem - tu choi ghi"; \
	    exit 1; \
	fi
	@lsblk -d -o NAME,SIZE,TRAN,RM,MODEL $(SD_DEV)
	@echo "Unmounting $(SD_DEV)* (if auto-mounted)..."
	-@for m in $$(findmnt -rno TARGET -S $(SD_DEV) 2>/dev/null; \
	             lsblk -rno MOUNTPOINT $(SD_DEV) 2>/dev/null); do \
	    sudo umount "$$m"; \
	done
	@# Phan vung FAT cua the thuong bat dau dung sector 2048: ghi khi con
	@# mount thi kernel co the ghi nguoc FAT/FSInfo de len firmware.
	@if [ -n "$$(lsblk -rno MOUNTPOINT $(SD_DEV) | tr -d '[:space:]')" ]; then \
	    echo "ERROR: $(SD_DEV) van dang mount (dong File Manager roi thu lai):"; \
	    lsblk -o NAME,MOUNTPOINT $(SD_DEV); \
	    exit 1; \
	fi
	@echo "Writing $(APP_BIN) to $(SD_DEV) at sector 2048 (1 MB offset)..."
	sudo dd if=$(APP_BIN) of=$(SD_DEV) bs=512 seek=2048 conv=notrunc oflag=sync
	sync
	@echo "Verifying..."
	@sudo dd if=$(SD_DEV) bs=512 skip=2048 count=$$(( ($$(stat -c %s $(APP_BIN)) + 511) / 512 )) status=none \
	    | cmp -n $$(stat -c %s $(APP_BIN)) - $(APP_BIN) \
	    && echo "Verify OK: the SD khop voi $(APP_BIN)"
	-sudo eject $(SD_DEV)
	@echo "Done - safe to remove the card."

# -------------------------------------------------------
# 4. Helpers
# -------------------------------------------------------
.PHONY: all clean disasm

all: bootloader boot_rom firmware

disasm: $(BOOT_DUMP) $(APP_DUMP)

clean:
	rm -f *.elf *.bin *.hex *.dis
