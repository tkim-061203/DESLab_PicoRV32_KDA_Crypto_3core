# Merged TCL Script

# All RTL lives under <repo>/rtl/ ; this script runs with CWD = scripts/vivado/.
# Read order is unchanged from the pre-consolidation script on purpose, so the
# resulting netlist and reports stay directly comparable.
#
# MUST be invoked from scripts/vivado/ : system.v does
#   initial $readmemh("bootloader.hex", boot_mem)
# which resolves against the tool's CWD, not the .v file's directory.

# Wrapper and System Verilog Files
read_verilog ../../rtl/soc/system.v
read_verilog ../../rtl/soc/axi_to_apb_bridge.v
read_verilog ../../rtl/soc/apb_interconnect.v
# ---- Crypto subsystem ----
# Five files: the cluster and its MMIO wrapper, plus one file per cipher
# holding all of that cipher's sub-modules.  One copy of every module.
read_verilog ../../rtl/crypto/crypto_cluster.v
read_verilog ../../rtl/crypto/aead_mmap_wrapper.v
read_verilog ../../rtl/crypto/tinyjambu.v
read_verilog ../../rtl/crypto/xoodyak.v
read_verilog ../../rtl/crypto/gift_cofb.v
read_verilog ../../rtl/peripherals/simple_spi_master.v
read_verilog ../../rtl/cpu/picorv32.v
read_verilog ../../rtl/peripherals/simpleuart.v

# Constraints
read_xdc synth_system.xdc

# Synthesis and Implementation
synth_design -part XC7A100TCSG324-1 -top system
opt_design
place_design
route_design

# Reports
report_utilization -hierarchical -file report_utilization.rpt
report_timing

# Write Outputs
write_verilog -force synth_system.v
write_bitstream -force synth_system.bit

proc report_core_timing {inst_path report_file} {
    set inst [get_cells -quiet $inst_path]
    if {[llength $inst] == 0} {
        set fh [open $report_file "w"]
        puts $fh "Instance not found: $inst_path"
        close $fh
        return
    }

    set regs [get_cells -hierarchical -quiet -filter "IS_SEQUENTIAL && NAME =~ ${inst_path}/*"]
    if {[llength $regs] == 0} {
        set fh [open $report_file "w"]
        puts $fh "No sequential cells found under $inst_path"
        close $fh
        return
    }

    report_timing -from $regs -to $regs -max_paths 10 -file $report_file
}

# Full System Reports
report_utilization -hierarchical -hierarchical_depth 3 -file report_util_full.txt

# Per-core Utilization Reports
report_utilization -cells [get_cells u_aead/u_cluster/u_tinyjambu] -file report_util_tinyjambu.txt
report_utilization -cells [get_cells u_aead/u_cluster/u_xoodyak]   -file report_util_xoodyak.txt
report_utilization -cells [get_cells u_aead/u_cluster/u_cofb]      -file report_util_giftcofb.txt

# Per-core Timing Reports
report_core_timing u_aead/u_cluster/u_tinyjambu report_timing_tinyjambu.txt
report_core_timing u_aead/u_cluster/u_xoodyak   report_timing_xoodyak.txt
report_core_timing u_aead/u_cluster/u_cofb      report_timing_giftcofb.txt

# Summary Timing
report_timing_summary -file report_timing_summary.txt
