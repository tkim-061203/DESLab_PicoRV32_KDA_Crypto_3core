// ============================================================
// gift_cofb.v -- GIFT-COFB AEAD core (GIFT-128 block cipher + COFB mode)
// ============================================================
// All sub-modules of this cipher in one file, in dependency order
// (leaf modules first, top core last).  Original per-module file
// names are preserved in the FILE: banners below.
//
// Consolidates the former rtl/crypto/gift_cofb/*.v directory and
// the memory-mapped wrapper (aead_mmap_wrapper.v) remain separate.
// ============================================================

// ======================================================================
// FILE: gift_cofb\double_half_block.v
// ======================================================================
module double_half_block (
    input  [63:0] s,      
    output [63:0] d       
); 
    wire msb;             
    wire [63:0] shifted;  
    wire [7:0] reduction; 
    
    assign msb = s[63];
    assign shifted = s << 1;
    assign reduction = msb ? 8'h1B : 8'h00; // 1b = 27 ( 0001_1011)
    assign d = {shifted[63:8], shifted[7:0] ^ reduction};

endmodule

// ======================================================================
// FILE: gift_cofb\triple_half_block.v
// ======================================================================
module triple_half_block (
    input  [63:0] s,
    output [63:0] d
);
    wire [63:0] tmp;
    double_half_block u_double (
        .s(s),
        .d(tmp)
    );
    assign d = s ^ tmp;
endmodule

// ======================================================================
// FILE: gift_cofb\feedback_G.v
// ======================================================================
module feedback_G (
    input  [127:0] Y_in,
    output [127:0] G_out
);
    wire [63:0] Y1 = Y_in[127:64];  // Y[1] - Upper half
    wire [63:0] Y2 = Y_in[63:0];    // Y[2] - Lower half
    
    // G(Y) = Y[2] || (Y[1] <<< 1)
    assign G_out = {Y2, {Y1[62:0], Y1[63]}};
    
endmodule

// ======================================================================
// FILE: gift_cofb\padding.v
// ======================================================================
module padding (
    input  [127:0] data_in,      
    input  [4:0]   num_bytes,    // Number of valid bytes (0-16) --> 2^5 =32 
    output [127:0] data_out      
);

    reg [127:0] padded_data;
    
    always @(*) begin
        case (num_bytes)
            5'd0: begin
                padded_data = 128'h80000000000000000000000000000000;
            end
            5'd1: begin
                padded_data = {data_in[127:120], 1'b1, 119'b0};
            end
            5'd2: begin
                padded_data = {data_in[127:112], 1'b1, 111'b0};
            end
            5'd3: begin
                padded_data = {data_in[127:104], 1'b1, 103'b0};
            end
            5'd4: begin
                padded_data = {data_in[127:96], 1'b1, 95'b0};
            end
            5'd5: begin
                padded_data = {data_in[127:88], 1'b1, 87'b0};
            end
            5'd6: begin
                padded_data = {data_in[127:80], 1'b1, 79'b0};
            end
            5'd7: begin
                padded_data = {data_in[127:72], 1'b1, 71'b0};
            end
            5'd8: begin
                padded_data = {data_in[127:64], 1'b1, 63'b0};
            end
            5'd9: begin
                padded_data = {data_in[127:56], 1'b1, 55'b0};
            end
            5'd10: begin
                padded_data = {data_in[127:48], 1'b1, 47'b0};
            end
            5'd11: begin
                padded_data = {data_in[127:40], 1'b1, 39'b0};
            end
            5'd12: begin
                padded_data = {data_in[127:32], 1'b1, 31'b0};
            end
            5'd13: begin
                padded_data = {data_in[127:24], 1'b1, 23'b0};
            end
            5'd14: begin
                padded_data = {data_in[127:16], 1'b1, 15'b0};
            end          
            5'd15: begin
                padded_data = {data_in[127:8], 1'b1, 7'b0};
            end            
            5'd16: begin
                padded_data = data_in;
            end           
            default: begin
                padded_data = 128'h0;
            end
        endcase
    end  
    assign data_out = padded_data;

endmodule

// ======================================================================
// FILE: gift_cofb\xor_block.v
// ======================================================================
module xor_block (
    input  [127:0] s1,           // input block s1
    input  [127:0] s2,           // input block s2
    input  [4:0]   no_of_bytes,  
    output [127:0] d              // output block
);
    reg [127:0] result;
    always @(*) begin
        case (no_of_bytes) 
            5'd0:
                result = 128'b0;
            5'd1:
                result = { s1[127:120] ^ s2[127:120], 120'b0 };
            5'd2:
                result = { s1[127:112] ^ s2[127:112], 112'b0 };
            5'd3:
                result = { s1[127:104] ^ s2[127:104], 104'b0 };
            5'd4:
                result = { s1[127:96] ^ s2[127:96], 96'b0 };
            5'd5:
                result = { s1[127:88] ^ s2[127:88], 88'b0 };
            5'd6:
                result = { s1[127:80] ^ s2[127:80], 80'b0 };
            5'd7:
                result = { s1[127:72] ^ s2[127:72], 72'b0 };
            5'd8:
                result = { s1[127:64] ^ s2[127:64], 64'b0 };
            5'd9:
                result = { s1[127:56] ^ s2[127:56], 56'b0 };
            5'd10:
                result = { s1[127:48] ^ s2[127:48], 48'b0 };
            5'd11:
                result = { s1[127:40] ^ s2[127:40], 40'b0 };
            5'd12:
                result = { s1[127:32] ^ s2[127:32], 32'b0 };
            5'd13:
                result = { s1[127:24] ^ s2[127:24], 24'b0 };
            5'd14:
                result = { s1[127:16] ^ s2[127:16], 16'b0 };
            5'd15:
                result = { s1[127:8] ^ s2[127:8], 8'b0 };
            5'd16:
                result = s1 ^ s2;
            default:
                result = 128'b0;
        endcase
    end
    assign d = result;

endmodule


// ======================================================================
// FILE: gift_cofb\xor_topbar_block.v
// ======================================================================
module xor_topbar_block (
    input  [127:0] s1,      // Input block (128-bit)
    input  [63:0]  s2,      // Half block (64-bit) - top bar
    output [127:0] d        // Output block (128-bit)
);
    assign d = {s1[127:64] ^ s2, s1[63:0]};

endmodule

// ======================================================================
// FILE: gift_cofb\pho1.v
// ======================================================================
module pho1 (
    input  [127:0] Y_in,         // chaining value in
    input  [127:0] M_in,         // message / plaintext block
    input  [4:0]   no_of_bytes,  // valid bytes in M
    output [127:0] d        
);

    wire [127:0] G_result;
    wire [127:0] M_padded;
    wire [127:0] tmpM;
    	feedback_G g_inst (
        	.Y_in  (Y_in),
        	.G_out (G_result)
    	);

    	padding pad_inst (
        	.data_in   (M_in),
        	.num_bytes (no_of_bytes),
        	.data_out  (M_padded)
    	);

	xor_block xor_inst (
		.s1(G_result),
		.s2(M_padded),
		.no_of_bytes(5'd16),
		.d(d)
	);
endmodule

// ======================================================================
// FILE: gift_cofb\pho.v
// ======================================================================
module pho (
    input  [127:0] Y,
    input  [127:0] M,
    input  [4:0]   no_of_bytes,
    output [127:0] C,
    output [127:0] X
);
    xor_block xor_inst (
        .s1(Y),
        .s2(M),
        .no_of_bytes(no_of_bytes),
        .d(C)
    );
    pho1 pho1_inst (
        .Y_in(Y),
        .M_in(M),
        .no_of_bytes(no_of_bytes),
        .d(X)
    );
endmodule

// ======================================================================
// FILE: gift_cofb\phoprime.v
// ======================================================================
module phoprime (
    input  [127:0] Y,
    input  [127:0] C,
    input  [4:0]   no_of_bytes,
    output [127:0] M,
    output [127:0] X
);
    xor_block xor_inst (
        .s1(Y),
        .s2(C),
        .no_of_bytes(no_of_bytes),
        .d(M)
    );
    pho1 pho1_inst (
        .Y_in(Y),
        .M_in(M),
        .no_of_bytes(no_of_bytes),
        .d(X)
    );
endmodule

// ======================================================================
// FILE: gift_cofb\gift128_subcells.v
// ======================================================================
// ============================================================
// GIFT-128 SubCells 
// ============================================================
module gift128_subcells (
    input  wire [31:0] S0,
    input  wire [31:0] S1,
    input  wire [31:0] S2,
    input  wire [31:0] S3,
    output reg  [31:0] Z0,
    output reg  [31:0] Z1,
    output reg  [31:0] Z2,
    output reg  [31:0] Z3
);

    reg [31:0] s1_0, s1_1;
    reg [31:0] s2_1, s2_2, s2_3;

    always @(*) begin
        // --- Stage 1: nonlinear mix ---
        s1_1 = S1 ^ (S0 & S2);
        s1_0 = S0 ^ (s1_1 & S3);

        // --- Stage 2: dependency propagation ---
        s2_2 = S2 ^ (S0 | S1);
        s2_3 = S3 ^ s2_2;
        s2_1 = s1_1 ^ s2_3;

        // --- Stage 3 & swap S0<->S3 ---
        Z0 = ~s2_3;
        Z1 = s2_1;
        Z2 = s2_2 ^ (s1_0 & s2_1);
        Z3 = s1_0;
    end

endmodule


// ======================================================================
// FILE: gift_cofb\gift128_permbits.v
// ======================================================================
// ============================================================
// GIFT-128 PermBits (FULL UNROLLED, NO LOOP)
// ============================================================
module gift128_permbits (
    input  wire [31:0] s0,
    input  wire [31:0] s1,
    input  wire [31:0] s2,
    input  wire [31:0] s3,
    output wire [31:0] p0,
    output wire [31:0] p1,
    output wire [31:0] p2,
    output wire [31:0] p3
);
    // --- S0 ---
    assign p0 = {
        s0[29],s0[25],s0[21],s0[17],s0[13],s0[9], s0[5], s0[1],
        s0[30],s0[26],s0[22],s0[18],s0[14],s0[10],s0[6], s0[2],
        s0[31],s0[27],s0[23],s0[19],s0[15],s0[11],s0[7], s0[3],
        s0[28],s0[24],s0[20],s0[16],s0[12],s0[8], s0[4], s0[0]
    };

    // --- S1 ---
    assign p1 = {
        s1[30],s1[26],s1[22],s1[18],s1[14],s1[10],s1[6], s1[2],
        s1[31],s1[27],s1[23],s1[19],s1[15],s1[11],s1[7], s1[3],
        s1[28],s1[24],s1[20],s1[16],s1[12],s1[8], s1[4], s1[0],
        s1[29],s1[25],s1[21],s1[17],s1[13],s1[9], s1[5], s1[1]
    };

    // --- S2 ---
    assign p2 = {
        s2[31],s2[27],s2[23],s2[19],s2[15],s2[11],s2[7], s2[3],
        s2[28],s2[24],s2[20],s2[16],s2[12],s2[8], s2[4], s2[0],
        s2[29],s2[25],s2[21],s2[17],s2[13],s2[9], s2[5], s2[1],
        s2[30],s2[26],s2[22],s2[18],s2[14],s2[10],s2[6], s2[2]
    };

    // --- S3 ---
    assign p3 = {
        s3[28],s3[24],s3[20],s3[16],s3[12],s3[8], s3[4], s3[0],
        s3[29],s3[25],s3[21],s3[17],s3[13],s3[9], s3[5], s3[1],
        s3[30],s3[26],s3[22],s3[18],s3[14],s3[10],s3[6], s3[2],
        s3[31],s3[27],s3[23],s3[19],s3[15],s3[11],s3[7], s3[3]
    };
endmodule

// ======================================================================
// FILE: gift_cofb\gift128_addroundkey.v
// ======================================================================
// ============================================================
// GIFT-128 AddRoundKey
// ============================================================
module gift128_addroundkey (
    input  wire [31:0] S1,
    input  wire [31:0] S2,
    input  wire [15:0] W2,
    input  wire [15:0] W3,
    input  wire [15:0] W6,
    input  wire [15:0] W7,
    output wire [31:0] Z1,
    output wire [31:0] Z2
);
    assign Z2 = S2 ^ {W2, W3};
    assign Z1 = S1 ^ {W6, W7};
endmodule

// ======================================================================
// FILE: gift_cofb\gift128_roundconst.v
// ======================================================================
// ============================================================
// GIFT-128 Round Constant
// ============================================================
module gift128_roundconst (
    input  wire [31:0] S3,
    input  wire [7:0]  RC,
    output wire [31:0] Z3
);
    assign Z3 = S3 ^ 32'h80000000 ^ {24'b0, RC};
endmodule

// ======================================================================
// FILE: gift_cofb\gift128_keyschedule.v
// ======================================================================
// ============================================================
// GIFT-128 Key Schedule
// ============================================================
module gift128_keyschedule (
    input  wire [15:0] W0, W1, W2, W3, W4, W5, W6, W7,
    output wire [15:0] N0, N1, N2, N3, N4, N5, N6, N7
);
    assign N0 = {W6[1:0],  W6[15:2]};   // ROR2
    assign N1 = {W7[11:0], W7[15:12]};  // ROR12
    assign N2 = W0;
    assign N3 = W1;
    assign N4 = W2;
    assign N5 = W3;
    assign N6 = W4;
    assign N7 = W5;
endmodule

// ======================================================================
// FILE: gift_cofb\gift128_round.v
// ======================================================================
// ============================================================
// GIFT-128 Round Datapath
// ============================================================
module gift128_round (
    input  wire [31:0] S0,S1,S2,S3,
    input  wire [15:0] W0,W1,W2,W3,W4,W5,W6,W7,
    input  wire [7:0]  RC,
    output wire [31:0] N0,N1,N2,N3,
    output wire [15:0] K0,K1,K2,K3,K4,K5,K6,K7
);
    wire [31:0] a0,a1,a2,a3;
    wire [31:0] b0,b1,b2,b3;
    wire [31:0] c1,c2,c3;

    gift128_subcells u_sub (S0,S1,S2,S3,a0,a1,a2,a3);
    gift128_permbits u_perm (a0,a1,a2,a3,b0,b1,b2,b3);
    gift128_addroundkey u_ark (b1,b2,W2,W3,W6,W7,c1,c2);
    gift128_roundconst u_rc (b3,RC,c3);
    gift128_keyschedule u_key (W0,W1,W2,W3,W4,W5,W6,W7,
                               K0,K1,K2,K3,K4,K5,K6,K7);

    assign N0 = b0;
    assign N1 = c1;
    assign N2 = c2;
    assign N3 = c3;
endmodule

// ======================================================================
// FILE: gift_cofb\gift128_encrypt_top.v
// ======================================================================
// ============================================================
// GIFT-128 Encrypt TOP
// - 40 rounds
// - 1 round / cycle
// ============================================================
module gift128_encrypt_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,

    output reg         busy,
    output reg         done,
    output reg  [127:0] ciphertext
);

    // --------------------------------------------------------
    // State registers
    // --------------------------------------------------------
    reg [31:0] S0, S1, S2, S3;
    reg [15:0] W0, W1, W2, W3, W4, W5, W6, W7;

    reg [5:0] round;

    // --------------------------------------------------------
    // Round constant ROM
    // --------------------------------------------------------
    reg [7:0] RC;
    always @(*) begin
        case (round)
            6'd0:  RC = 8'h01;  6'd1:  RC = 8'h03;
            6'd2:  RC = 8'h07;  6'd3:  RC = 8'h0F;
            6'd4:  RC = 8'h1F;  6'd5:  RC = 8'h3E;
            6'd6:  RC = 8'h3D;  6'd7:  RC = 8'h3B;
            6'd8:  RC = 8'h37;  6'd9:  RC = 8'h2F;
            6'd10: RC = 8'h1E;  6'd11: RC = 8'h3C;
            6'd12: RC = 8'h39;  6'd13: RC = 8'h33;
            6'd14: RC = 8'h27;  6'd15: RC = 8'h0E;
            6'd16: RC = 8'h1D;  6'd17: RC = 8'h3A;
            6'd18: RC = 8'h35;  6'd19: RC = 8'h2B;
            6'd20: RC = 8'h16;  6'd21: RC = 8'h2C;
            6'd22: RC = 8'h18;  6'd23: RC = 8'h30;
            6'd24: RC = 8'h21;  6'd25: RC = 8'h02;
            6'd26: RC = 8'h05;  6'd27: RC = 8'h0B;
            6'd28: RC = 8'h17;  6'd29: RC = 8'h2E;
            6'd30: RC = 8'h1C;  6'd31: RC = 8'h38;
            6'd32: RC = 8'h31;  6'd33: RC = 8'h23;
            6'd34: RC = 8'h06;  6'd35: RC = 8'h0D;
            6'd36: RC = 8'h1B;  6'd37: RC = 8'h36;
            6'd38: RC = 8'h2D;  6'd39: RC = 8'h1A;
            default: RC = 8'h00;
        endcase
    end

    // --------------------------------------------------------
    // Round datapath
    // --------------------------------------------------------
    wire [31:0] nS0, nS1, nS2, nS3;
    wire [15:0] nW0, nW1, nW2, nW3, nW4, nW5, nW6, nW7;

    gift128_round u_round (
        .S0(S0), .S1(S1), .S2(S2), .S3(S3),
        .W0(W0), .W1(W1), .W2(W2), .W3(W3),
        .W4(W4), .W5(W5), .W6(W6), .W7(W7),
        .RC(RC),
        .N0(nS0), .N1(nS1), .N2(nS2), .N3(nS3),
        .K0(nW0), .K1(nW1), .K2(nW2), .K3(nW3),
        .K4(nW4), .K5(nW5), .K6(nW6), .K7(nW7)
    );

    // --------------------------------------------------------
    // FSM / registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy  <= 1'b0;
            done  <= 1'b0;
            round <= 6'd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                // load plaintext (big-endian)
                S0 <= plaintext[127:96];
                S1 <= plaintext[ 95:64];
                S2 <= plaintext[ 63:32];
                S3 <= plaintext[ 31: 0];

                // load key
                W0 <= key[127:112];
                W1 <= key[111:96];
                W2 <= key[ 95:80];
                W3 <= key[ 79:64];
                W4 <= key[ 63:48];
                W5 <= key[ 47:32];
                W6 <= key[ 31:16];
                W7 <= key[ 15: 0];

                round <= 6'd0;
                busy  <= 1'b1;
            end
            else if (busy) begin
                S0 <= nS0; S1 <= nS1; S2 <= nS2; S3 <= nS3;
                W0 <= nW0; W1 <= nW1; W2 <= nW2; W3 <= nW3;
                W4 <= nW4; W5 <= nW5; W6 <= nW6; W7 <= nW7;

                if (round == 6'd39) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ciphertext <= {nS0, nS1, nS2, nS3};
                end

                round <= round + 6'd1;
            end
        end
    end

endmodule

// ======================================================================
// FILE: gift_cofb\cofb_core.v
// ======================================================================
// ============================================================
// COFB CORE - Multi-block FSM (matching encrypt.c)
// Req/ack handshake interface for multi-block AD and MSG
// ============================================================

module cofb_core (
`ifdef USE_POWER_PINS
    inout wire          VPWR,
    inout wire          VGND,
`endif
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         decrypt_mode,   // 0: Encrypt, 1: Decrypt

    input  wire [127:0] key,
    input  wire [127:0] nonce,

    // ---- AD streaming input ----
    input  wire [127:0] ad_data,
    input  wire [7:0]   ad_total_len,   // Total AD bytes (0..255)
    input  wire         ad_ack,         // User: new block is stable on ad_data

    // ---- MSG streaming input ----
    input  wire [127:0] msg_data,
    input  wire [7:0]   msg_total_len,  // Total MSG bytes (0..255)
    input  wire         msg_ack,        // User: new block is stable on msg_data

    // ---- Decrypt: tag to check ----
    input  wire [127:0] tag_in,

    // ---- Handshake outputs ----
    output reg          ad_req,         // Core is waiting for the next AD block
    output reg          msg_req,        // Core is waiting for the next MSG block

    // ---- Output streaming ----
    output reg  [127:0] data_out,
    output reg          data_out_valid,

    // ---- Final results ----
    output reg  [127:0] tag_out,
    output reg          valid,          // Decrypt: 1 if tag matches; Encrypt: always 1
    output reg          done
);

    // ----------------------------------------------------------
    // FSM States
    // ----------------------------------------------------------
    localparam S_IDLE       = 4'd0;
    localparam S_WAIT_NONCE = 4'd1;
    localparam S_PROC_AD    = 4'd2;
    localparam S_WAIT_AD    = 4'd3;
    localparam S_REQ_AD     = 4'd4;
    localparam S_PROC_MSG   = 4'd5;
    localparam S_WAIT_MSG   = 4'd6;
    localparam S_REQ_MSG    = 4'd7;
    localparam S_DONE       = 4'd8;

    reg [3:0]   state;
    reg [63:0]  L;
    reg [127:0] Y_prev;
    reg [7:0]   remaining_ad;
    reg [7:0]   remaining_msg;
    reg         is_last_ad;
    reg         is_last_msg;

    // ----------------------------------------------------------
    // Combinational signals
    // ----------------------------------------------------------
    wire [4:0] ad_bytes  = (remaining_ad  > 8'd16) ? 5'd16 : remaining_ad[4:0];
    wire [4:0] msg_bytes = (remaining_msg > 8'd16) ? 5'd16 : remaining_msg[4:0];

    wire last_ad_now  = (remaining_ad  <= 8'd16);
    wire last_msg_now = (remaining_msg <= 8'd16);

    // C: (alen%16 != 0) || emptyA
    wire partial_or_empty_ad = (remaining_ad == 8'd0) ||
                                (remaining_ad[3:0] != 4'd0);

    // C: inlen%16 != 0
    wire partial_msg = (remaining_msg != 8'd0) &&
                       (remaining_msg[3:0] != 4'd0);

    // emptyM: use original total length (input port, invariant)
    wire emptyM = (msg_total_len == 8'd0);

    // ----------------------------------------------------------
    // Submodule connections
    // ----------------------------------------------------------
    reg  [127:0] gift_in;
    wire [127:0] gift_out;
    reg          gift_start;
    wire         gift_done;

    wire [127:0] pho1_AD_X;
    wire [127:0] gift_in_with_offset;

    // ----------------------------------------------------------
    // Shared MSG processing (replaces separate pho + phoprime)
    // Both compute partial_xor(Y,input) and pho1(Y,M,bytes).
    // Encrypt: out_data=C=xor(Y,M), X=pho1(Y, M)
    // Decrypt: out_data=M=xor(Y,C), X=pho1(Y, M=xor(Y,C))
    // ----------------------------------------------------------
    wire [127:0] msg_xor_out;   // C (encrypt) or M (decrypt)
    wire [127:0] msg_pho1_X;    // chaining value for both modes

    xor_block u_msg_xor (
        .s1          (Y_prev),
        .s2          (msg_data),
        .no_of_bytes (msg_bytes),
        .d           (msg_xor_out)
    );

    // pho1 M input: encrypt uses msg_data, decrypt uses msg_xor_out
    wire [127:0] pho1_msg_m_in = decrypt_mode ? msg_xor_out : msg_data;

    pho1 u_pho1_msg (
        .Y_in        (Y_prev),
        .M_in        (pho1_msg_m_in),
        .no_of_bytes (msg_bytes),
        .d           (msg_pho1_X)
    );

    // ----------------------------------------------------------
    // Offset sequence: L → 2L / 3L / 9L / 27L / 81L
    // ----------------------------------------------------------
    wire [63:0] L_dbl;
    wire [63:0] L_tri;
    wire [63:0] L_tri2;
    wire [63:0] L_tri3;
    wire [63:0] L_tri4;

    double_half_block u_dbl  (.s(L),      .d(L_dbl));
    triple_half_block u_tri  (.s(L),      .d(L_tri));
    triple_half_block u_tri2 (.s(L_tri),  .d(L_tri2));
    triple_half_block u_tri3 (.s(L_tri2), .d(L_tri3));
    triple_half_block u_tri4 (.s(L_tri3), .d(L_tri4));

    pho1 u_pho1_ad (
        .Y_in        (Y_prev),
        .M_in        (ad_data),
        .no_of_bytes (ad_bytes),
        .d           (pho1_AD_X)
    );

    xor_topbar_block u_offset_xor (
        .s1 (gift_in),
        .s2 (L),
        .d  (gift_in_with_offset)
    );

    gift128_encrypt_top u_gift (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (gift_start),
        .plaintext (gift_in_with_offset),
        .key       (key),
        .busy      (),
        .done      (gift_done),
        .ciphertext(gift_out)
    );

    // ----------------------------------------------------------
    // FSM Sequential
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            valid          <= 1'b0;
            data_out_valid <= 1'b0;
            ad_req         <= 1'b0;
            msg_req        <= 1'b0;
            gift_start     <= 1'b0;
            L              <= 64'd0;
            Y_prev         <= 128'd0;
            data_out       <= 128'd0;
            tag_out        <= 128'd0;
            gift_in        <= 128'd0;
            remaining_ad   <= 8'd0;
            remaining_msg  <= 8'd0;
            is_last_ad     <= 1'b0;
            is_last_msg    <= 1'b0;
        end else begin

            gift_start     <= 1'b0;
            data_out_valid <= 1'b0;
            ad_req         <= 1'b0;
            msg_req        <= 1'b0;

            case (state)

                // =================================================
                // S_IDLE
                // =================================================
                S_IDLE: begin
                    done  <= 1'b0;
                    valid <= 1'b0;
                    if (start) begin
                        gift_in       <= nonce;
                        L             <= 64'd0;
                        gift_start    <= 1'b1;
                        remaining_ad  <= ad_total_len;
                        remaining_msg <= msg_total_len;
                        state         <= S_WAIT_NONCE;
                    end
                end

                // =================================================
                // S_WAIT_NONCE
                // =================================================
                S_WAIT_NONCE: begin
                    if (gift_done) begin
                        Y_prev <= gift_out;
                        L      <= gift_out[127:64];
                        state  <= S_PROC_AD;
                    end
                end

                // =================================================
                // S_PROC_AD
                // =================================================
                S_PROC_AD: begin
                    is_last_ad <= last_ad_now;

                    if (!last_ad_now) begin
                        L <= L_dbl;
                    end else begin
                        if      (!partial_or_empty_ad && !emptyM) L <= L_tri;
                        else if ( partial_or_empty_ad && !emptyM) L <= L_tri2;
                        else if (!partial_or_empty_ad &&  emptyM) L <= L_tri3;
                        else                                       L <= L_tri4;
                    end

                    gift_in    <= pho1_AD_X;
                    gift_start <= 1'b1;
                    state      <= S_WAIT_AD;
                end

                // =================================================
                // S_WAIT_AD
                // =================================================
                S_WAIT_AD: begin
                    if (gift_done) begin
                        Y_prev <= gift_out;

                        if (is_last_ad) begin
                            if (!emptyM)
                                state <= S_PROC_MSG;
                            else begin
                                tag_out <= gift_out;
                                state   <= S_DONE;
                            end
                        end else begin
                            remaining_ad <= remaining_ad - 8'd16;
                            state        <= S_REQ_AD;
                        end
                    end
                end

                // =================================================
                // S_REQ_AD
                // =================================================
                S_REQ_AD: begin
                    ad_req <= 1'b1;
                    if (ad_ack)
                        state <= S_PROC_AD;
                end

                // =================================================
                // S_PROC_MSG
                // =================================================
                S_PROC_MSG: begin
                    is_last_msg <= last_msg_now;

                    if (!last_msg_now) begin
                        L <= L_dbl;
                    end else begin
                        if (!partial_msg) L <= L_tri;
                        else              L <= L_tri2;
                    end

                    data_out       <= msg_xor_out;
                    data_out_valid <= 1'b1;
                    gift_in        <= msg_pho1_X;

                    gift_start <= 1'b1;
                    state      <= S_WAIT_MSG;
                end

                // =================================================
                // S_WAIT_MSG
                // =================================================
                S_WAIT_MSG: begin
                    if (gift_done) begin
                        Y_prev <= gift_out;

                        if (is_last_msg) begin
                            tag_out <= gift_out;
                            state   <= S_DONE;
                        end else begin
                            remaining_msg <= remaining_msg - 8'd16;
                            state         <= S_REQ_MSG;
                        end
                    end
                end

                // =================================================
                // S_REQ_MSG
                // =================================================
                S_REQ_MSG: begin
                    msg_req <= 1'b1;
                    if (msg_ack)
                        state <= S_PROC_MSG;
                end

                // =================================================
                // S_DONE
                // =================================================
                S_DONE: begin
                    done <= 1'b1;
                    if (decrypt_mode)
                        valid <= (tag_out == tag_in);
                    else
                        valid <= 1'b1;

                    if (!start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
