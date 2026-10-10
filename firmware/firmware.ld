/*
 * firmware.ld  –  Linker script for the main application firmware
 *
 * The bootloader copies firmware.bin from SD card to App BRAM starting
 * at 0x0001_0000, then jumps there.  All application code must be
 * position-dependent and linked to start at 0x0001_0000.
 *
 * App RAM: 16 KB at 0x0001_0000 - 0x0001_3FFF.
 * The top 2 KB (0x0001_3800 - 0x0001_3FFF) is reserved for the
 * bootloader's own BL_RAM (see bootloader.ld) and must not be used by
 * the app image or its stack -- see the ASSERT below.
 */

MEMORY
{
    APP_RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 16K
}

ENTRY(app_entry)

SECTIONS
{
    . = 0x00010000;

    /* ---- Reset / entry vector ---- */
    .text.entry : {
        *(.text.entry)
    } > APP_RAM

    /* ---- Code ---- */
    .text : {
        *(.text*)
    } > APP_RAM

    /* ---- Read-only data ---- */
    .rodata : {
        *(.rodata*)
    } > APP_RAM

    /* ---- Initialised data ---- */
    .data : {
        *(.data*)
    } > APP_RAM

    /* ---- Zero-initialised data ---- */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > APP_RAM

    _stack_top = ORIGIN(APP_RAM) + LENGTH(APP_RAM);

    /* 0x800 = 2 KB = BL_RAM (see bootloader.ld), which starts at
     * _stack_top - 0x800 = 0x0001_3800 and holds the bootloader's own
     * .data/.bss/stack while it is copying this image in from the SD
     * card. The app image (.text/.rodata/.data/.bss) must end at or
     * before that address, or it corrupts the bootloader's live state
     * mid-copy (and, once running, would leave the app's own .bss/stack
     * overlapping BL_RAM). This bound is the bootloader's load limit,
     * not just "fits in App RAM". */
    ASSERT(. <= _stack_top - 0x800,
        "ERROR: application too large - overruns BL_RAM (bootloader.ld), does not fit in 16 KB App RAM!")
}
