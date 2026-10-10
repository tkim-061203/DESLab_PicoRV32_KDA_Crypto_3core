`timescale 1 ns / 1 ps

module system_tb;
	reg clk = 1'b0;
	always #5 clk = ~clk;

	reg resetn_btn = 1'b0;
	reg [3:0] sw = 4'b0;
	reg [3:0] btn = 4'b0;
	reg uart_rx = 1'b1;
	reg sd_miso = 1'b1;

	wire trap;
	wire [7:0] out_byte;
	wire out_byte_en;
	wire uart_tx;
	wire sd_cs_n;
	wire sd_sck;
	wire sd_mosi;

	integer cycle_count = 0;

	system #(
		.UART_DEFAULT_DIV(10)
	) uut (
		.clk        (clk),
		.resetn_btn (resetn_btn),
		.trap       (trap),
		.out_byte   (out_byte),
		.out_byte_en(out_byte_en),
		.sw         (sw),
		.btn        (btn),
		.uart_tx    (uart_tx),
		.uart_rx    (uart_rx),
		.sd_cs_n    (sd_cs_n),
		.sd_sck     (sd_sck),
		.sd_mosi    (sd_mosi),
		.sd_miso    (sd_miso)
	);

	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("system.vcd");
			$dumpvars(0, system_tb);
		end

		// Preload the app image the bootloader will jump to. system.v
		// itself loads the real bootloader.hex into boot_mem
		// (`initial $readmemh("bootloader.hex", boot_mem)`); driving
		// sw[0]=1 makes bootloader.c take its debug/sim strap and jump
		// straight to 0x0001_0000 instead of talking to (non-existent)
		// SD hardware, so this now exercises the real boot ROM code
		// instead of a hand-poked boot_mem stub that bypassed it.
		#1;
		$readmemh("sim_app.hex", uut.app_mem);
		sw <= 4'b0001;

		repeat (100) @(posedge clk);
		resetn_btn <= 1'b1;
	end

	always @(posedge clk) begin
		cycle_count <= cycle_count + 1;

		if (cycle_count == 0 || (cycle_count % 1000000 == 0)) begin
			$display("[TB] cycle=%0d pc=0x%08x trap=%0b uart_we=%0b",
				cycle_count,
				uut.cpu.picorv32_core.reg_pc,
				trap,
				uut.uart_we);
		end

		if (uut.uart_we) begin
			$write("%c", uut.uart_tx_data);
			$fflush();
		end

		if (out_byte_en && out_byte == 8'hff) begin
			$display("\n[TB] PASS");
			$finish;
		end

		if (out_byte_en && out_byte == 8'h55) begin
			$display("\n[TB] FAIL");
			$fatal(1);
		end

		if (trap) begin
			$display("\n[TB] Unexpected CPU trap at cycle %0d", cycle_count);
			$fatal(1);
		end

		if (cycle_count > 20000000) begin
			$display("\n[TB] TIMEOUT after %0d cycles", cycle_count);
			$fatal(1);
		end
	end
endmodule
