// ============================================================
// xoodyak.v -- Xoodyak AEAD core (Xoodoo permutation + wrapper)
// ============================================================
// All sub-modules of this cipher in one file, in dependency order
// (leaf modules first, top core last).  Original per-module file
// names are preserved in the FILE: banners below.
//
// Consolidates the former rtl/crypto/xoodyak/*.v directory and
// the memory-mapped wrapper (aead_mmap_wrapper.v) remain separate.
// ============================================================

// ======================================================================
// FILE: xoodyak\xoodoo_rc.v
// ======================================================================
//--------------------------------------------------------------------------------
// Round constant computation module
// Matches xoodoo_rc.vhd functionality
//--------------------------------------------------------------------------------
module xoodoo_rc(
    state_in,
    state_out,
    rc
);
    input  [5:0] state_in;
    output [5:0] state_out;
    output [31:0] rc;
    
    wire [2:0] si;
    wire [3:0] temp_new_si;
    wire [2:0] new_si;
    wire [2:0] qi;
    wire [2:0] new_qi;
    wire [3:0] qi_plus_t3;
    
    assign si = state_in[2:0];
    assign temp_new_si = {1'b0, si} + {si[1:0], si[2]};
    assign new_si = temp_new_si[2:0] + {2'b0, temp_new_si[3]};
    assign state_out[2:0] = new_si;
    
    assign qi = state_in[5:3];
    assign new_qi[0] = qi[2];
    assign new_qi[1] = qi[0] ^ qi[2];
    assign new_qi[2] = qi[1];
    assign state_out[5:3] = new_qi;
    
    assign qi_plus_t3 = {1'b1, qi};
    
    // RC value computation based on si
    // VHDL: rc(0) is LSB, rc(9) is MSB of rc[9:0]
    // For si="001": rc(0)=0, rc(1)=qi_plus_t3(0), rc(2)=qi_plus_t3(1), 
    //               rc(3)=qi_plus_t3(2), rc(4)=qi_plus_t3(3), rc(9:5)=0
    // In Verilog: rc[0]=LSB, rc[9]=MSB
    // So rc[9:0] = {rc[9], rc[8], ..., rc[1], rc[0]} = {5'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 1'b0}
    assign rc[31:10] = 22'h0;
    assign rc[9:0] = (si == 3'b001) ? {5'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 1'b0} :
                     (si == 3'b010) ? {4'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 2'b0} :
                     (si == 3'b011) ? {3'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 3'b0} :
                     (si == 3'b100) ? {2'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 4'b0} :
                     (si == 3'b101) ? {1'b0, qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 5'b0} :
                     (si == 3'b110) ? {qi_plus_t3[3], qi_plus_t3[2], qi_plus_t3[1], qi_plus_t3[0], 6'b0} :
                     10'b0;
    
endmodule


// ======================================================================
// FILE: xoodyak\xoodoo_round.v
// ======================================================================
//--------------------------------------------------------------------------------
// Single round computation module
// Matches xoodoo_round.vhd functionality
// Uses flattened 384-bit vectors for Verilog compatibility
//--------------------------------------------------------------------------------
module xoodoo_round(
    state_in,
    rc,
    state_out
);
    input  [383:0] state_in;
    input  [31:0]  rc;
    output [383:0] state_out;
    
    // Internal arrays for computation
    reg  [31:0] state_array [0:2][0:3];
    reg  [31:0] theta_out [0:2][0:3];
    reg  [31:0] rho_w_out [0:2][0:3];
    reg  [31:0] iota_out [0:2][0:3];
    reg  [31:0] chi_out [0:2][0:3];
    reg  [31:0] rho_e_out [0:2][0:3];
    
    // Theta step: parity and diffusion
    reg  [31:0] P [0:3];
    reg  [31:0] E [0:3];
    reg [2:0] x, y;   // x:0..4, y:0..3 : must hold each loop's exit value
    
    // Unpack input state
    always @(*) begin
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                state_array[y][x] = state_in[128*y + 32*x +: 32];
    end
    
    // Theta: compute parity
    always @(*) begin
        for (x = 0; x < 4; x = x + 1)
            P[x] = state_array[0][x] ^ state_array[1][x] ^ state_array[2][x];
    end
    
    // Theta: compute E[x] = rotl(P[x-1], 5) XOR rotl(P[x-1], 14)
    function [31:0] rotl32;
        input [31:0] val;
        input [4:0]  shift;
        begin
            rotl32 = (val << shift) | (val >> (32 - shift));
        end
    endfunction

    always @(*) begin
        for (x = 0; x < 4; x = x + 1) begin
            E[x] = rotl32(P[(x+3) % 4], 5) ^ rotl32(P[(x+3) % 4], 14);
        end
    end
    
    // Theta: apply E
    always @(*) begin
            for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                theta_out[y][x] = state_array[y][x] ^ E[x];
    end
    
    // Rho west
    always @(*) begin
            for (x = 0; x < 4; x = x + 1) begin
            rho_w_out[0][x] = theta_out[0][x];
            rho_w_out[1][x] = theta_out[1][(x+3) % 4];
            rho_w_out[2][x] = rotl32(theta_out[2][x], 11);
        end
    end
    
    // Iota: add round constant
    always @(*) begin
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                if (y == 0 && x == 0)
                    iota_out[y][x] = rho_w_out[y][x] ^ rc;
                else
                    iota_out[y][x] = rho_w_out[y][x];
    end
    
    // Chi: non-linear layer
    reg [31:0] B0, B1, B2;
    always @(*) begin
        for (x = 0; x < 4; x = x + 1) begin
            B0 = (~iota_out[1][x]) & iota_out[2][x];
            B1 = (~iota_out[2][x]) & iota_out[0][x];
            B2 = (~iota_out[0][x]) & iota_out[1][x];
            chi_out[0][x] = iota_out[0][x] ^ B0;
            chi_out[1][x] = iota_out[1][x] ^ B1;
            chi_out[2][x] = iota_out[2][x] ^ B2;
        end
    end
    
    // Rho east
    always @(*) begin
        for (x = 0; x < 4; x = x + 1) begin
            rho_e_out[0][x] = chi_out[0][x];
            rho_e_out[1][x] = rotl32(chi_out[1][x], 1);
            rho_e_out[2][x] = rotl32(chi_out[2][(x+2) % 4], 8);
        end
    end
    
    // Pack output state - use internal reg then assign to output wire
    reg [383:0] state_out_reg;
    always @(*) begin
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                state_out_reg[128*y + 32*x +: 32] = rho_e_out[y][x];
    end
    
    // Assign internal reg to output wire
    assign state_out = state_out_reg;
    
endmodule


// ======================================================================
// FILE: xoodyak\xoodoo_n_rounds.v
// ======================================================================
//--------------------------------------------------------------------------------
// N rounds computation module
// Uses Verilog generate to instantiate configurable number of rounds
// roundPerCycle parameter controls unrolling (1, 2, 3, 4, 6, or 12)
//--------------------------------------------------------------------------------
module xoodoo_n_rounds(
    state_in,
    state_out,
    rc_state_in,
    rc_state_out
);
    parameter roundPerCycle = 1;
    
    input  [383:0] state_in;
    output [383:0] state_out;
    input  [5:0]   rc_state_in;
    output [5:0]   rc_state_out;
    
    // Internal wires for chaining rounds (roundPerCycle + 1 entries)
    wire [383:0] state_chain [0:roundPerCycle];
    wire [5:0]   rc_chain [0:roundPerCycle];
    wire [31:0]  rc_val [0:roundPerCycle-1];
    
    // Connect inputs to first chain element
    assign state_chain[0] = state_in;
    assign rc_chain[0] = rc_state_in;
    
    // Generate N rounds dynamically based on roundPerCycle parameter
    genvar i;
    generate
        for (i = 0; i < roundPerCycle; i = i + 1) begin : round_gen
            // Round constant generator
            xoodoo_rc rc_inst(
                .state_in(rc_chain[i]),
                .state_out(rc_chain[i+1]),
                .rc(rc_val[i])
            );
            
            // Round computation
            xoodoo_round round_inst(
                .state_in(state_chain[i]),
                .rc(rc_val[i]),
                .state_out(state_chain[i+1])
            );
        end
    endgenerate
    
    // Connect outputs from last chain element
    assign state_out = state_chain[roundPerCycle];
    assign rc_state_out = rc_chain[roundPerCycle];
    
endmodule


// ======================================================================
// FILE: xoodyak\xoodoo.v
// ======================================================================
//--------------------------------------------------------------------------------
// Xoodoo permutation with configurable rounds per cycle
// LUT-OPTIMIZED version:
//   - Write decoder reduced to indices 0..8 (xoodyak never writes beyond 8)
//   - Read mux reduced to indices 0..3 (xoodyak never reads beyond 3)
//   - Domain XOR isolated to word 11
//   - Dead 'done' register removed
//--------------------------------------------------------------------------------

module xoodoo(
    clk_i,
    rst_i,
    start_i,
    state_valid_o,
    init_reg,
    word_in,
    word_index_in,
    word_enable_in,
    domain_i,
    domain_enable_i,
    word_out
);
    // Port declarations
    input               clk_i;
    input               rst_i;
    input               start_i;
    output reg          state_valid_o;
    input               init_reg;
    input      [31:0]   word_in;
    input      [3:0]    word_index_in;  // write: 0..8, read: 0..3 (only [1:0] used for read)
    input               word_enable_in;
    input      [31:0]   domain_i;
    input               domain_enable_i;
    output     [31:0]   word_out;

    // Parameters
    parameter roundPerCycle = 1;
    parameter active_rst    = 1'b1;

    // Internal state: 3 planes x 4 words x 32 bits = 384 bits
    reg  [383:0] reg_value;
    wire [383:0] round_out_state;

    // Round constant state machine (6 bits)
    reg  [5:0]  rc_state_in;
    wire [5:0]  rc_state_out;

    // Control signal
    reg         running;

    // =========================================================================
    // state_with_xor: apply input word + domain XOR BEFORE round computation.
    //   - Only indices 0..8 can receive word_in (xoodyak usage).
    //   - Only index 11 can receive domain_i.
    //   - Indices 9..10 pass through reg_value unchanged.
    // This removes the word_in decoder logic for 3 words and simplifies index 11.
    // =========================================================================
    wire [383:0] state_with_xor;

    genvar i;
    generate
        // Write path: indices 0..8 (covers LOAD_KEY/NONCE/AD/DATA and PAD_NONCE at idx=8)
        for (i = 0; i < 9; i = i + 1) begin : gen_word_xor_write
            assign state_with_xor[i*32 +: 32] =
                reg_value[i*32 +: 32] ^
                ((word_enable_in && (word_index_in == i[3:0])) ? word_in : 32'h0);
        end
        // Indices 9..10: no write, no domain -> pass-through
        for (i = 9; i < 11; i = i + 1) begin : gen_word_xor_passthrough
            assign state_with_xor[i*32 +: 32] = reg_value[i*32 +: 32];
        end
    endgenerate

    // Index 11: domain XOR only (no word_in path)
    assign state_with_xor[11*32 +: 32] =
        reg_value[11*32 +: 32] ^ (domain_enable_i ? domain_i : 32'h0);

    // N rounds computation module
    xoodoo_n_rounds #(.roundPerCycle(roundPerCycle)) rounds_inst(
        .state_in(state_with_xor),
        .state_out(round_out_state),
        .rc_state_in(rc_state_in),
        .rc_state_out(rc_state_out)
    );

    // =========================================================================
    // State register: combined reset paths; gated update saves dynamic power
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i == active_rst || init_reg == 1'b1) begin
            reg_value <= 384'h0;
        end else if (running == 1'b1 || start_i == 1'b1) begin
            reg_value <= round_out_state;
        end else if (word_enable_in || domain_enable_i) begin
            // Only update if there's an actual XOR input to apply
            reg_value <= state_with_xor;
        end
        // else: hold
    end

    // =========================================================================
    // Word output: only positions 0..3 needed (xoodyak DEC absorb + tag/data/hash
    // extraction all use word_cnt_r = 0..3). 4:1 mux instead of 12:1.
    // =========================================================================
    assign word_out = reg_value[word_index_in[1:0]*32 +: 32];

    // =========================================================================
    // Main FSM controller (dead 'done' register removed)
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i == active_rst) begin
            running       <= 1'b0;
            rc_state_in   <= 6'b011011;  // Initial RC state
            state_valid_o <= 1'b0;
        end else begin
            if (rc_state_out == 6'b010011) begin
                // Permutation complete
                running       <= 1'b0;
                rc_state_in   <= 6'b011011;
                state_valid_o <= 1'b1;
            end else if (start_i == 1'b1 || running == 1'b1) begin
                // Start or continue permutation
                running       <= 1'b1;
                rc_state_in   <= rc_state_out;
                state_valid_o <= 1'b0;
            end
            // else: hold state_valid_o (stays high after done, until next start)
        end
    end

endmodule

// ======================================================================
// FILE: xoodyak\xoodyakcore.v
// ======================================================================
//--------------------------------------------------------------------------------
// @file       xoodyak_keyed.v
// @brief      Xoodyak cipher (Keyed-only: AEAD Enc/Dec) - LUT + FF optimized v2
// @description Keyed-only variant: AEAD Enc/Dec with AD, Tag verification.
//              Hash mode removed for area optimization.
//
// FF optimizations vs original v1:
//   Round 1 (~−290 FF):
//   - domain_r[31:0]        removed → combinational constant                  (−32 FF)
//   - word_cnt_r[3:0]       narrowed → [2:0] (max value = 7)                  (−1 FF)
//   - data_out_r, tag_r     removed → write directly to output ports          (−256 FF)
//   - valid_r               removed → write directly to output port            (−1 FF)
//   Round 2 (~−637 FF net):
//   - key_r, nonce_r, ad_r, data_in_r, tag_in_r removed (inputs held stable)  (−640 FF)
//   - sel_type_r[1:0]       → sel_dec_r (1 bit: 0=ENC, 1=DEC)                 (−1 FF)
//   - ad/data_word_cnt_max_r added to simplify FSM comparisons                 (+4 FF)
//
// LUT optimizations:
//   Round 1 (retained):
//   - Shared XOR for data_out; shared != comparator for tag verify
//   Round 2 (new):
//   - Barrel shifters → 4:1 mux for pad_word (shared, one mux for both PAD states)
//   - Precomputed word_cnt_max → 2-bit register compare replaces 5-bit add/shift/sub
//   - Redundant valid=1 in S_DONE/ENC removed
//   - FSM forced to sequential (binary) encoding (prevents Vivado one-hot auto-select)
//
// IMPORTANT: key, nonce, ad, data_in, tag_in must remain stable from ena to done.
//--------------------------------------------------------------------------------


module xoodyakcore (
`ifdef USE_POWER_PINS
    inout wire          VPWR,
    inout wire          VGND,
`endif
    // Clock and Reset
    input  wire         clk,
    input  wire         rst_n,              // Active low reset

    // Control
    input  wire         ena,                // Enable - start processing
    input  wire         restart,            // Restart for new encryption
    input  wire [1:0]   sel_type,           // Mode: 01=Encrypt, 10=Decrypt

    // Inputs (must be held stable from ena to done)
    input  wire [127:0] key,                // 128-bit key
    input  wire [127:0] nonce,              // 128-bit nonce
    input  wire [127:0] ad,                 // 128-bit Associated Data
    input  wire [4:0]   ad_length,          // AD length in bytes (0-16)
    input  wire [4:0]   data_length,        // Data length in bytes (0-16)
    input  wire [127:0] data_in,            // Data input (PT/CT)
    input  wire [127:0] tag_in,             // Tag for verification (decrypt)

    // Outputs
    output reg          valid,              // Tag verification result
    output reg  [127:0] tag,                // 128-bit tag output
    output reg  [127:0] data_out,           // CT/PT output
    output reg          done                // Done signal
  );

  // =========================================================================
  // Parameters
  // =========================================================================
  parameter roundsPerCycle = 1;

  parameter CCW        = 32;
  parameter KEY_WORDS  = 4;
  parameter NPUB_WORDS = 4;
  parameter TAG_WORDS  = 4;
  parameter AD_WORDS   = 4;

  // Mode constants
  localparam [1:0] MODE_AEAD_ENC = 2'b01;
  localparam [1:0] MODE_AEAD_DEC = 2'b10;

  // Domain constants
  localparam [31:0] DOMAIN_ABSORB_KEY       = 32'h02000000;
  localparam [31:0] DOMAIN_ABSORB           = 32'h03000000;
  localparam [31:0] DOMAIN_SQUEEZE          = 32'h40000000;
  localparam [31:0] DOMAIN_CRYPT            = 32'h80000000;
  localparam [31:0] PADD_01_KEY_NONCE       = {16'h0, 1'b1, 3'h0, 1'b1, 4'h0};
  // Precomputed: DOMAIN_ABSORB ^ DOMAIN_CRYPT = 32'h83000000
  localparam [31:0] DOMAIN_ABSORB_XOR_CRYPT = DOMAIN_ABSORB ^ DOMAIN_CRYPT;

  // =========================================================================
  // FSM States
  // OPT-5: Force binary (sequential) encoding.
  //   Prevents Vivado from auto-selecting one-hot which would cost +10 FF
  //   for 14 states (one-hot needs 14 FF vs binary's 4 FF).
  // =========================================================================
  (* fsm_encoding = "sequential" *) reg [3:0] state_r;
  reg [3:0] state_next;

  localparam [3:0] S_IDLE        = 4'd0,
             S_LOAD_KEY          = 4'd1,
             S_LOAD_NONCE        = 4'd2,
             S_PAD_NONCE         = 4'd3,
             S_PERM_NONCE        = 4'd4,
             S_LOAD_AD           = 4'd5,
             S_PAD_AD            = 4'd6,
             S_PERM_AD           = 4'd7,
             S_LOAD_DATA         = 4'd8,
             S_PAD_DATA          = 4'd9,
             S_PERM_DATA         = 4'd10,
             S_EXTRACT_TAG       = 4'd11,
             S_VERIFY_TAG        = 4'd12,
             S_DONE              = 4'd13;

  // =========================================================================
  // Registers
  // =========================================================================
  // FF round-1 OPT-B: [2:0] — max counter value = 7 fits in 3 bits
  reg [2:0]   word_cnt_r;

  // Control latches (small scalars — must be registered)
  reg [4:0]   ad_length_r, data_length_r;

  // OPT-3: 1-bit mode register: 0 = ENC, 1 = DEC (was sel_type_r[1:0])
  reg         sel_dec_r;

  // OPT-2: Precomputed word count ceilings — registered at ena time.
  //   Replaces the combinational expression ((length + 3) >> 2) - 1
  //   which required a 5-bit adder + shifter + subtractor in the FSM path.
  //   Formula: ceil(length/4) - 1 = (length - 1) >> 2   (valid for length >= 1)
  //   Range: 0..3 → fits in 2 bits.
  reg [1:0]   ad_word_cnt_max_r;
  reg [1:0]   data_word_cnt_max_r;

  // OPT-6+7: key_r, nonce_r, ad_r, data_in_r, tag_in_r REMOVED.
  //   All 128-bit input ports are used directly (held stable ena→done).

  // Internal reset (active high for xoodoo)
  wire rst = ~rst_n;

  // =========================================================================
  // Xoodoo Interface
  // =========================================================================
  reg         xoodoo_start_next;
  reg         xoodoo_start_r;
  reg         xoodoo_init;
  reg  [31:0] xoodoo_word_in;
  reg  [3:0]  xoodoo_word_idx;
  reg         xoodoo_word_en;
  reg  [31:0] xoodoo_domain;
  reg         xoodoo_domain_en;
  wire        xoodoo_valid;
  wire [31:0] xoodoo_word_out;

  // Delay start by one cycle so word/domain XOR is clocked in before permutation
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      xoodoo_start_r <= 1'b0;
    else if (restart)
      xoodoo_start_r <= 1'b0;
    else
      xoodoo_start_r <= xoodoo_start_next;
  end

  xoodoo #(.roundPerCycle(roundsPerCycle)) u_xoodoo (
           .clk_i(clk),
           .rst_i(rst),
           .start_i(xoodoo_start_r),
           .state_valid_o(xoodoo_valid),
           .init_reg(xoodoo_init),
           .word_in(xoodoo_word_in),
           .word_index_in(xoodoo_word_idx),
           .word_enable_in(xoodoo_word_en),
           .domain_i(xoodoo_domain),
           .domain_enable_i(xoodoo_domain_en),
           .word_out(xoodoo_word_out)
         );

  // =========================================================================
  // Byte swap (wire routing — zero LUT)
  // =========================================================================
  function [31:0] byte_swap;
    input [31:0] word;
    begin
      byte_swap = {word[7:0], word[15:8], word[23:16], word[31:24]};
    end
  endfunction

  function [31:0] get_word;
    input [127:0] data;
    input [1:0] idx;
    begin
      case (idx)
        2'd0: get_word = byte_swap(data[127:96]);
        2'd1: get_word = byte_swap(data[95:64]);
        2'd2: get_word = byte_swap(data[63:32]);
        2'd3: get_word = byte_swap(data[31:0]);
      endcase
    end
  endfunction

  // =========================================================================
  // Shared datapath nets
  // OPT-7: data_in and tag_in ports used directly (no latch)
  // =========================================================================
  wire [31:0] data_in_word = get_word(data_in, word_cnt_r[1:0]);
  wire [31:0] data_xor     = xoodoo_word_out ^ data_in_word;
  wire [31:0] data_xor_swp = byte_swap(data_xor);

  // Single 4:1 mux for tag_in word selection (tag_in port used directly)
  reg [31:0] tag_in_slice;
  always @(*) begin
    case (word_cnt_r[1:0])
      2'd0:    tag_in_slice = tag_in[127:96];
      2'd1:    tag_in_slice = tag_in[95:64];
      2'd2:    tag_in_slice = tag_in[63:32];
      default: tag_in_slice = tag_in[31:0];
    endcase
  end

  // =========================================================================
  // OPT-1: Pad byte word — 4:1 mux replacing two barrel shifters
  //
  // Old form (each ≈16–20 LUT as a barrel shifter):
  //   32'h01 << ({ad_length_r[1:0], 3'b000})
  //   32'h01 << ({data_length_r[1:0], 3'b000})
  //
  // New form: shared 4:1 mux (≈2–4 LUT total for both PAD states)
  //   The only 4 possible values: byte position 0/1/2/3 within a 32-bit word.
  // =========================================================================
  wire [1:0] pad_sel = (state_r == S_PAD_AD) ? ad_length_r[1:0]
                                              : data_length_r[1:0];
  reg [31:0] pad_word;
  always @(*) begin
    case (pad_sel)
      2'b00: pad_word = 32'h00000001;   // byte 0
      2'b01: pad_word = 32'h00000100;   // byte 1
      2'b10: pad_word = 32'h00010000;   // byte 2
      2'b11: pad_word = 32'h01000000;   // byte 3
    endcase
  end

  // =========================================================================
  // State Machine
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      state_r <= S_IDLE;
    else if (restart)
      state_r <= S_IDLE;
    else
      state_r <= state_next;
  end

  always @(*)
  begin
    state_next = state_r;

    case (state_r)
      S_IDLE:
        if (ena)
          state_next = S_LOAD_KEY;

      S_LOAD_KEY:
        if (word_cnt_r == KEY_WORDS - 1)
          state_next = S_LOAD_NONCE;

      S_LOAD_NONCE:
        if (word_cnt_r == KEY_WORDS + NPUB_WORDS - 1)
          state_next = S_PAD_NONCE;

      S_PAD_NONCE:
        state_next = S_PERM_NONCE;

      S_PERM_NONCE:
        if (xoodoo_valid && !xoodoo_start_r)
        begin
          if (ad_length_r > 0)
            state_next = S_LOAD_AD;
          else
            state_next = S_PAD_AD;
        end

      S_LOAD_AD:
      begin
        // OPT-2: simple 2-bit register compare
        //   was: ((ad_length_r + 3) >> 2) - 1  (adder + shifter + subtractor)
        if (word_cnt_r >= {1'b0, ad_word_cnt_max_r} || word_cnt_r == AD_WORDS - 1)
          state_next = S_PAD_AD;
      end

      S_PAD_AD:
        state_next = S_PERM_AD;

      S_PERM_AD:
        if (xoodoo_valid && !xoodoo_start_r)
        begin
          if (data_length_r > 0)
            state_next = S_LOAD_DATA;
          else
            state_next = S_PAD_DATA;
        end

      S_LOAD_DATA:
      begin
        // OPT-2: simple 2-bit register compare
        //   was: ((data_length_r + 3) >> 2) - 1
        if (word_cnt_r >= {1'b0, data_word_cnt_max_r} || word_cnt_r == 3)
          state_next = S_PAD_DATA;
      end

      S_PAD_DATA:
        state_next = S_PERM_DATA;

      S_PERM_DATA:
        if (xoodoo_valid && !xoodoo_start_r)
        begin
          // OPT-3: sel_dec_r single-bit compare (was 2-bit sel_type_r == MODE_AEAD_ENC)
          if (!sel_dec_r)
            state_next = S_EXTRACT_TAG;
          else
            state_next = S_VERIFY_TAG;
        end

      S_EXTRACT_TAG:
        if (word_cnt_r == TAG_WORDS - 1)
          state_next = S_DONE;

      S_VERIFY_TAG:
        if (word_cnt_r == TAG_WORDS - 1)
          state_next = S_DONE;

      S_DONE:
        state_next = S_IDLE;

      default:
        state_next = S_IDLE;
    endcase
  end

  // =========================================================================
  // Word Counter (3-bit)
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      word_cnt_r <= 0;
    else if (restart)
      word_cnt_r <= 0;
    else
    begin
      case (state_r)
        S_IDLE, S_PAD_NONCE, S_PAD_AD, S_PAD_DATA,
        S_PERM_NONCE, S_PERM_AD, S_PERM_DATA, S_DONE:
          word_cnt_r <= 0;

        S_LOAD_KEY, S_LOAD_NONCE, S_LOAD_AD, S_LOAD_DATA,
        S_EXTRACT_TAG, S_VERIFY_TAG:
          word_cnt_r <= word_cnt_r + 1;

        default:
          word_cnt_r <= word_cnt_r;
      endcase
    end
  end

  // =========================================================================
  // Latch Control Inputs
  //
  // OPT-6+7: 128-bit data inputs (key/nonce/ad/data_in/tag_in) no longer
  //   latched — ports are used directly throughout. Only small control
  //   scalars are registered.
  //
  // OPT-3: sel_dec_r (1-bit) replaces sel_type_r (2-bit)
  // OPT-2: word_cnt_max precomputed from raw ports at ena pulse
  //   Formula: (length - 1) >> 2  gives ceil(length/4) - 1 for length >= 1.
  //   These registers are only read when the respective length > 0 (FSM
  //   bypasses S_LOAD_AD/DATA when length == 0), so no special-casing needed.
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      ad_length_r         <= 5'd0;
      data_length_r       <= 5'd0;
      sel_dec_r           <= 1'b0;
      ad_word_cnt_max_r   <= 2'd0;
      data_word_cnt_max_r <= 2'd0;
    end
    else if (restart)
    begin
      ad_length_r         <= 5'd0;
      data_length_r       <= 5'd0;
      sel_dec_r           <= 1'b0;
      ad_word_cnt_max_r   <= 2'd0;
      data_word_cnt_max_r <= 2'd0;
    end
    else if (state_r == S_IDLE && ena)
    begin
      ad_length_r         <= ad_length;
      data_length_r       <= data_length;
      sel_dec_r           <= (sel_type == MODE_AEAD_DEC);
      ad_word_cnt_max_r   <= (ad_length   - 1) >> 2;   // read from port
      data_word_cnt_max_r <= (data_length - 1) >> 2;   // read from port
    end
  end

  // =========================================================================
  // Xoodoo Control
  // OPT-1: pad_word mux used in S_PAD_AD and S_PAD_DATA
  // OPT-6: key, nonce, ad ports used directly (no _r suffix)
  // OPT-7: data_in_word already uses data_in port
  // =========================================================================
  always @(*)
  begin
    xoodoo_init       = 1'b0;
    xoodoo_start_next = 1'b0;
    xoodoo_word_in    = 32'b0;
    xoodoo_word_idx   = {1'b0, word_cnt_r};   // zero-extend 3→4 bit
    xoodoo_word_en    = 1'b0;
    xoodoo_domain     = 32'b0;
    xoodoo_domain_en  = 1'b0;

    case (state_r)
      S_IDLE:
        if (ena)
          xoodoo_init = 1'b1;

      S_LOAD_KEY:
      begin
        xoodoo_word_in  = get_word(key, word_cnt_r[1:0]);   // port direct
        xoodoo_word_idx = {1'b0, word_cnt_r};
        xoodoo_word_en  = 1'b1;
      end

      S_LOAD_NONCE:
      begin
        xoodoo_word_in  = get_word(nonce, word_cnt_r[1:0]); // port direct
        xoodoo_word_idx = {1'b0, word_cnt_r};
        xoodoo_word_en  = 1'b1;
      end

      S_PAD_NONCE:
      begin
        xoodoo_word_in    = PADD_01_KEY_NONCE;
        xoodoo_word_idx   = KEY_WORDS + NPUB_WORDS;          // 4'b1000 = 8
        xoodoo_word_en    = 1'b1;
        xoodoo_domain     = DOMAIN_ABSORB_KEY;
        xoodoo_domain_en  = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      S_LOAD_AD:
      begin
        xoodoo_word_in  = get_word(ad, word_cnt_r[1:0]);    // port direct
        xoodoo_word_idx = {1'b0, word_cnt_r};
        xoodoo_word_en  = 1'b1;
      end

      S_PAD_AD:
      begin
        xoodoo_word_in    = pad_word;                        // OPT-1: shared mux
        xoodoo_word_idx   = ad_length_r >> 2;               // word index of padding
        xoodoo_word_en    = 1'b1;
        xoodoo_domain     = DOMAIN_ABSORB_XOR_CRYPT;
        xoodoo_domain_en  = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      S_LOAD_DATA:
      begin
        // OPT-3: sel_dec_r (was: sel_type_r == MODE_AEAD_DEC)
        // data_in_word uses data_in port directly (OPT-7)
        if (sel_dec_r)
          xoodoo_word_in = data_xor;       // DEC: absorb PT = state XOR CT
        else
          xoodoo_word_in = data_in_word;   // ENC: absorb PT directly
        xoodoo_word_idx = {1'b0, word_cnt_r};
        xoodoo_word_en  = 1'b1;
      end

      S_PAD_DATA:
      begin
        xoodoo_word_in    = pad_word;                        // OPT-1: shared mux
        xoodoo_word_idx   = data_length_r >> 2;
        xoodoo_word_en    = 1'b1;
        xoodoo_domain     = DOMAIN_SQUEEZE;
        xoodoo_domain_en  = 1'b1;
        xoodoo_start_next = 1'b1;
      end

      default: begin end
    endcase
  end

  // =========================================================================
  // Collect Output Data (Encrypt/Decrypt)
  // Write directly to output port data_out (no intermediate data_out_r)
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      data_out <= 128'b0;
    else if (restart)
      data_out <= 128'b0;
    else if (state_r == S_LOAD_DATA)
    begin
      case (word_cnt_r[1:0])
        2'd0:    data_out[127:96] <= data_xor_swp;
        2'd1:    data_out[95:64]  <= data_xor_swp;
        2'd2:    data_out[63:32]  <= data_xor_swp;
        default: data_out[31:0]   <= data_xor_swp;
      endcase
    end
  end

  // =========================================================================
  // Collect Tag Output
  // Write directly to output port tag (no intermediate tag_r)
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      tag <= 128'b0;
    else if (restart)
      tag <= 128'b0;
    else if (state_r == S_EXTRACT_TAG || state_r == S_VERIFY_TAG)
    begin
      case (word_cnt_r[1:0])
        2'd0:    tag[127:96] <= byte_swap(xoodoo_word_out);
        2'd1:    tag[95:64]  <= byte_swap(xoodoo_word_out);
        2'd2:    tag[63:32]  <= byte_swap(xoodoo_word_out);
        default: tag[31:0]   <= byte_swap(xoodoo_word_out);
      endcase
    end
  end

  // =========================================================================
  // Tag Verification — valid output
  // Write directly to output port valid (no intermediate valid_r)
  // OPT-4: S_DONE/ENC branch removed — valid is already 1 at S_DONE for ENC
  //   because: set=1 at S_IDLE+ena, never written again (S_VERIFY_TAG skipped).
  // tag_in used directly from port (OPT-7)
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      valid <= 1'b0;
    else if (restart)
      valid <= 1'b0;
    else if (state_r == S_IDLE && ena)
      valid <= 1'b1;                       // preset to pass; DEC may clear below
    else if (state_r == S_VERIFY_TAG)
    begin
      if (byte_swap(xoodoo_word_out) != tag_in_slice)
        valid <= 1'b0;                     // tag word mismatch → fail
    end
    // OPT-4: no else-if for S_DONE/ENC — redundant, removed
  end

  // =========================================================================
  // Done Output
  // =========================================================================
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      done <= 1'b0;
    else if (restart)
      done <= 1'b0;
    else if (state_r == S_DONE)
      done <= 1'b1;
    else if (state_r == S_IDLE)
      done <= 1'b0;
  end

endmodule
