VIVADO_BASE = /tools/Xilinx/Vivado/2024.2
VIVADO = $(VIVADO_BASE)/bin/vivado
XVLOG = $(VIVADO_BASE)/bin/xvlog
XELAB = $(VIVADO_BASE)/bin/xelab
XSIM = $(VIVADO_BASE)/bin/xsim
GLBL = $(VIVADO_BASE)/data/verilog/src/glbl.v
IVERILOG ?= iverilog
VVP ?= vvp
TOOLCHAIN_PREFIX = /opt/riscv/bin/riscv64-unknown-elf-
CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

export VIVADO

export RDI_VERBOSE = False

SIM_RTL = \
	system_tb.v \
	system.v \
	axi_to_apb_bridge.v \
	apb_interconnect.v \
	crypto_cluster.v \
	../../picosoc/aead_mmap_wrapper.v \
	../../picosoc/simple_spi_master.v \
	../../picorv32.v \
	../../picosoc/simpleuart.v \
	../../picosoc/tinyjambu/tinyjambu_core.v \
	../../picosoc/tinyjambu/tinyjambu_datapath.v \
	../../picosoc/tinyjambu/tinyjambu_nlfsr.v \
	../../picosoc/tinyjambu/tinyjambu_fsm.v \
	../../picosoc/Xoodyak_old/xoodoo.v \
	../../picosoc/Xoodyak_old/xoodoo_n_rounds.v \
	../../picosoc/Xoodyak_old/xoodoo_rc.v \
	../../picosoc/Xoodyak_old/xoodoo_round.v \
	../../picosoc/Xoodyak_old/xoodyakcore.v \
	../../picosoc/GIFT_COFB/cofb_core.v \
	../../picosoc/GIFT_COFB/double_half_block.v \
	../../picosoc/GIFT_COFB/feedback_G.v \
	../../picosoc/GIFT_COFB/gift128_addroundkey.v \
	../../picosoc/GIFT_COFB/gift128_encrypt_top.v \
	../../picosoc/GIFT_COFB/gift128_keyschedule.v \
	../../picosoc/GIFT_COFB/gift128_permbits.v \
	../../picosoc/GIFT_COFB/gift128_round.v \
	../../picosoc/GIFT_COFB/gift128_roundconst.v \
	../../picosoc/GIFT_COFB/gift128_subcells.v \
	../../picosoc/GIFT_COFB/padding.v \
	../../picosoc/GIFT_COFB/pho.v \
	../../picosoc/GIFT_COFB/pho1.v \
	../../picosoc/GIFT_COFB/phoprime.v \
	../../picosoc/GIFT_COFB/triple_half_block.v \
	../../picosoc/GIFT_COFB/xor_block.v \
	../../picosoc/GIFT_COFB/xor_topbar_block.v

# =======================================================================
# Gate-level simulation of the OpenLane sky130 netlist
# =======================================================================
# The netlist is sky130, not Xilinx, so Vivado cannot elaborate it (every cell
# comes out a black box).  These targets run it under iverilog/xsim against the
# sky130 cell models instead.
#
# NOTE: RTL under scripts/ (system.v, crypto_cluster.v) is the FPGA variant with
# inferred memories.  The netlist was built from openlane/designs/picosoc/src/,
# which uses SRAM macros.  Everything below points at the OpenLane sources.

PDK ?= sky130A

# Volare installs into $HOME/.volare/volare/sky130/versions/<hash>, and that
# versioned directory -- not $HOME/.volare -- is what OpenLane records as
# PDK_ROOT (see PDK_ROOT / CELL_VERILOG_MODELS in any run's resolved.json).
# Search the layouts volare/ciel/open_pdks actually use and take the first one
# that really holds the cell models.  Set PDK_ROOT explicitly to skip the search.
PDK_ROOT ?=
PDK_SEARCH = $(PDK_ROOT) \
	$(wildcard $(HOME)/.volare/volare/sky130/versions/*) \
	$(HOME)/.volare \
	$(wildcard $(HOME)/.ciel/volare/sky130/versions/*) \
	$(HOME)/.ciel \
	/usr/local/share/pdk \
	/opt/pdk
PDK_ROOT_RESOLVED := $(firstword $(foreach r,$(PDK_SEARCH), \
	$(if $(wildcard $(r)/$(PDK)/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v),$(r))))

PDK_VLOG = $(PDK_ROOT_RESOLVED)/$(PDK)/libs.ref/sky130_fd_sc_hd/verilog
PDK_SRAM = $(PDK_ROOT_RESOLVED)/$(PDK)/libs.ref/sky130_sram_macros/verilog

GL_DIR   = ../../sim/gl
GL_PDK   = $(GL_DIR)/pdk
GL_BUILD = $(GL_DIR)/build

OL_DESIGNS = ../../openlane/designs
OL_SRC     = $(OL_DESIGNS)/picosoc/src
OL_RUN    ?= $(lastword $(sort $(wildcard $(OL_DESIGNS)/picosoc/runs/RUN_*)))

# Latest run wins; RUN_<ISO date> sorts chronologically.  crypto_cluster is
# hardened out of designs/wrapper/ (DESIGN_NAME: crypto_cluster), not out of a
# directory named after it.
NL_TOP      ?= ../../rtl/system.nl.v
PICORV32_NL ?= $(lastword $(sort $(wildcard $(OL_DESIGNS)/picorv32/runs/RUN_*/final/nl/picorv32_axi.nl.v)))
CRYPTO_NL   ?= $(lastword $(sort $(wildcard $(OL_DESIGNS)/wrapper/runs/RUN_*/final/nl/crypto_cluster.nl.v)))

SDF_TOP    ?= $(OL_RUN)/final/sdf/nom_tt_025C_1v80/system__nom_tt_025C_1v80.sdf
SDF_CPU    ?= $(patsubst %/nl/picorv32_axi.nl.v,%/sdf/nom_tt_025C_1v80/picorv32_axi__nom_tt_025C_1v80.sdf,$(PICORV32_NL))
SDF_CRYPTO ?= $(patsubst %/nl/crypto_cluster.nl.v,%/sdf/nom_tt_025C_1v80/crypto_cluster__nom_tt_025C_1v80.sdf,$(CRYPTO_NL))

# Netlist preparation for the functional run -- see sim/gl/gl_prep.py for why
# both transforms are needed.  Short version: dropping decap/fill/tap/diode
# takes 134k of 163k instances out of the elaboration, and collapsing the clock
# tree removes the artificial 5-6 ns skew that UNIT_DELAY=#1 creates between
# the macros and the top level (OpenROAD balanced CTS in real time, not in cell
# counts).  GL_PREP=0 uses the netlists untouched, which is what the SDF run
# needs.
GL_PREP           ?= 1
GL_STRIP_PHYSICAL ?= 1
GL_FLATTEN_CLOCK  ?= 1
GL_PREP_FLAGS = $(if $(filter 0,$(GL_STRIP_PHYSICAL)),--keep-physical,) \
	$(if $(filter 0,$(GL_FLATTEN_CLOCK)),--keep-clock-tree,)

# Longest combinational chain is 25 cells (picorv32), so at 1 ns per cell the
# functional run needs a period comfortably above that.  Everything in the
# design and the testbench counts clock cycles, not nanoseconds, so a long
# period costs nothing.  The SDF run overrides this to the signoff 25 ns.
GL_CLK_NS ?= 50

ifeq ($(GL_PREP),1)
GL_NL_TOP    = $(GL_BUILD)/system.nl.v
GL_NL_CPU    = $(GL_BUILD)/picorv32_axi.nl.v
GL_NL_CRYPTO = $(GL_BUILD)/crypto_cluster.nl.v
else
GL_NL_TOP    = $(NL_TOP)
GL_NL_CPU    = $(PICORV32_NL)
GL_NL_CRYPTO = $(CRYPTO_NL)
endif

# sky130_sram_4kbyte_1rw_32x1024_8 is a hard macro (macros/ has only
# .gds/.lef/.lib), so a behavioural model is the only option.  gl_pdk_fetch
# prefers the PDK's OpenRAM model; GL_SRAM_MODEL=local forces the one in sim/gl.
# Before gl_pdk_fetch has run, fall back to the local model so that
# sim_system_ol works without a PDK at all.
GL_SRAM_MODEL ?= auto
GL_SRAM_SRC = $(if $(wildcard $(GL_PDK)/sky130_sram_4kbyte_1rw_32x1024_8.v), \
		$(GL_PDK)/sky130_sram_4kbyte_1rw_32x1024_8.v, \
		$(GL_DIR)/sky130_sram_4kbyte_1rw_32x1024_8.v)

# dfxtp has no reset pin, so in a gate netlist those flops power up X and a
# handful of never-reset registers in system.v (active_is_ram, apb_paddr, ...)
# poison the whole datapath.  dff_init.v gives them a defined power-up state,
# the equivalent of a simulator's +initreg.  It must precede the PDK models,
# whose include guards it claims.
GL_DFF_INIT ?= 1
GL_DEFS = -DFUNCTIONAL -DUNIT_DELAY=\#1 -DGL_NETLIST -DGL_CLK_NS=$(GL_CLK_NS) \
	$(if $(filter 1,$(GL_DFF_INIT)),-DGL_DFF_INIT,)
GL_XDEFS = -d FUNCTIONAL -d UNIT_DELAY=\#1 -d GL_NETLIST -d GL_CLK_NS=$(GL_CLK_NS) \
	$(if $(filter 1,$(GL_DFF_INIT)),-d GL_DFF_INIT,)

GL_SRC = $(GL_DIR)/system_nl_tb.v \
	$(GL_DIR)/nettype_wire.v \
	$(GL_NL_TOP) \
	$(GL_NL_CPU) \
	$(GL_NL_CRYPTO) \
	$(GL_DIR)/dff_init.v \
	$(GL_PDK)/primitives.v \
	$(GL_PDK)/sky130_fd_sc_hd.v \
	$(GL_PDK)/sky130_ef_sc_hd.v \
	$(GL_SRAM_SRC)

# RTL baseline: same testbench driving the OpenLane RTL instead of the netlist.
# USE_POWER_PINS stays undefined so the whole set is consistently power-less,
# which is also what our SRAM model expects.
OL_RTL = $(filter-out $(wildcard $(OL_SRC)/*_stub.v) \
		$(OL_SRC)/tinyjambu_mmio.v $(OL_SRC)/xoodyak_mmio.v $(OL_SRC)/cofb_mmio.v, \
		$(wildcard $(OL_SRC)/*.v))

SIM_OL_SRC = $(GL_DIR)/system_nl_tb.v \
	$(GL_DIR)/nettype_wire.v \
	$(OL_RTL) \
	$(GL_SRAM_SRC)

# GL_FW=smoke used to route the console through OUTBYTE instead of the UART,
# because the netlist hardened UART_TX_HOLDOFF at 9000 cycles and the
# testbench could no longer override it. UART_TX_HOLDOFF has since been
# removed from the RTL (tx_ready now follows the real UART busy state), so
# firmware.c no longer has an OUTBYTE-console path; smoke/full now just pick
# the output hex filename below and build the same firmware.
GL_FW ?= smoke
ifeq ($(GL_FW),full)
GL_APP_HEX = sim_app.hex
else
GL_APP_HEX = sim_app_gl.hex
endif

.PHONY: gl_pdk_fetch gl_check gl_fwcheck gl_prep sim_netlist sim_netlist_xsim \
	sim_netlist_sdf sim_netlist_sdf_run sim_system_ol

# The app SRAM has no byte write-enable and system.v drives app_din straight
# from cpu_wdata, so on this netlist an sb/sh writes picorv32's replicated
# wdata into all four lanes and destroys the rest of the word.  Catch it here
# rather than after an hours-long gate-level run.
GL_FW_ELF = $(patsubst %.hex,%.elf,$(GL_APP_HEX))

gl_fwcheck: $(GL_FW_ELF)
	python3 $(GL_DIR)/check_bytestores.py $(GL_FW_ELF)

gl_pdk_fetch:
	@if [ -z "$(PDK_ROOT_RESOLVED)" ]; then \
		echo "ERROR: no sky130 PDK found. Searched:"; \
		for r in $(PDK_SEARCH); do echo "    $$r"; done; \
		echo "Set it explicitly:  make gl_pdk_fetch PDK_ROOT=<dir containing $(PDK)/libs.ref>"; \
		echo "The last OpenLane run used:"; \
		grep -ho '"PDK_ROOT": "[^"]*"' $(OL_DESIGNS)/*/runs/RUN_*/resolved.json 2>/dev/null \
			| sort -u | sed 's/^/    /' || true; \
		echo "  (that path is recorded from whichever machine ran OpenLane, so it may"; \
		echo "   not exist here - check with: ls <path>/$(PDK)/libs.ref)"; \
		exit 1; \
	fi
	@echo "[PDK] root: $(PDK_ROOT_RESOLVED)"
	mkdir -p $(GL_PDK)
	cp $(PDK_VLOG)/primitives.v      $(GL_PDK)/
	cp $(PDK_VLOG)/sky130_fd_sc_hd.v $(GL_PDK)/
	@if [ -f $(PDK_VLOG)/sky130_ef_sc_hd.v ]; then \
		cp $(PDK_VLOG)/sky130_ef_sc_hd.v $(GL_PDK)/; \
		echo "[PDK] sky130_ef_sc_hd.v <- PDK"; \
	else \
		cp $(GL_DIR)/sky130_ef_sc_hd_stub.v $(GL_PDK)/sky130_ef_sc_hd.v; \
		if grep -q "^module sky130_ef_sc_hd__decap_12" $(GL_PDK)/sky130_fd_sc_hd.v; then \
			echo "[PDK] no separate sky130_ef_sc_hd.v; ef cells live in sky130_fd_sc_hd.v -> local stub self-disables"; \
		else \
			echo "[PDK] sky130_ef_sc_hd.v not in PDK -> local stub provides decap_12"; \
		fi; \
	fi
	@if [ "$(GL_SRAM_MODEL)" != "local" ] && [ -f $(PDK_SRAM)/sky130_sram_4kbyte_1rw_32x1024_8.v ]; then \
		cp $(PDK_SRAM)/sky130_sram_4kbyte_1rw_32x1024_8.v $(GL_PDK)/; \
		echo "[PDK] SRAM model <- PDK OpenRAM (set GL_SRAM_MODEL=local to override)"; \
	else \
		cp $(GL_DIR)/sky130_sram_4kbyte_1rw_32x1024_8.v $(GL_PDK)/; \
		echo "[PDK] SRAM model <- local behavioural model"; \
	fi
	@echo "[PDK] $(GL_PDK) ready"

$(GL_BUILD)/system.nl.v: $(NL_TOP) $(GL_DIR)/gl_prep.py
	@mkdir -p $(GL_BUILD)
	python3 $(GL_DIR)/gl_prep.py $< $@ --clock clk $(GL_PREP_FLAGS)

$(GL_BUILD)/picorv32_axi.nl.v: $(PICORV32_NL) $(GL_DIR)/gl_prep.py
	@mkdir -p $(GL_BUILD)
	python3 $(GL_DIR)/gl_prep.py $< $@ --clock clk $(GL_PREP_FLAGS)

$(GL_BUILD)/crypto_cluster.nl.v: $(CRYPTO_NL) $(GL_DIR)/gl_prep.py
	@mkdir -p $(GL_BUILD)
	python3 $(GL_DIR)/gl_prep.py $< $@ --clock PCLK $(GL_PREP_FLAGS)

gl_prep: $(GL_BUILD)/system.nl.v $(GL_BUILD)/picorv32_axi.nl.v $(GL_BUILD)/crypto_cluster.nl.v

gl_check:
	@echo "--- netlists ---"
	@for f in "$(NL_TOP)" "$(PICORV32_NL)" "$(CRYPTO_NL)"; do \
		if [ -n "$$f" ] && [ -f "$$f" ]; then \
			printf "  OK      %-72s cells=%s\n" "$$f" "$$(grep -cE '^ sky130' $$f)"; \
		else \
			printf "  MISSING %s\n" "$${f:-<unresolved wildcard>}"; \
		fi; \
	done
	@echo "--- rtl/system.nl.v vs $(OL_RUN) ---"
	@if [ -f "$(OL_RUN)/final/nl/system.nl.v" ]; then \
		a=$$(md5sum "$(NL_TOP)" | cut -d' ' -f1); \
		b=$$(md5sum "$(OL_RUN)/final/nl/system.nl.v" | cut -d' ' -f1); \
		[ "$$a" = "$$b" ] && echo "  md5 match ($$a)" \
			|| echo "  MD5 MISMATCH - rtl/system.nl.v is stale, re-copy from the run"; \
	else echo "  run netlist not found"; fi
	@echo "--- netlist prep (GL_PREP=$(GL_PREP) strip=$(GL_STRIP_PHYSICAL) flatten_clock=$(GL_FLATTEN_CLOCK)) ---"
	@echo "  clock period GL_CLK_NS=$(GL_CLK_NS) ns  (longest chain 25 cells @ 1 ns)"
	@for f in $(GL_NL_TOP) $(GL_NL_CPU) $(GL_NL_CRYPTO); do \
		[ -f "$$f" ] && printf "  %-40s %7s cells\n" "$$f" "$$(grep -cE '^ sky130' $$f)" \
			|| printf "  %-40s (not built - run: make gl_prep)\n" "$$f"; \
	done
	@echo "--- sdf (nom_tt_025C_1v80) ---"
	@for f in "$(SDF_TOP)" "$(SDF_CPU)" "$(SDF_CRYPTO)"; do \
		[ -f "$$f" ] && printf "  OK      %s\n" "$$f" || printf "  MISSING %s\n" "$$f"; \
	done
	@echo "--- pdk ---"
	@if [ -n "$(PDK_ROOT_RESOLVED)" ]; then echo "  PDK_ROOT = $(PDK_ROOT_RESOLVED)"; \
	else echo "  NOT FOUND - set PDK_ROOT= (searched: $(PDK_SEARCH))"; fi
	@echo "--- pdk models ---"
	@for f in $(GL_PDK)/primitives.v $(GL_PDK)/sky130_fd_sc_hd.v \
		  $(GL_PDK)/sky130_ef_sc_hd.v $(GL_PDK)/sky130_sram_4kbyte_1rw_32x1024_8.v; do \
		[ -f "$$f" ] && printf "  OK      %s\n" "$$f" \
			|| printf "  MISSING %s   (run: make gl_pdk_fetch)\n" "$$f"; \
	done
	@echo "--- firmware ---"
	@echo "  GL_FW=$(GL_FW) -> $(GL_APP_HEX)"
	@[ -f $(GL_FW_ELF) ] && python3 $(GL_DIR)/check_bytestores.py $(GL_FW_ELF) --warn \
		| sed 's/^/  /' || echo "  ($(GL_FW_ELF) not built yet)"
	@echo "--- rtl baseline sources for sim_system_ol ---"
	@for f in $(OL_RTL); do echo "  $$f"; done

sim_netlist: $(GL_APP_HEX) $(GL_NL_TOP) $(GL_NL_CPU) $(GL_NL_CRYPTO)
	@python3 $(GL_DIR)/check_bytestores.py $(GL_FW_ELF) --warn
	$(IVERILOG) -g2012 $(GL_DEFS) -o system_nl_tb.vvp $(GL_SRC)
	$(VVP) system_nl_tb.vvp +app_hex=$(GL_APP_HEX) $(SIM_ARGS) $(if $(VCD),+vcd,)

sim_netlist_xsim: $(GL_APP_HEX) $(GL_NL_TOP) $(GL_NL_CPU) $(GL_NL_CRYPTO)
	rm -rf xsim.dir
	$(XVLOG) $(GL_XDEFS) $(GL_SRC)
	$(XELAB) system_nl_tb -timescale 1ns/1ps --relax -s sim_nl
	$(XSIM) sim_nl -R -testplusarg app_hex=$(GL_APP_HEX)

# SDF needs the specify blocks (so no FUNCTIONAL) and the physical cells back,
# and iverilog's SDF support is partial -- xsim only.  Clock drops to the 25 ns
# the design was signed off at (CLOCK_PERIOD: 25 in picosoc/config.json).
sim_netlist_sdf:
	$(MAKE) GL_PREP=0 sim_netlist_sdf_run

sim_netlist_sdf_run: $(GL_APP_HEX)
	rm -rf xsim.dir
	$(XVLOG) -d GL_NETLIST -d GL_CLK_NS=25 -d USE_SDF \
		-d SDF_TOP=\"$(SDF_TOP)\" \
		-d SDF_CPU=\"$(SDF_CPU)\" \
		-d SDF_CRYPTO=\"$(SDF_CRYPTO)\" \
		$(GL_SRC)
	$(XELAB) system_nl_tb -timescale 1ns/1ps --relax --maxdelay \
		-transport_int_delays -pulse_r 0 -pulse_int_r 0 -s sim_nl_sdf
	$(XSIM) sim_nl_sdf -R -testplusarg app_hex=$(GL_APP_HEX)

sim_system_ol: $(GL_APP_HEX)
	$(IVERILOG) -g2012 -o system_ol_tb.vvp $(SIM_OL_SRC)
	$(VVP) system_ol_tb.vvp +app_hex=$(GL_APP_HEX) $(SIM_ARGS) $(if $(VCD),+vcd,)

sim_app_gl.elf: ../../firmware/app_crt0.S ../../firmware/firmware.c ../../firmware/firmware.ld
	$(CC) \
		-march=rv32i -mabi=ilp32 -Os -g \
		-ffreestanding -fno-builtin \
		-ffunction-sections -fdata-sections \
		-nostdlib -nostartfiles \
		-DSKIP_SD_TEST=1 \
		-Wl,--gc-sections \
		-T ../../firmware/firmware.ld \
		-o $@ \
		../../firmware/app_crt0.S \
		../../firmware/firmware.c \
		-lgcc

sim_app_gl.bin: sim_app_gl.elf
	$(OBJCOPY) -O binary $< $@

sim_app_gl.hex: sim_app_gl.bin
	python3 ../../firmware/makehex.py $< 4096 > $@

help:
	@echo ""
	@echo "Simple synthesis tests:"
	@echo "  make synth_area_{small|regular|large}"
	@echo "  make synth_speed"
	@echo ""
	@echo "System (SD-boot):"
	@echo "  make synth_system          <- synthesis (1 lần, chỉ cần khi đổi RTL/bootloader)"
	@echo "  make bootloader.hex        <- rebuild bootloader nếu bootloader.c thay đổi"
	@echo "  make sim_system            <- RTL system test + throughput summary (skips SD test)"
	@echo ""
	@echo "Gate-level (netlist sky130 của OpenLane):"
	@echo "  make gl_check              <- kiểm tra đường dẫn netlist/SDF/PDK trước khi chạy"
	@echo "  make gl_pdk_fetch          <- copy model sky130 ra sim/gl/pdk (chạy 1 lần, trong OpenLane2)"
	@echo "  make sim_system_ol         <- baseline RTL OpenLane (cùng testbench) - chạy trước để so"
	@echo "  make sim_netlist           <- gate-level bằng iverilog       <-- mục tiêu chính"
	@echo "  make sim_netlist_xsim      <- gate-level bằng Vivado xsim"
	@echo "  make sim_netlist_sdf       <- gate-level + SDF back-annotation (xsim, 25 ns)"
	@echo "  Biến: GL_FW=smoke|full  GL_CLK_NS=50  GL_PREP=1|0  PDK_ROOT=...  VCD=1"
	@echo ""
	@echo "Firmware update (KHÔNG cần synthesis lại):"
	@echo "  cd ../../firmware && make firmware"
	@echo "  cd ../../firmware && make write-sd SD_DEV=/dev/sdX"
	@echo "  (reset FPGA - bootloader tự đọc SD và load firmware)"
	@echo ""

synth_%:
	rm -f $@.log
	$(VIVADO) -nojournal -log $@.log -mode batch -source $@.tcl
	rm -rf .Xil fsm_encoding.os synth_*.backup.log usage_statistics_webtalk.xml
	-grep -B4 -A10 'Slice LUTs' $@.log
	-grep -B1 -A9 ^Slack $@.log && echo


synth_system: bootloader.hex

sim_system: bootloader.hex sim_app.hex
	$(IVERILOG) -g2012 -o system_tb.vvp $(SIM_RTL)
	$(VVP) system_tb.vvp $(SIM_ARGS) $(if $(VCD),+vcd,)

sim_app.elf: ../../firmware/app_crt0.S ../../firmware/firmware.c ../../firmware/firmware.ld
	$(CC) \
		-march=rv32i -mabi=ilp32 -Os -g \
		-ffreestanding -fno-builtin \
		-ffunction-sections -fdata-sections \
		-nostdlib -nostartfiles \
		-DSKIP_SD_TEST=1 \
		-Wl,--gc-sections \
		-T ../../firmware/firmware.ld \
		-o $@ \
		../../firmware/app_crt0.S \
		../../firmware/firmware.c \
		-lgcc

sim_app.bin: sim_app.elf
	$(OBJCOPY) -O binary $< $@

sim_app.hex: sim_app.bin
	python3 ../../firmware/makehex.py $< 4096 > $@


bootloader.hex: ../../firmware/bootloader.c ../../firmware/boot_crt0.S ../../firmware/bootloader.ld
	$(CC) \
		-march=rv32i -mabi=ilp32 -Os -g \
		-ffreestanding -fno-builtin \
		-nostdlib -nostartfiles \
		-T ../../firmware/bootloader.ld \
		-o bootloader_tmp.elf \
		../../firmware/boot_crt0.S \
		../../firmware/bootloader.c
	$(OBJCOPY) -O binary bootloader_tmp.elf bootloader_tmp.bin
	python3 ../../firmware/makehex.py bootloader_tmp.bin 1024 > bootloader.hex
	rm -f bootloader_tmp.elf bootloader_tmp.bin
	@echo "[BOOT] bootloader.hex ready (1024 words = 4 KB)"
	@echo "[INFO] Re-synthesize Vivado project để nạp bootloader mới vào bitfile"

# -------------------------------------------------------
# firmware.hex (legacy — chỉ dùng cho sim, KHÔNG dùng cho synth_system)
# Nếu không cần sim có thể xóa target này
# -------------------------------------------------------
firmware.hex: firmware.S firmware.c firmware.lds
	$(CC) -Os -ffreestanding -nostdlib \
		-mabi=ilp32 -march=rv32i \
		-o firmware.elf firmware.S firmware.c \
		--std=gnu99 \
		-Wl,-Bstatic,-T,firmware.lds,-Map,firmware.map,\
--strip-debug,--build-id=none -lgcc
	$(OBJCOPY) -O binary firmware.elf firmware.bin
	python3 ../../firmware/makehex.py firmware.bin 4096 > firmware.hex

# -------------------------------------------------------
tab_%/results.txt:
	bash tabtest.sh $@

area: synth_area_small synth_area_regular synth_area_large
	-grep -B4 -A10 'Slice LUTs' \
		synth_area_small.log \
		synth_area_regular.log \
		synth_area_large.log

clean:
	rm -rf .Xil/
	rm -f firmware.bin firmware.elf firmware.hex firmware.map
	rm -f bootloader.hex bootloader_tmp.elf bootloader_tmp.bin
	rm -f sim_app.elf sim_app.bin sim_app.hex system_tb.vvp system.vcd
	rm -f sim_app_gl.elf sim_app_gl.bin sim_app_gl.hex
	rm -f system_nl_tb.vvp system_ol_tb.vvp system_nl.vcd
	rm -rf $(GL_BUILD)
	rm -rf synth_*.log synth_*.mmi synth_*.bit synth_system.v
	rm -rf table.txt tab_*/ webtalk.jou
	rm -rf webtalk.log webtalk_*.jou webtalk_*.log
	rm -rf xelab.* xsim[._]* xvlog.*
