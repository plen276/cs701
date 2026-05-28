library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity TopLevel is
	port (
		CLOCK_50	: in std_logic;
		reset : in std_logic;
		send : out std_logic_vector(39 downto 0);
		recv : in std_logic_vector(31 downto 0)
	);
end entity;

architecture beh of TopLevel is
	signal clock : std_logic;
	
	component PeakDetector is
		port (
			clock : in std_logic;
			reset : in std_logic;
			addr : out std_logic_vector(7 downto 0);
			send : out std_logic_vector(31 downto 0);
			recv : in std_logic_vector(31 downto 0)
		);
	end component;
	
begin

	clock <= CLOCK_50;
	--reset <= reset;
	
	PD : PeakDetector port map (
		clock => clock,
		reset => reset,
		addr => send(39 downto 32),
		send => send(31 downto 0),
		recv => recv
	);
	
end architecture;