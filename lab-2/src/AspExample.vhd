LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY AspExample IS
	PORT
	(
		clock : IN STD_LOGIC;
		key   : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		sw    : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
		ledr  : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
		hex0  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		hex1  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		hex2  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		hex3  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		hex4  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		hex5  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);

		send  : OUT tdma_min_port;
		recv  : IN tdma_min_port
	);
END ENTITY;

ARCHITECTURE rtl OF AspExample IS

	SIGNAL hexn : unsigned(23 DOWNTO 0) := x"000000";

BEGIN

	ledr <= sw;

	PROCESS (clock)
		VARIABLE edge  : STD_LOGIC;
		VARIABLE state : NATURAL := 0;
	BEGIN
		IF rising_edge(clock) THEN

			-- Check for KEY0 press
			IF key(0) = '0' AND edge = '1' THEN
				IF state > 4 THEN
					state := 4;
				ELSE
					state := 9;
				END IF;
				hexn <= hexn + 1;
			END IF;
			edge := key(0);

			-- Process data if available
			IF recv.data(31 DOWNTO 28) = "1000" AND recv.data(16) = '0' AND key(2) = '1' THEN
				send.addr <= x"01";
				send.data <= recv.data;
			ELSIF recv.data(31 DOWNTO 28) = "1000" AND recv.data(16) = '1' AND key(1) = '1' THEN
				send.addr <= x"01";
				send.data <= recv.data;

				-- Otherwise send configuration commands
				-- State 0 is disabled, state 5 is enabled
			ELSE
				CASE state IS

						-- Enable DAC channel 0
					WHEN 9 =>
						send.addr <= x"01";
						send.data <= x"b1020000";
						state := 8;

						-- Enable DAC channel 1
					WHEN 8 =>
						send.addr <= x"01";
						send.data <= x"b1030000";
						state := 7;

						-- Enable ADC channel 0, forward to DP-ASP (port 3)
					WHEN 7 =>
						send.addr <= x"00";
						send.data <= x"a0320000";
						state := 6;

						-- Enable ADC channel 1, forward to DP-ASP (port 3)
					WHEN 6 =>
						send.addr <= x"00";
						send.data <= x"a0330000";
						state := 5;

						-- Disable ADC channel 0
					WHEN 4 =>
						send.addr <= x"00";
						send.data <= x"a0000000";
						state := 3;

						-- Disable ADC channel 1
					WHEN 3 =>
						send.addr <= x"00";
						send.data <= x"a0010000";
						state := 2;

						-- Disable DAC channel 0
					WHEN 2 =>
						send.addr <= x"01";
						send.data <= x"b1000000";
						state := 1;

						-- Disable DAC channel 1
					WHEN 1 =>
						send.addr <= x"01";
						send.data <= x"b1010000";
						state := 0;

					WHEN OTHERS =>
						send.addr <= x"01";
						send.data <= x"00000000";
				END CASE;
			END IF;

		END IF;
	END PROCESS;

	hs6 : ENTITY work.HexSeg6
		PORT MAP
		(
			hexn => STD_LOGIC_VECTOR(hexn),
			seg0 => hex0,
			seg1 => hex1,
			seg2 => hex2,
			seg3 => hex3,
			seg4 => hex4,
			seg5 => hex5
		);

END ARCHITECTURE;
