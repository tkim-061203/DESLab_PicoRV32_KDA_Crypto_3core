/*
 * bootloader.ld — Linker script for PicoRV32 SD bootloader
 *
 * Memory layout:
 *   BOOTROM  0x0000_0000  4 KB  code + rodata (read-only BRAM, pre-loaded hex)
 *   BL_RAM   0x0001_3800  2 KB  bootloader .data/.bss + stack (top of App RAM)
 *
 * Real App RAM is 16 KB at 0x0001_0000 - 0x0001_3FFF (4096 words, see
 * rtl/soc/system.v APP_SIZE and openlane sram_16kb_wrapper). BL_RAM sits in
 * the TOP 2 KB of that same 16 KB (same scheme used by 3core/dual), so the
 * firmware load area is 0x0001_0000 - 0x0001_37FF (14336 B = 0x3800), and
 * firmware.ld's ASSERT enforces that the app image never grows into BL_RAM.
 *
 *   App RAM 16 KB layout during boot:
 *   ┌──────────────────────┐ 0x0001_4000
 *   │  ← stack (grows ↓)  │
 *   │  bootloader .bss     │ ← sbuf[512], g_sdhc, etc.
 *   │  bootloader .data    │
 *   ├──────────────────────┤ 0x0001_3800
 *   │                      │
 *   │  (firmware load area │
 *   │   max 14336 B)       │
 *   │                      │
 *   └──────────────────────┘ 0x0001_0000
 */

MEMORY
{
    BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    BL_RAM  (rw)  : ORIGIN = 0x00013800, LENGTH = 2K
}

ENTRY(boot_entry)

SECTIONS
{
    .text.entry : { *(.text.entry) } > BOOTROM
    .text       : { *(.text*)      } > BOOTROM
    .rodata     : { *(.rodata*)    } > BOOTROM
    .data       : { *(.data*)      } > BL_RAM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > BL_RAM

    _stack_top = ORIGIN(BL_RAM) + LENGTH(BL_RAM);  /* 0x0001_4000 */

    ASSERT(_bss_end <= _stack_top,
        "ERROR: bootloader .data+.bss overflow the 2 KB BL_RAM region!")
}

