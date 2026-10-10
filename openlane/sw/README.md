# openlane/sw

Firmware for this SoC lives in [`../../firmware`](../../firmware), not here.
This directory used to hold stale, unreferenced copies that predated (and in
some cases had nothing to do with) the current PicoSoC RTL/ASIC design.
Nothing in the repo's Makefiles, OpenLane configs, or scripts referenced
this directory.

Removed (all dead code, verified unreferenced by any Makefile/config/script
before deletion):

- `firmware.c`, `start.s`, `sections.lds` - the generic upstream picosoc
  demo firmware (icebreaker/hx8kdemo example from the original PicoSoC
  project), unrelated to this project's memory map or peripherals.
- `system_firmware.c`, `iot_gateway.c` - firmware using a **stale/wrong**
  crypto address map (TinyJAMBU @ 0x3000_0000, Xoodyak @ 0x4000_0000,
  GIFT-COFB @ 0x5000_0000 as three separate blocks). The current RTL
  (`rtl/crypto/`, `openlane/designs/picosoc/src/aead_mmap_wrapper.v`) has a
  single AEAD wrapper at 0x3000_0000 with an algorithm-select field, so this
  code cannot run against current hardware.
- `bootloader.hex` - a stale prebuilt hex for the old (wrong) firmware
  above; not the bootloader.hex this project's `firmware/Makefile` produces.

Kept:

- `iot_receiver.py` - a host-side (PC) UART tool, not device firmware. It
  decodes `[PKT|...]` lines and expects the `JB`/`XD`/`GC` algorithm tags
  that `iot_gateway.c` used to print. With `iot_gateway.c` removed, no
  firmware in this repo currently emits that packet format, so this script
  is kept as a standalone utility but has no matching sender right now.
