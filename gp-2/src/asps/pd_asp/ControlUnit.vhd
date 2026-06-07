LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

ENTITY ControlUnit IS
	PORT
	(
		clock           : IN STD_LOGIC;
		reset           : IN STD_LOGIC;
		addr            : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		send            : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		recv            : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		-- To BaseAdj
		base_reset      : OUT STD_LOGIC;
		base_conf       : OUT STD_LOGIC;
		base_rate       : OUT INTEGER;
		base_ld         : OUT STD_LOGIC;
		base_in         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		-- To FindPeak
		find_reset      : OUT STD_LOGIC;
		find_conf       : OUT STD_LOGIC;
		find_hysteresis : OUT INTEGER;
		find_ld         : OUT STD_LOGIC;
		find_in         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		-- To Mem
		lifetime        : OUT INTEGER;
		-- To Max_Mem
		max_reset       : OUT STD_LOGIC;
		max_conf        : OUT STD_LOGIC;
		max_sel_v       : OUT INTEGER RANGE 0 TO 15;
		max_sel_a       : OUT INTEGER RANGE 0 TO 15;
		-- To Min_Mem
		min_reset       : OUT STD_LOGIC;
		min_conf        : OUT STD_LOGIC;
		min_sel_v       : OUT INTEGER RANGE 0 TO 15;
		min_sel_a       : OUT INTEGER RANGE 0 TO 15;
		-- To Seq_Max
		seq_max_reset   : OUT STD_LOGIC;
		seq_max_ld      : OUT STD_LOGIC;
		-- To Seq_Min
		seq_min_reset   : OUT STD_LOGIC;
		seq_min_ld      : OUT STD_LOGIC;
		-- From Max_Mem
		max_size        : IN INTEGER RANGE 0 TO 16;
		peak_time       : IN INTEGER;
		-- From Min_Mem
		min_size        : IN INTEGER RANGE 0 TO 16;
		-- From Seq_Max
		seq_max_out     : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		-- From Seq_Min
		seq_min_out     : IN STD_LOGIC_VECTOR(15 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE beh OF ControlUnit IS
	SIGNAL adj_rate      : INTEGER               := 100;
	SIGNAL hysteresis    : INTEGER               := 10;
	SIGNAL max_mem_index : INTEGER RANGE 0 TO 15 := 0;
	SIGNAL min_mem_index : INTEGER RANGE 0 TO 15 := 0;
	SIGNAL global_max    : STD_LOGIC_VECTOR(15 DOWNTO 0);
	SIGNAL global_min    : STD_LOGIC_VECTOR(15 DOWNTO 0);
BEGIN
	PROCESS (clock)
		VARIABLE shift_var : unsigned(15 DOWNTO 0)        := "0000000000000001";
		VARIABLE state     : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	BEGIN
		IF rising_edge(clock) THEN
			IF reset = '1' THEN
				adj_rate   <= 100;
				hysteresis <= 10;
				lifetime   <= 2147483647;
				addr       <= (OTHERS => '0');
				send       <= (OTHERS => '0');
				shift_var := "0000000000000001";
				state     := "00";
				max_mem_index   <= 0;
				min_mem_index   <= 0;
				global_max      <= (OTHERS => '0');
				global_min      <= (OTHERS => '0');
				-- Reset all components
				base_reset      <= '1';
				base_conf       <= '0';
				base_rate       <= 100;
				base_ld         <= '0';
				base_in         <= (OTHERS => '0');
				find_reset      <= '1';
				find_conf       <= '0';
				find_hysteresis <= 10;
				find_ld         <= '0';
				find_in         <= (OTHERS => '0');
				max_reset       <= '1';
				max_conf        <= '0';
				max_sel_v       <= 0;
				max_sel_a       <= 0;
				min_reset       <= '1';
				min_conf        <= '0';
				min_sel_v       <= 0;
				min_sel_a       <= 0;
				seq_max_reset   <= '1';
				seq_max_ld      <= '0';
				seq_min_reset   <= '1';
				seq_min_ld      <= '0';

			ELSE
				base_conf     <= '0';
				base_ld       <= '0';
				find_conf     <= '0';
				find_ld       <= '0';
				max_conf      <= '0';
				min_conf      <= '0';
				seq_max_ld    <= '0';
				seq_min_ld    <= '0';

				IF recv(31 DOWNTO 28) = "1001" THEN -- If configuration packet

					-- Set addr from 'Next' field
					addr     <= "0000" & recv(23 DOWNTO 20);

					-- Set lifetime as 2^ recv(4->0) 
					lifetime <= to_integer(shift_left(shift_var, to_integer(unsigned(recv(4 DOWNTO 0)))));

					-- Set hysteresis
					CASE recv(7 DOWNTO 5) IS
						WHEN "000"  => hysteresis  <= 0;
						WHEN "001"  => hysteresis  <= 5;
						WHEN "010"  => hysteresis  <= 10;
						WHEN "011"  => hysteresis  <= 15;
						WHEN "100"  => hysteresis  <= 20;
						WHEN "101"  => hysteresis  <= 30;
						WHEN "110"  => hysteresis  <= 40;
						WHEN "111"  => hysteresis  <= 50;
						WHEN OTHERS => hysteresis <= 50;
					END CASE;

					-- Set baseline adjust rate as 2^ recv(12->8)
					adj_rate <= to_integer(shift_left(shift_var, to_integer(unsigned(recv(12 DOWNTO 8)))));

					IF recv(17) = '1' THEN -- Set enable/state from 'En' bit
						state := "01";
					ELSE
						state := "00";
					END IF;

					-- Tell all components to configure
					max_mem_index   <= 0;
					min_mem_index   <= 0;
					global_max      <= (OTHERS => '0');
					global_min      <= (OTHERS => '0');
					base_reset      <= '0';
					base_conf       <= '1';
					base_rate       <= adj_rate;
					base_ld         <= '0';
					base_in         <= (OTHERS => '0');
					find_reset      <= '0';
					find_conf       <= '1';
					find_hysteresis <= hysteresis;
					find_ld         <= '0';
					find_in         <= (OTHERS => '0');
					max_reset       <= '0';
					max_conf        <= '1';
					max_sel_v       <= 0;
					max_sel_a       <= 0;
					min_reset       <= '0';
					min_conf        <= '1';
					min_sel_v       <= 0;
					min_sel_a       <= 0;
					seq_max_reset   <= '0';
					seq_max_ld      <= '0';
					seq_min_reset   <= '0';
					seq_min_ld      <= '0';

				ELSIF recv(31 DOWNTO 28) = "1000" THEN -- If data packet
					base_in       <= recv(15 DOWNTO 0);
					find_in       <= recv(15 DOWNTO 0);

					base_reset    <= '0';
					base_conf     <= '0';
					base_ld       <= '1';
					find_reset    <= '0';
					find_conf     <= '0';
					find_ld       <= '1';
					max_reset     <= '0';
					max_conf      <= '0';
					min_reset     <= '0';
					min_conf      <= '0';
					seq_max_reset <= '0';
					seq_min_reset <= '0';

				END IF;

				-- Cycle outputs from max memory
				IF max_size > 0 THEN
					IF max_mem_index < max_size - 1 THEN
						max_sel_v     <= max_mem_index;
						max_sel_a     <= max_mem_index;
						seq_max_ld    <= '1';
						max_mem_index <= max_mem_index + 1;
					ELSE
						-- If end of entries, update max var and set index back to 0
						global_max    <= seq_max_out;
						max_mem_index <= 0;
					END IF;

				ELSE
					seq_max_ld <= '0';
				END IF;

				-- Cycle outputs from min memory
				IF min_size > 0 THEN
					IF min_mem_index < min_size - 1 THEN
						min_sel_v     <= min_mem_index;
						min_sel_a     <= min_mem_index;
						seq_min_ld    <= '1';
						min_mem_index <= min_mem_index + 1;
					ELSE
						-- If end of entries, update min var and set index back to 0
						global_min    <= seq_min_out;
						min_mem_index <= 0;
					END IF;

				ELSE
					seq_min_ld <= '0';
				END IF;

				CASE state IS
					WHEN "00"                    => -- Enable off
						send(31 DOWNTO 0) <= (OTHERS => '0');
						state := "00";
					WHEN "01" => -- Send global max
						send <= "1000" & "01" & "0000000000" & global_max;
						-- send(31 downto 28) <= "1000";
						-- send(27 downto 26) <= "01";
						-- send(29 downto 16) <= (others => '0');
						-- send(15 downto 0) <= global_max;
						state := "10";
					WHEN "10" => -- Send global min
						send <= "1000" & "10" & "0000000000" & global_min;
						-- send(31 downto 28) <= "1000";
						-- send(27 downto 26) <= "10";
						-- send(29 downto 16) <= (others => '0');
						-- send(15 downto 0) <= global_min;
						state := "11";
					WHEN "11" => -- Send time between peaks
						send <= "1000" & "11" & "0000000000" & STD_LOGIC_VECTOR(to_unsigned(peak_time, 16));
						-- send(31 DOWNTO 28) <= "1000";
						-- send(27 DOWNTO 26) <= "11";
						-- send(29 DOWNTO 16) <= (OTHERS => '0');
						-- send(15 DOWNTO 0)  <= STD_LOGIC_VECTOR(to_unsigned(peak_time, 16)); -- Change to time between peaks
						state := "01";
					WHEN OTHERS                  =>
						send(31 DOWNTO 0) <= (OTHERS => '0');
						state := "00";
				END CASE;

			END IF;

		END IF;

	END PROCESS;

END ARCHITECTURE;
