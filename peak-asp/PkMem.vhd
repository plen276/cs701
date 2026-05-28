library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity PkMem is
	port (
		clock : in std_logic;
		reset : in std_logic;
		
		conf_en : in std_logic;
		set_lifetime : in integer;
		
		wren : in std_logic;
		input : in std_logic_vector(15 downto 0);
		
		size : out integer range 0 to 16;
		select_v : in integer range 0 to 15;
		select_a : in integer range 0 to 15;
		output_v : out std_logic_vector(15 downto 0);
		output_a : out integer;
		
		output_a_avg : out integer
	);
end entity;

architecture beh of PkMem is

	type values_array is array (0 to 15) of std_logic_vector(15 downto 0);
	type ages_array is array (0 to 15) of integer;
	
	signal values : values_array := (others => (others => '0'));
	signal ages : ages_array := (others => 0);

	signal lifetime : integer := 2147483647;
	signal counter : integer := 0;
	
begin
	process(clock)
		variable values_var : values_array := (others => (others => '0'));
		variable ages_var : ages_array := (others => 0);
		variable size_var : integer := 0;
		variable avg_var : integer := 0;
	begin
		if rising_edge(clock) then
			if reset = '1' then -- Reset
				-- Clear storage
				for i in 0 to 15 loop
					values(i) <= (others => '0');
					values_var(i) := (others => '0');
					ages(i) <= 0;
					ages_var(i) := 0;
					size <= 0;
					size_var := 0;
					avg_var := 0;
					lifetime <= 2147483647;
					counter <= 0;
				end loop;
				
				-- Clear outputs
				output_v <= (others => '0');
				output_a <= 0;
			else
				if conf_en = '1' then
					lifetime <= set_lifetime;
				elsif wren = '1' then -- Write new value
					-- Shift values
					for i in 1 to 15 loop
						values_var(i) := values(i-1);
						ages_var(i) := ages(i-1);
					end loop;
					
					-- Insert new value
					values_var(0) := input;
					ages_var(0) := counter;
					-- Move size_var
					if size_var < 16 then
						size_var := size_var + 1;
					end if;
					
					-- Reset counter
					counter <= 0;
				else
					counter <= counter + 1;
				end if;
				
				-- If there are entries
				if size_var > 0 then
					-- Check for out of lifetime values
					if ages_var(size_var - 1) > lifetime then
						-- Clear oldest
						values_var(size_var) := (others => '0');
						ages_var(size_var) := 0;
						-- Move size_var
						if size_var > 0 then
							size_var := size_var - 1;
						end if;
					
					else -- Else tick ages
						for i in 0 to 15 loop
							ages_var(i) := ages_var(i) + 1;
						end loop;
					
					end if;
					
				end if;
				
				-- Calculate average time between peaks
				if size_var > 0 then
					avg_var := 0;
					for i in 0 to 15 loop
						if i < size_var then
							avg_var := avg_var + ages_var(i);
						end if;
						
					end loop;
					avg_var := avg_var/size_var;
				end if;
				
				-- Update signals
				for i in 1 to 15 loop
					values(i) <= values_var(i);
					ages(i) <= ages_var(i);
				end loop;
				
				-- Output values
				size <= size_var;
				output_v <= values(select_v);
				output_a <= ages(select_a);
				output_a_avg <= avg_var;
			end if;
			
		end if;
		
	end process;
end architecture;