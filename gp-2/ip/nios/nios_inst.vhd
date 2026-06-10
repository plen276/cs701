	component nios is
		port (
			clk_clk                                    : in  std_logic                     := 'X';             -- clk
			noc_noc_coe_send_data                      : out std_logic_vector(31 downto 0);                    -- coe_send_data
			noc_noc_coe_send_addr                      : out std_logic_vector(7 downto 0);                     -- coe_send_addr
			noc_noc_coe_recv_data                      : in  std_logic_vector(31 downto 0) := (others => 'X'); -- coe_recv_data
			noc_noc_coe_recv_addr                      : in  std_logic_vector(7 downto 0)  := (others => 'X'); -- coe_recv_addr
			recop_reset_pio_external_connection_export : out std_logic;                                        -- export
			reset_reset_n                              : in  std_logic                     := 'X';             -- reset_n
			reset_0_reset_n                            : in  std_logic                     := 'X';             -- reset_n
			clk_1_clk                                  : in  std_logic                     := 'X'              -- clk
		);
	end component nios;

	u0 : component nios
		port map (
			clk_clk                                    => CONNECTED_TO_clk_clk,                                    --                                 clk.clk
			noc_noc_coe_send_data                      => CONNECTED_TO_noc_noc_coe_send_data,                      --                             noc_noc.coe_send_data
			noc_noc_coe_send_addr                      => CONNECTED_TO_noc_noc_coe_send_addr,                      --                                    .coe_send_addr
			noc_noc_coe_recv_data                      => CONNECTED_TO_noc_noc_coe_recv_data,                      --                                    .coe_recv_data
			noc_noc_coe_recv_addr                      => CONNECTED_TO_noc_noc_coe_recv_addr,                      --                                    .coe_recv_addr
			recop_reset_pio_external_connection_export => CONNECTED_TO_recop_reset_pio_external_connection_export, -- recop_reset_pio_external_connection.export
			reset_reset_n                              => CONNECTED_TO_reset_reset_n,                              --                               reset.reset_n
			reset_0_reset_n                            => CONNECTED_TO_reset_0_reset_n,                            --                             reset_0.reset_n
			clk_1_clk                                  => CONNECTED_TO_clk_1_clk                                   --                               clk_1.clk
		);

