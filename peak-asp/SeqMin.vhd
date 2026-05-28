library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity SeqMin is
	port (
		clock : in std_logic;
		reset : in std_logic;
		
		ld_in : in std_logic;
		input : in std_logic_vector(15 downto 0);
		
		output : out std_logic_vector(15 downto 0)
	);
end entity;

architecture beh of SeqMin is
	signal min : integer := 2147483647;
begin
	process(clock)
		variable input_var : integer := 0;
	begin
		if rising_edge(clock) then
			if reset = '1' then
				min <= -2147483647;
			else
				if ld_in = '1' then
					-- If input is less than current min, overwrite
					input_var := to_integer(signed(input));
					if input_var > min then
						min <= input_var;
					end if;
					
				end if;
				
				-- Output min value
				output <= std_logic_vector(to_signed(min, 16));
			end if;
			
		end if;
		
	end process;
end architecture;