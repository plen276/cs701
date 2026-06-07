-- Top level (NoC-bridge enabled, standalone loopback bring-up)
--
-- This is the Lab 1 Part 2 Nios system with the noc_avalon_bridge
-- component added inside the Qsys system (Nios_System_2A) and its
-- "noc" conduit exported to the top level.
--
-- STANDALONE TEST: the exported send_* signals are looped straight
-- back into recv_*, so a packet written by Nios to the bridge TX
-- register returns on its RX register. (For HMPSoC integration these
-- four signals instead connect to a TDMA-MIN NoC port.)
--
-- IMPORTANT: the exported conduit port names below assume the
-- conduit was exported in Platform Designer with the name "noc"
-- (giving noc_send_data / noc_send_addr / noc_recv_data /
-- noc_recv_addr). If you exported it under a different name, rename
-- the four ports in the component declaration and port map to match
-- the regenerated Nios_System_2A entity.


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;


entity Nios_Sys_2A is
	port (CLOCK_50 : in std_logic;
		  KEY : in std_logic_vector(1 downto 0);  
		  LEDR : out std_logic_vector(7 downto 0);
		  DRAM_DQ : inout std_logic_vector(15 downto 0);
		  DRAM_ADDR : out std_logic_vector(12 downto 0);
		  DRAM_BA : out std_logic_vector(1 downto 0);
		  DRAM_CAS_N, DRAM_RAS_N, DRAM_CLK : out std_logic;
		  DRAM_CKE, DRAM_CS_N, DRAM_WE_N : out std_logic;
		  DRAM_UDQM, DRAM_LDQM: out std_logic);
end entity Nios_Sys_2A;


architecture Structure of Nios_Sys_2A is
	component Nios_System_2A is
		port (
			led_pio_external_connection_export 		: out   std_logic_vector(7 downto 0);                     -- export
			button_pio_external_connection_export 	: in    std_logic_vector(1 downto 0)  := (others => 'X');  -- export
			sdram_wire_addr                    		: out   std_logic_vector(12 downto 0);                    -- addr
			sdram_wire_ba                      		: out   std_logic_vector(1 downto 0);                     -- ba
			sdram_wire_cas_n                   		: out   std_logic;                                        -- cas_n
			sdram_wire_cke                    		: out   std_logic;                                        -- cke
			sdram_wire_cs_n                 		: out   std_logic;                                        -- cs_n
			sdram_wire_dq                  		    : inout std_logic_vector(15 downto 0) := (others => 'X'); -- dq
			sdram_wire_dqm                 		    : out   std_logic_vector(1 downto 0);                     -- dqm
			sdram_wire_ras_n               		    : out   std_logic;                                        -- ras_n
			sdram_wire_we_n                 		: out   std_logic;                                        -- we_n
			clocks_sdram_clk_clk           		    : out   std_logic;                                        -- clk
			clocks_ref_clk_clk              		: in    std_logic                     := 'X';             -- clk
			clocks_ref_reset_reset         		    : in    std_logic                     := 'X';            -- reset

			-- noc_avalon_bridge conduit (exported as "noc")
			noc_send_data                           : out   std_logic_vector(31 downto 0);
			noc_send_addr                           : out   std_logic_vector(7 downto 0);
			noc_recv_data                           : in    std_logic_vector(31 downto 0) := (others => '0');
			noc_recv_addr                           : in    std_logic_vector(7 downto 0)  := (others => '0')
		);
	end component Nios_System_2A;

	-- Loopback wires: bridge TX -> bridge RX
	signal noc_send_data_s : std_logic_vector(31 downto 0);
	signal noc_send_addr_s : std_logic_vector(7 downto 0);

begin 
	u0 : component Nios_System_2A
		port map (
			led_pio_external_connection_export 		=> LEDR, 		-- led_pio_external_connection.export
			button_pio_external_connection_export 	=> KEY, 		-- button_pio_external_connection_export
			sdram_wire_addr                    		=> DRAM_ADDR,   -- sdram_wire.addr
			sdram_wire_ba                      		=> DRAM_BA,     -- .ba
			sdram_wire_cas_n                   		=> DRAM_CAS_N,  -- .cas_n
			sdram_wire_cke                    		=> DRAM_CKE,    -- .cke
			sdram_wire_cs_n                 		=> DRAM_CS_N,   -- .cs_n
			sdram_wire_dq                  		    => DRAM_DQ,     -- .dq
			sdram_wire_dqm(1)                  		=> DRAM_UDQM,   -- .dqm
			sdram_wire_dqm(0)                  		=> DRAM_LDQM,   --
			sdram_wire_ras_n                   		=> DRAM_RAS_N,  -- .ras_n
			sdram_wire_we_n                    		=> DRAM_WE_N,   -- .we_n
			clocks_sdram_clk_clk               		=> DRAM_CLK,    -- clocks_sdram_clk.clk
			clocks_ref_clk_clk                 		=> CLOCK_50,    -- clocks_ref_clk.clk
			clocks_ref_reset_reset             		=> NOT KEY(0),  -- clocks_ref_reset.reset

			noc_send_data                           => noc_send_data_s,
			noc_send_addr                           => noc_send_addr_s,
			noc_recv_data                           => noc_send_data_s, -- loopback: RX <= TX
			noc_recv_addr                           => noc_send_addr_s  -- loopback: RX <= TX
		);

end architecture Structure;
