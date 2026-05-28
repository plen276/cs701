library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity FindPeak is
	port (
		clock : in std_logic;
		reset : in std_logic;
		
		conf_en : in std_logic;
		set_hysteresis : in integer := 10;
		
		ld_en : in std_logic;
		baseline : in integer;
		input : in std_logic_vector(15 downto 0);
		
		out_max : out std_logic;
		out_min : out std_logic;
		output : out std_logic_vector(15 downto 0)
	);
end entity;

architecture beh of FindPeak is
	signal current_pick : integer := -2147483647;
begin
	process(clock)
		variable above_base : boolean := true;
		variable hysteresis : integer := 10;
		variable new_sample : integer := 0;
		variable send_output : boolean := false;
	begin
		if rising_edge(clock) then
			if reset = '1' then
				above_base := true;
				hysteresis := 10;
				new_sample := 0;
				send_output := false;
				current_pick <= -2147483647;
				out_min <= '0';
				out_max <= '0';
			else
				if conf_en = '1' then
					hysteresis := set_hysteresis;
				elsif ld_en = '1' then
					new_sample := to_integer(signed(input));
					
					-- Check if samples have moved above/below baseline
					if above_base then
						if new_sample < (baseline * 100 + baseline * hysteresis)/100 then
							above_base := false;
							send_output := true;
						end if;
					else
						if new_sample > (baseline * 100 - baseline * hysteresis)/100 then
							above_base := true;
							send_output := true;
						end if;
					end if;
					
					-- Send output if samples have moved above/below baseline
					if send_output then
						if above_base then
							out_min <= '1';
						else
							out_max <= '1';
						end if;
						
						output <= std_logic_vector(to_signed(current_pick, 16));
						send_output := false;
					else
						out_min <= '0';
						out_max <= '0';
					end if;
					
					-- Check if new sample is more max/min than current pick
					if above_base then
						if new_sample > current_pick then
							current_pick <= new_sample;
						end if;
					else
						if new_sample < current_pick then
							current_pick <= new_sample;
						end if;
					end if;
					
					
				end if;
				
			end if;
			
		end if;
	
	end process;
	
end architecture;