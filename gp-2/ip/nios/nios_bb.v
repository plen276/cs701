
module nios (
	clk_clk,
	noc_noc_coe_send_data,
	noc_noc_coe_send_addr,
	noc_noc_coe_recv_data,
	noc_noc_coe_recv_addr,
	recop_reset_pio_external_connection_export,
	reset_reset_n,
	reset_0_reset_n,
	clk_1_clk);	

	input		clk_clk;
	output	[31:0]	noc_noc_coe_send_data;
	output	[7:0]	noc_noc_coe_send_addr;
	input	[31:0]	noc_noc_coe_recv_data;
	input	[7:0]	noc_noc_coe_recv_addr;
	output		recop_reset_pio_external_connection_export;
	input		reset_reset_n;
	input		reset_0_reset_n;
	input		clk_1_clk;
endmodule
