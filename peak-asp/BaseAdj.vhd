library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity BaseAdj is
	port (
		clock : in std_logic;
		reset : in std_logic;
		
		conf_en : in std_logic;
		set_adj_rate : in integer;
		
		ld_in : in std_logic;
		input : in std_logic_vector(15 downto 0);
		output : out integer
	);
end entity;

architecture beh of BaseAdj is
	signal baseline : integer := 0;
begin
	process(clock)
		variable new_sample : integer := 0;
		variable adj_rate : integer := 100;
	begin
		if rising_edge(clock) then
			if reset = '1' then
				new_sample := 0;
				baseline <= 0;
				adj_rate := 100;
			else
				if conf_en = '1' then
					adj_rate := set_adj_rate;
				elsif ld_in = '1' then
					new_sample := to_integer(signed(input));
					baseline <= ((baseline * (adj_rate - 1)) + new_sample)/adj_rate;
				end if;
				
				output <= baseline;
			end if;
			
		end if;
			
	end process;

end architecture;