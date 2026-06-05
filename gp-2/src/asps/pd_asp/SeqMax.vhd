library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity SeqMax is
	port (
		clock : in std_logic;
		reset : in std_logic;
		
		ld_in : in std_logic;
		input : in std_logic_vector(15 downto 0);
		
		output : out std_logic_vector(15 downto 0)
	);
end entity;

architecture beh of SeqMax is
	signal max : integer := -2147483647;
begin
	process(clock)
		variable input_var : integer := 0;
	begin
		if rising_edge(clock) then
			if reset = '1' then
				max <= -2147483647;
			else
				if ld_in = '1' then
					-- If input is greater than current max, overwrite
					input_var := to_integer(signed(input));
					if input_var > max then
						max <= input_var;
					end if;
					
				end if;
				
				-- Output max value
				output <= std_logic_vector(to_signed(max, 16));
			end if;
			
		end if;
	end process;
end architecture;