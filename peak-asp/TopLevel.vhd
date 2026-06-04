library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

use work.TdmaMinTypes.all;

entity TopLevel is
	generic (
		ports : positive := 4
	);
	port (
		CLOCK_50	: in std_logic;
		reset : in std_logic;
		--send : out std_logic_vector(39 downto 0);
		--recv : in std_logic_vector(31 downto 0)
		send  : out tdma_min_port;
		recv  : in  tdma_min_port
	);
end entity;

architecture beh of TopLevel is
	signal clock : std_logic;
	
	signal send_port : tdma_min_ports(0 to ports-1);
	signal recv_port : tdma_min_ports(0 to ports-1);
	
	component PeakDetector is
		port (
			clock : in std_logic;
			reset : in std_logic;
			--addr : out std_logic_vector(7 downto 0);
			--send : out std_logic_vector(31 downto 0);
			--recv : in std_logic_vector(31 downto 0)
			send  : out tdma_min_port;
			recv  : in  tdma_min_port
		);
	end component;
	
begin

	clock <= CLOCK_50;
	--reset <= reset;
	
	PD : PeakDetector port map (
		clock => clock,
		reset => reset,
		--addr => send(39 downto 32),
		--send => send(31 downto 0),
		--recv => recv
		send => send_port(0),
		recv => recv_port(0)
	);
	
	tdma_min : entity work.TdmaMin
	generic map (
		ports => ports
	)
	port map (
		clock => clock,
		sends => send_port,
		recvs => recv_port
	);
	
end architecture;