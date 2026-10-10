
`default_nettype none

module sram_16kb_wrapper (
`ifdef USE_POWER_PINS
    inout  vccd1,
    inout  vssd1,
`endif
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [11:0] addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0
);

    // ----------------------------------------------------------
    // 16 kB = 2 x sky130_sram_8kbyte_1rw_32x2048_8.
    // Truoc day la 4 x sky130_sram_4kbyte_1rw_32x1024_8; macro 8 kB dac hon
    // (6.85 vs 7.74 um2/bit) nen 2 bank chiem 0.898 mm2 thay vi 1.014 mm2,
    // va bot 2 macro phai lo kenh dinh tuyen + thoat chan.
    // Giao dien module GIU NGUYEN -> system.v khong phai sua.
    // ----------------------------------------------------------

    // ----------------------------------------------------------
    // Bank select: MSB cua dia chi tu 12 bit (2 bank x 2048 tu)
    // ----------------------------------------------------------
    wire bank_sel0 = addr0[11];

    // ----------------------------------------------------------
    // Per-bank active-low chip-select
    // ----------------------------------------------------------
    wire [1:0] csb0_bank;
    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_cs
            assign csb0_bank[i] = csb0 | (bank_sel0 != i[0]);
        end
    endgenerate

    // ----------------------------------------------------------
    // Tie cells cho cac chan spare/wmask cua SRAM.
    // Giu duoi dang wire co ten de Yosys sinh sky130_fd_sc_hd__conb_1
    // (LVS can chung).
    //
    // wmask0 buoc 4'hF: macro 8 kB CO byte write mask (khac ban 4 kB cu chi
    // ghi ca tu), nhung sram_16kb_wrapper khong co cong byte-enable va
    // system.v khong dua AXI wstrb xuong day -> buoc all-ones de giu nguyen
    // hanh vi cu. Muon ton trong wstrb thi them cong wmask vao module nay va
    // noi tu AXI slave trong system.v.
    // ----------------------------------------------------------
    wire tie_lo_addr;
    wire tie_lo_din;
    wire [3:0] tie_hi_wmask;
    assign tie_lo_addr  = 1'b0;
    assign tie_lo_din   = 1'b0;
    assign tie_hi_wmask = 4'hF;

    // ----------------------------------------------------------
    // 33-bit raw outputs from each 8-kB macro bank
    // (bit 32 la cot spare cua macro, khong dung)
    // ----------------------------------------------------------
    wire [32:0] dout0_bank [0:1];

    // ----------------------------------------------------------
    // Instantiate 2 x sky130_sram_8kbyte_1rw_32x2048_8
    // addr0 cua macro rong 12 bit = 1 bit chon hang spare + 11 bit that.
    // ----------------------------------------------------------
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_bank
            sky130_sram_8kbyte_1rw_32x2048_8 u_bank (

                .clk0       (clk0),
                .csb0       (csb0_bank[i]),
                .web0       (web0),
                .wmask0     (tie_hi_wmask),
                .spare_wen0 (tie_lo_din),
                .addr0      ({tie_lo_addr, addr0[10:0]}),
                .din0       ({tie_lo_din,  din0}),
                .dout0      (dout0_bank[i])
            );
        end
    endgenerate

    // ----------------------------------------------------------
    // Synchronous read-data mux.
    // bank_sel0_r khoi tao 1'b0 de dout0 xac dinh (tro vao bank 0) truoc
    // lan truy cap dau tien.
    // ----------------------------------------------------------
    reg bank_sel0_r = 1'b0;
    always @(posedge clk0)
        if (!csb0) bank_sel0_r <= bank_sel0;

    assign dout0 = dout0_bank[bank_sel0_r][31:0];

endmodule
