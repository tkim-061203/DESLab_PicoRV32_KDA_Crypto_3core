`timescale 1ns/1ps
// ============================================================
// crypto_cluster.v — shared APB slave for 3 AEAD cores
// ============================================================
// ctrl register (addr 0x000):
//   [1:0]  alg_sel    : 00=TinyJAMBU  01=Xoodyak  10=GIFT-COFB  11=invalid
//   [2]    start      : write 1 to trigger (auto-clears next cycle)
//   [3]    decrypt    : 0=encrypt  1=decrypt
//   [4]    reserved   : reads 0
//   [5]    busy       : read-only, set while meas_active
//   [6]    done       : read-only sticky done flag
//   [7]    valid      : read-only sticky valid flag
//   [8]    err        : read-only sticky error flag — set instead of
//                       starting when a non-GIFT-COFB op requests
//                       ad_len/data_len > 16 bytes, or alg_sel == 2'b11
//                       (no core wired to that value); cleared by the
//                       next successful start
//
// While an operation is in flight (busy, see below) ctrl/key/nonce/
// tag_in/lengths writes are ignored (the cores read these registers
// directly for the whole operation); ad/data_in writes are ignored too,
// except for GIFT-COFB (alg_sel==10), which streams the next AD/MSG
// block through them via the ad_ack/msg_ack handshake. stream_ctrl
// (0x64) writes are always accepted.
//
// Only PADDR[11:10] == 2'b00 is decoded for this slot; writes with any
// other value are dropped and reads return 0.
//
// Shared input registers (word-aligned, PADDR[9:2] = word index):
//   0x04–0x10  key[127:0]        words 1–4   write-only, reads 0
//   0x14–0x20  nonce[127:0]      words 5–8   (TinyJAMBU uses [95:0])
//   0x24–0x30  ad[127:0]         words 9–12
//   0x34–0x40  data_in[127:0]    words 13–16
//   0x44–0x50  tag_in[127:0]     words 17–20 (TinyJAMBU uses [63:0])
//   0x54       ad_len[7:0]       word 21
//   0x58       data_len[7:0]     word 22
//   0x5C       msg_len[7:0]      word 23
//   0x60       stream_status     word 24 [4]=gf done&&valid  [3]=gf done
//                                          [2]=gf_ad_req [1]=gf_msg_req
//                                          [0]=gf_data_valid_sticky
//                                        (bits 3/4 come from the sticky
//                                         done/valid flags, gated to
//                                         GIFT-COFB, since the core's own
//                                         done/valid are 1-cycle pulses
//                                         that firmware polling can miss)
//   0x64       stream_ctrl       word 25 write [2]=clr_data_valid
//                                          [1]=ad_ack pulse [0]=msg_ack pulse
//
// Output readback:
//   0x80–0x8C  data_out[127:0]   words 32–35 (tracks the last *started*
//                                             op via meas_alg_sel, not the
//                                             live alg_sel; on a non-GIFT-
//                                             COFB decrypt it reads 0 until
//                                             the op is done AND valid —
//                                             GIFT-COFB streams plaintext
//                                             out before its tag check, so
//                                             it is exempt: firmware must
//                                             discard COFB plaintext if the
//                                             final valid bit is 0)
//   0x90–0x9C  tag_out[127:0]    words 36–39 (reads 0 on a decrypt op —
//                                             the tag is an input there,
//                                             not a verified output)
//   0xA0       meas_status       word 40 [2:1]=active_alg [0]=active
//   0xA4       meas_cycles_cur   word 41
//   0xA8       meas_cycles_last  word 42
//   0xAC       tinyjambu_cycles  word 43
//   0xB0       xoodyak_cycles    word 44
//   0xB4       giftcofb_cycles   word 45
// ============================================================

module crypto_cluster #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire                   PCLK,
    input  wire                   PRESETn,
    input  wire [ADDR_WIDTH-1:0]  PADDR,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire [DATA_WIDTH-1:0]  PWDATA,
    output reg  [DATA_WIDTH-1:0]  PRDATA,
    output wire                   PREADY,
    output wire                   PSLVERR
);
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // -------------------------------------------------------
    // Control & shared input registers
    // -------------------------------------------------------
    reg [1:0] reg_alg_sel;
    reg       reg_decrypt;
    reg       start_pulse;

    reg [127:0] reg_key;
    reg [127:0] reg_nonce;
    reg [127:0] reg_ad;
    reg [127:0] reg_data_in;
    reg [127:0] reg_tag_in;
    reg [7:0]   reg_ad_len;
    reg [7:0]   reg_data_len;
    reg [7:0]   reg_msg_len;
    reg         ad_ack_pulse, msg_ack_pulse;
    reg         gf_data_valid_sticky;

    // Measurement / sticky state — declared here, ahead of the busy/
    // len_bad/start_blocked wires and the control-write case statement
    // below that read meas_active/meas_alg_sel, and ahead of
    // data_out_blank further down that reads done_sticky/valid_sticky.
    // Keeping every reg/wire declared before its first use avoids any
    // tool inferring an implicit (and wrongly 1-bit-wide) net for it.
    reg        meas_active;
    reg [1:0]  meas_alg_sel;
    reg        meas_decrypt;
    reg        done_sticky, valid_sticky, err_sticky;

    wire apb_wr   = PSEL && PENABLE && PWRITE && (PADDR[11:10] == 2'b00);
    wire [7:0] wi = PADDR[9:2];    // word index
    wire busy     = meas_active | start_pulse;

    // A ctrl write that requests start while alg_sel == 2'b11 (no core
    // wired to it) or while a non-GIFT-COFB op asks for more than 16B of
    // AD/data is rejected instead of issuing start_pulse (those cores
    // only support up to a single 16B block); GIFT-COFB takes 8-bit
    // lengths up to 255 and is exempt from the length cap.
    wire len_bad       = (PWDATA[1:0] == 2'b11) ||
                          ((PWDATA[1:0] != 2'b10) &&
                           (reg_ad_len > 8'd16 || reg_data_len > 8'd16));
    wire start_blocked = apb_wr && !busy && (wi == 8'h00) && PWDATA[2] && len_bad;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_alg_sel  <= 2'b00;
            reg_decrypt  <= 1'b0;
            start_pulse  <= 1'b0;
            reg_key      <= 128'b0;
            reg_nonce    <= 128'b0;
            reg_ad       <= 128'b0;
            reg_data_in  <= 128'b0;
            reg_tag_in   <= 128'b0;
            reg_ad_len   <= 8'd0;
            reg_data_len <= 8'd0;
            reg_msg_len  <= 8'd0;
            ad_ack_pulse <= 1'b0;
            msg_ack_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;          // auto-clear every cycle
            ad_ack_pulse <= 1'b0;
            msg_ack_pulse <= 1'b0;
            if (apb_wr) begin
                case (wi)
                    8'h00: if (!busy) begin
                        reg_alg_sel <= PWDATA[1:0];
                        reg_decrypt <= PWDATA[3];
                        start_pulse <= PWDATA[2] && !len_bad;
                    end
                    8'h01: if (!busy) reg_key[  31:  0] <= PWDATA;
                    8'h02: if (!busy) reg_key[  63: 32] <= PWDATA;
                    8'h03: if (!busy) reg_key[  95: 64] <= PWDATA;
                    8'h04: if (!busy) reg_key[ 127: 96] <= PWDATA;
                    8'h05: if (!busy) reg_nonce[  31:  0] <= PWDATA;
                    8'h06: if (!busy) reg_nonce[  63: 32] <= PWDATA;
                    8'h07: if (!busy) reg_nonce[  95: 64] <= PWDATA;
                    8'h08: if (!busy) reg_nonce[ 127: 96] <= PWDATA;
                    8'h09: if (!busy || meas_alg_sel == 2'b10) reg_ad[   31:  0] <= PWDATA;
                    8'h0A: if (!busy || meas_alg_sel == 2'b10) reg_ad[   63: 32] <= PWDATA;
                    8'h0B: if (!busy || meas_alg_sel == 2'b10) reg_ad[   95: 64] <= PWDATA;
                    8'h0C: if (!busy || meas_alg_sel == 2'b10) reg_ad[  127: 96] <= PWDATA;
                    8'h0D: if (!busy || meas_alg_sel == 2'b10) reg_data_in[  31:  0] <= PWDATA;
                    8'h0E: if (!busy || meas_alg_sel == 2'b10) reg_data_in[  63: 32] <= PWDATA;
                    8'h0F: if (!busy || meas_alg_sel == 2'b10) reg_data_in[  95: 64] <= PWDATA;
                    8'h10: if (!busy || meas_alg_sel == 2'b10) reg_data_in[ 127: 96] <= PWDATA;
                    8'h11: if (!busy) reg_tag_in[  31:  0] <= PWDATA;
                    8'h12: if (!busy) reg_tag_in[  63: 32] <= PWDATA;
                    8'h13: if (!busy) reg_tag_in[  95: 64] <= PWDATA;
                    8'h14: if (!busy) reg_tag_in[ 127: 96] <= PWDATA;
                    8'h15: if (!busy) reg_ad_len   <= PWDATA[7:0];
                    8'h16: if (!busy) reg_data_len <= PWDATA[7:0];
                    8'h17: if (!busy) reg_msg_len  <= PWDATA[7:0];
                    8'h19: begin
                        msg_ack_pulse <= PWDATA[0];
                        ad_ack_pulse  <= PWDATA[1];
                    end
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // Core 0: TinyJAMBU   (nonce=96b, tag=64b)
    // -------------------------------------------------------
    wire [127:0] tj_data_out;
    wire [63:0]  tj_tag_out;
    wire         tj_valid, tj_done;

    tinyjambu_core u_tinyjambu (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk        (PCLK),
        .rst_n      (PRESETn),
        .ena        (start_pulse && (reg_alg_sel == 2'b00)),
        .sel_type   (reg_decrypt ? 3'b001 : 3'b000),
        .key        (reg_key),
        .nonce      (reg_nonce[95:0]),
        .ad         (reg_ad),
        .ad_length  (reg_ad_len[4:0]),
        .data_in    (reg_data_in),
        .data_length(reg_data_len[4:0]),
        .tag_in     (reg_tag_in[63:0]),
        .data_out   (tj_data_out),
        .tag        (tj_tag_out),
        .valid      (tj_valid),
        .done       (tj_done)
    );

    // -------------------------------------------------------
    // Core 1: Xoodyak   (nonce=128b, tag=128b)
    // -------------------------------------------------------
    wire [127:0] xd_data_out, xd_tag_out;
    wire         xd_valid, xd_done;

    xoodyakcore u_xoodyak (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk        (PCLK),
        .rst_n      (PRESETn),
        .ena        (start_pulse && (reg_alg_sel == 2'b01)),
        .restart    (1'b0),
        .sel_type   (reg_decrypt ? 2'b10 : 2'b01),
        .key        (reg_key),
        .nonce      (reg_nonce),
        .ad         (reg_ad),
        .ad_length  (reg_ad_len[4:0]),
        .data_length(reg_data_len[4:0]),
        .data_in    (reg_data_in),
        .tag_in     (reg_tag_in),
        .data_out   (xd_data_out),
        .tag        (xd_tag_out),
        .valid      (xd_valid),
        .done       (xd_done)
    );

    // -------------------------------------------------------
    // Core 2: GIFT-COFB  (nonce=128b, tag=128b, req/ack)
    // -------------------------------------------------------
    wire [127:0] gf_data_out, gf_tag_out;
    wire         gf_valid, gf_done;
    wire         gf_ad_req, gf_msg_req, gf_data_out_valid;

    cofb_core u_cofb (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk          (PCLK),
        .rst_n        (PRESETn),
        .start        (start_pulse && (reg_alg_sel == 2'b10)),
        .decrypt_mode (reg_decrypt),
        .key          (reg_key),
        .nonce        (reg_nonce),
        .ad_data      (reg_ad),
        .ad_total_len (reg_ad_len),
        .ad_ack       (ad_ack_pulse),
        .msg_data     (reg_data_in),
        .msg_total_len(reg_msg_len),
        .msg_ack      (msg_ack_pulse),
        .tag_in       (reg_tag_in),
        .ad_req       (gf_ad_req),
        .msg_req      (gf_msg_req),
        .data_out     (gf_data_out),
        .data_out_valid(gf_data_out_valid),
        .tag_out      (gf_tag_out),
        .valid        (gf_valid),
        .done         (gf_done)
    );

    // -------------------------------------------------------
    // Output mux — select based on meas_alg_sel (the op that was last
    // *started*), not the live alg_sel, so a ctrl write that changes
    // alg_sel while an op is still busy can't retarget the readback.
    // -------------------------------------------------------
    wire [127:0] sel_data_out = (meas_alg_sel == 2'b00) ? tj_data_out :
                                (meas_alg_sel == 2'b01) ? xd_data_out : gf_data_out;
    wire [127:0] sel_tag_out  = (meas_alg_sel == 2'b00) ? {64'b0, tj_tag_out} :
                                (meas_alg_sel == 2'b01) ? xd_tag_out  : gf_tag_out;

    // -------------------------------------------------------
    // Per-operation cycle measurement
    // Counts core cycles from start acceptance to done pulse.
    // (meas_active/meas_alg_sel/meas_decrypt are declared up in the
    // control-register section above, ahead of their first use.)
    // -------------------------------------------------------
    reg [31:0] meas_cycles_cur;
    reg [31:0] meas_cycles_last;
    reg [31:0] tj_cycles_last, xd_cycles_last, gf_cycles_last;

    wire meas_done  = (meas_alg_sel == 2'b00) ? tj_done  :
                       (meas_alg_sel == 2'b01) ? xd_done  : gf_done;
    wire meas_valid = (meas_alg_sel == 2'b00) ? tj_valid :
                       (meas_alg_sel == 2'b01) ? xd_valid : gf_valid;

    // Unverified plaintext oracle: for non-GIFT-COFB decrypt ops, hide
    // data_out until the op is done AND the tag has verified valid.
    // GIFT-COFB streams plaintext blocks out before its final tag check,
    // so it is exempt — firmware must discard COFB plaintext output if
    // the final `valid` bit comes back 0.
    wire data_out_blank = (meas_alg_sel != 2'b10) && meas_decrypt &&
                          !(!meas_active && done_sticky && valid_sticky);

    // -------------------------------------------------------
    // Done / valid / err sticky registers — follow the op that was
    // actually started (meas_alg_sel/meas_active), not the live ctrl
    // register, so a ctrl write mid-operation can't corrupt the result
    // of the op already in flight.
    // (done_sticky/valid_sticky/err_sticky are declared up in the
    // control-register section above, ahead of their first use in
    // data_out_blank.)
    // -------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            done_sticky  <= 1'b0;
            valid_sticky <= 1'b0;
            err_sticky   <= 1'b0;
        end else if (start_pulse) begin
            done_sticky  <= 1'b0;
            valid_sticky <= 1'b0;
            err_sticky   <= 1'b0;      // a successful start clears err
        end else if (start_blocked) begin
            done_sticky  <= 1'b1;      // let a `while(!done)` poll exit
            valid_sticky <= 1'b0;
            err_sticky   <= 1'b1;
        end else if (meas_active && meas_done) begin
            done_sticky  <= 1'b1;
            valid_sticky <= meas_valid;
        end
    end

    // gf_data_valid_sticky has its own lifetime, separate from the block
    // above: a data_out_valid pulse landing on the same cycle as `done`
    // must not be lost by sharing that always block.
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            gf_data_valid_sticky <= 1'b0;
        else if (start_pulse)
            gf_data_valid_sticky <= 1'b0;
        else if (apb_wr && wi == 8'h19 && PWDATA[2])
            gf_data_valid_sticky <= 1'b0;
        else if (gf_data_out_valid)
            gf_data_valid_sticky <= 1'b1;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            meas_active      <= 1'b0;
            meas_alg_sel     <= 2'b00;
            meas_decrypt     <= 1'b0;
            meas_cycles_cur  <= 32'd0;
            meas_cycles_last <= 32'd0;
            tj_cycles_last   <= 32'd0;
            xd_cycles_last   <= 32'd0;
            gf_cycles_last   <= 32'd0;
        end else if (start_pulse) begin
            meas_active     <= 1'b1;
            meas_alg_sel    <= reg_alg_sel;
            meas_decrypt    <= reg_decrypt;
            meas_cycles_cur <= 32'd0;
        end else if (meas_active) begin
            meas_cycles_cur <= meas_cycles_cur + 32'd1;
            if (meas_done) begin
                meas_active      <= 1'b0;
                meas_cycles_last <= meas_cycles_cur + 32'd1;
                case (meas_alg_sel)
                    2'b00: tj_cycles_last <= meas_cycles_cur + 32'd1;
                    2'b01: xd_cycles_last <= meas_cycles_cur + 32'd1;
                    default: gf_cycles_last <= meas_cycles_cur + 32'd1;
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // APB read mux (combinational)
    // -------------------------------------------------------
    always @(*) begin
        if (PADDR[11:10] != 2'b00) begin
            PRDATA = 32'h0;
        end else begin
            case (wi)
                8'h00: PRDATA = {23'b0, err_sticky, valid_sticky, done_sticky,
                                 meas_active, 1'b0, reg_decrypt, 1'b0, reg_alg_sel};
                8'h01: PRDATA = 32'h0;   // key is write-only
                8'h02: PRDATA = 32'h0;
                8'h03: PRDATA = 32'h0;
                8'h04: PRDATA = 32'h0;
                8'h05: PRDATA = reg_nonce[  31:  0];
                8'h06: PRDATA = reg_nonce[  63: 32];
                8'h07: PRDATA = reg_nonce[  95: 64];
                8'h08: PRDATA = reg_nonce[ 127: 96];
                8'h09: PRDATA = reg_ad[   31:  0];
                8'h0A: PRDATA = reg_ad[   63: 32];
                8'h0B: PRDATA = reg_ad[   95: 64];
                8'h0C: PRDATA = reg_ad[  127: 96];
                8'h0D: PRDATA = reg_data_in[  31:  0];
                8'h0E: PRDATA = reg_data_in[  63: 32];
                8'h0F: PRDATA = reg_data_in[  95: 64];
                8'h10: PRDATA = reg_data_in[ 127: 96];
                8'h11: PRDATA = reg_tag_in[  31:  0];
                8'h12: PRDATA = reg_tag_in[  63: 32];
                8'h13: PRDATA = reg_tag_in[  95: 64];
                8'h14: PRDATA = reg_tag_in[ 127: 96];
                8'h15: PRDATA = {24'b0, reg_ad_len};
                8'h16: PRDATA = {24'b0, reg_data_len};
                8'h17: PRDATA = {24'b0, reg_msg_len};
                8'h18: PRDATA = {27'b0,
                                 (valid_sticky && meas_alg_sel == 2'b10),
                                 (done_sticky  && meas_alg_sel == 2'b10),
                                 gf_ad_req, gf_msg_req, gf_data_valid_sticky};
                8'h19: PRDATA = 32'h0;
                8'h20: PRDATA = data_out_blank ? 32'h0 : sel_data_out[  31:  0];
                8'h21: PRDATA = data_out_blank ? 32'h0 : sel_data_out[  63: 32];
                8'h22: PRDATA = data_out_blank ? 32'h0 : sel_data_out[  95: 64];
                8'h23: PRDATA = data_out_blank ? 32'h0 : sel_data_out[ 127: 96];
                8'h24: PRDATA = meas_decrypt ? 32'h0 : sel_tag_out[  31:  0];
                8'h25: PRDATA = meas_decrypt ? 32'h0 : sel_tag_out[  63: 32];
                8'h26: PRDATA = meas_decrypt ? 32'h0 : sel_tag_out[  95: 64];
                8'h27: PRDATA = meas_decrypt ? 32'h0 : sel_tag_out[ 127: 96];
                8'h28: PRDATA = {29'b0, meas_alg_sel, meas_active};
                8'h29: PRDATA = meas_cycles_cur;
                8'h2A: PRDATA = meas_cycles_last;
                8'h2B: PRDATA = tj_cycles_last;
                8'h2C: PRDATA = xd_cycles_last;
                8'h2D: PRDATA = gf_cycles_last;
                default: PRDATA = 32'h0;
            endcase
        end
    end

endmodule
