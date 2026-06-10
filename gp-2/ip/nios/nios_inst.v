	nios u0 (
		.clk_clk                                    (<connected-to-clk_clk>),                                    //                                 clk.clk
		.noc_noc_coe_send_data                      (<connected-to-noc_noc_coe_send_data>),                      //                             noc_noc.coe_send_data
		.noc_noc_coe_send_addr                      (<connected-to-noc_noc_coe_send_addr>),                      //                                    .coe_send_addr
		.noc_noc_coe_recv_data                      (<connected-to-noc_noc_coe_recv_data>),                      //                                    .coe_recv_data
		.noc_noc_coe_recv_addr                      (<connected-to-noc_noc_coe_recv_addr>),                      //                                    .coe_recv_addr
		.recop_reset_pio_external_connection_export (<connected-to-recop_reset_pio_external_connection_export>), // recop_reset_pio_external_connection.export
		.reset_reset_n                              (<connected-to-reset_reset_n>),                              //                               reset.reset_n
		.reset_0_reset_n                            (<connected-to-reset_0_reset_n>),                            //                             reset_0.reset_n
		.clk_1_clk                                  (<connected-to-clk_1_clk>)                                   //                               clk_1.clk
	);

