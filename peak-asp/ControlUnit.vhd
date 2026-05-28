library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity ControlUnit is
	port (
		clock : in std_logic;
		reset : in std_logic;
		addr : out std_logic_vector(7 downto 0);
		send : out std_logic_vector(31 downto 0);
		recv : in std_logic_vector(31 downto 0);
		-- To BaseAdj
		base_reset : out std_logic;
		base_conf : out std_logic;
		base_rate : out integer;
		base_ld : out std_logic;
		base_in : out std_logic_vector(15 downto 0);
		-- To FindPeak
		find_reset : out std_logic;
		find_conf : out std_logic;
		find_hysteresis : out integer;
		find_ld : out std_logic;
		find_in : out std_logic_vector(15 downto 0);
		-- To Mem
		lifetime : out integer;
		-- To Max_Mem
		max_reset : out std_logic;
		max_conf : out std_logic;
		max_sel_v : out integer range 0 to 15;
		max_sel_a : out integer range 0 to 15;
		-- To Min_Mem
		min_reset : out std_logic;
		min_conf : out std_logic;
		min_sel_v : out integer range 0 to 15;
		min_sel_a : out integer range 0 to 15;
		-- To Seq_Max
		seq_max_reset : out std_logic;
		seq_max_ld : out std_logic;
		-- To Seq_Min
		seq_min_reset : out std_logic;
		seq_min_ld : out std_logic;
		-- From Max_Mem
		max_size : in integer range 0 to 16;
		peak_time : in integer;
		-- From Min_Mem
		min_size : in integer range 0 to 16;
		-- From Seq_Max
		seq_max_out : in std_logic_vector(15 downto 0);
		-- From Seq_Min
		seq_min_out : in std_logic_vector(15 downto 0)
	);
end entity;

architecture beh of ControlUnit is
	signal adj_rate : integer := 100;
	signal hysteresis : integer := 10;
	signal max_mem_index : integer range 0 to 15 := 0;
	signal min_mem_index : integer range 0 to 15 := 0;
	signal global_max : std_logic_vector(15 downto 0);
	signal global_min : std_logic_vector(15 downto 0);
begin
	process(clock)
		variable shift_var : unsigned(15 downto 0) := "0000000000000001";
		variable state : std_logic_vector(1 downto 0) := "00";
	begin
		if rising_edge(clock) then
			if reset = '1' then
				adj_rate <= 100;
				hysteresis <= 10;
				lifetime <= 2147483647;
				addr <= (others => '0');
				send <= (others => '0');
				shift_var := "0000000000000001";
				state := "00";
				max_mem_index <= 0;
				min_mem_index <= 0;
				global_max <= (others => '0');
				global_min <= (others => '0');
				-- Reset all components
				base_reset <= '1';
				base_conf <= '0';
				base_rate <= 100;
				base_ld <= '0';
				base_in <= (others => '0');
				find_reset <= '1';
				find_conf <= '0';
				find_hysteresis <= 10;
				find_ld <= '0';
				find_in <= (others => '0');
				max_reset <= '1';
				max_conf <= '0';
				max_sel_v <= 0;
				max_sel_a <= 0;
				min_reset <= '1';
				min_conf <= '0';
				min_sel_v <= 0;
				min_sel_a <= 0;
				seq_max_reset <= '1';
				seq_max_ld <= '0';
				seq_min_reset <= '1';
				seq_min_ld <= '0';
				
			else
				if recv(31 downto 28) = "1111" then -- If configuration packet
				
					-- Set addr
					addr <= "0000" & recv(27 downto 24);
				
					-- Set lifetime as 2^ recv(4->0) 
					lifetime <= to_integer(shift_left(shift_var, to_integer(unsigned(recv(4 downto 0)))));
					
					-- Set hysteresis
					case recv(7 downto 5) is
						when "000" => hysteresis <= 0;
						when "001" => hysteresis <= 5;
						when "010" => hysteresis <= 10;
						when "011" => hysteresis <= 15;
						when "100" => hysteresis <= 20;
						when "101" => hysteresis <= 30;
						when "110" => hysteresis <= 40;
						when "111" => hysteresis <= 50;
					end case;
					
					-- Set baseline adjust rate as 2^ recv(12->8)
					adj_rate <= to_integer(shift_left(shift_var, to_integer(unsigned(recv(12 downto 8)))));
					
					-- Tell all components to configure
					base_reset <= '0';
					base_conf <= '1';
					base_rate <= adj_rate;
					base_ld <= '0';
					base_in <= (others => '0');
					find_reset <= '0';
					find_conf <= '1';
					find_hysteresis <= hysteresis;
					find_ld <= '0';
					find_in <= (others => '0');
					max_reset <= '0';
					max_conf <= '1';
					max_sel_v <= 0;
					max_sel_a <= 0;
					min_reset <= '0';
					min_conf <= '1';
					min_sel_v <= 0;
					min_sel_a <= 0;
					seq_max_reset <= '0';
					seq_max_ld <= '0';
					seq_min_reset <= '0';
					seq_min_ld <= '0';
					
				elsif recv(31 downto 28) = "0000" then -- If data packet
					base_in <= recv(15 downto 0);
					find_in <= recv(15 downto 0);
					
					base_reset <= '0';
					base_conf <= '0';
					base_ld <= '1';
					find_reset <= '0';
					find_conf <= '0';
					find_ld <= '1';
					max_reset <= '0';
					max_conf <= '0';
					min_reset <= '0';
					min_conf <= '1';
					seq_max_reset <= '0';
					seq_min_reset <= '0';
					
				end if;
				
				-- Cycle outputs from max memory
				if max_size > 0 then
					if max_mem_index < max_size then
						max_sel_v <= max_mem_index;
						max_sel_a <= max_mem_index;
						seq_max_ld <= '1';
						max_mem_index <= max_mem_index + 1;
					else
						-- If end of entries, update max var and set index back to 0
						global_max <= seq_max_out;
						max_mem_index <= 0;
					end if;
					
				else
					seq_max_ld <= '0';
				end if;
					
				-- Cycle outputs from min memory
				if min_size > 0 then
					if min_mem_index < min_size then
						min_sel_v <= min_mem_index;
						min_sel_a <= min_mem_index;
						seq_min_ld <= '1';
						min_mem_index <= min_mem_index + 1;
					else
						-- If end of entries, update min var and set index back to 0
						global_min <= seq_min_out;
						min_mem_index <= 0;
					end if;
					
				else
					seq_min_ld <= '0';
				end if;
				
				case state is
					when "00" =>
						send(31 downto 30) <= "01";
						send(29 downto 16) <= (others => '0');
						send(15 downto 0) <= global_max;
						state := "01";
					when "01" =>
						send(31 downto 30) <= "10";
						send(29 downto 16) <= (others => '0');
						send(15 downto 0) <= global_min;
						state := "10";
					when "10" =>
						send(31 downto 30) <= "11";
						send(29 downto 16) <= (others => '0');
						send(15 downto 0) <= std_logic_vector(to_unsigned(peak_time, 16)); -- Change to time between peaks
						state := "00";
					when others =>
						send(31 downto 0) <= (others => '0');
						state := "00";
				end case;
				
			end if;
		
		end if;
		
	end process;

end architecture;