LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

-- ============================================================
-- Debugger 
--
-- Can hold and step forward execution of code on the ReCOP
-- Snoops and displays values of current parameters to 7-segment display
-- Cycles through displaying PC, 
-- ============================================================

ENTITY debugger IS
	port (
		clk           : IN  bit_1;
		debug_key     : IN  bit_3;
		debug_sw		  : IN  bit_10;
	   debug_output0 : OUT bit_7;
		debug_output1 : OUT bit_7;
		debug_output2 : OUT bit_7;
		debug_output3 : OUT bit_7;
	   debug_assert  : OUT bit_1;
	   debug_step    : OUT bit_1;
		
		debug_pc      : IN  bit_16;
		debug_ir      : IN  bit_32
	);
END ENTITY debugger;

ARCHITECTURE beh OF debugger IS
	TYPE display_type IS (DT_PC_TEXT, DT_PC_VALUE, DT_INST_TEXT, DT_INST_VALUE, DT_OPR_TEXT, DT_OPR_VALUE);
   SIGNAL display : display_type := DT_PC_TEXT;
	SIGNAL display_next : display_type := DT_PC_VALUE;
	
	type value_to_hex_array is array (15 downto 0) of bit_16;
	signal value_to_hex: value_to_hex_array := ("1000000", "1111001", "0100100", "0110000", "0011001", "0010010", "0000010", "1111000", "0000000", "0010000", "0001000", "0000011", "1000110", "0100001", "0000110", "0001110"); -- Values 0 to F
	
	SIGNAL pc : bit_16 := (OTHERS => '0');
	SIGNAL rx : bit_16 := (OTHERS => '0');
	SIGNAL rz : bit_16 := (OTHERS => '0');
BEGIN
	PROCESS(debug_sw(9))
	BEGIN
		IF debug_sw(9) = '0' THEN
			debug_assert <= '0';
			debug_output3 <= "1111111"; -- Blank
			debug_output2 <= "1111111"; -- Blank
			debug_output1 <= "1111111"; -- Blank
			debug_output0 <= "1111111"; -- Blank
		ELSE
			debug_assert <= '1';
			CASE display IS
				WHEN DT_PC_TEXT =>
					display_next <= DT_PC_VALUE;
					debug_output3 <= "0001100"; -- P
					debug_output2 <= "1000110"; -- C
					debug_output1 <= "1111111"; -- Blank
					debug_output0 <= "1111111"; -- Blank
				WHEN DT_PC_VALUE =>
					display_next <= DT_INST_TEXT;
					debug_output3 <= value_to_hex(to_integer(unsigned(debug_pc(15 DOWNTO 12))));
					debug_output2 <= value_to_hex(to_integer(unsigned(debug_pc(11 DOWNTO 8))));
					debug_output1 <= value_to_hex(to_integer(unsigned(debug_pc(7 DOWNTO 4))));
					debug_output0 <= value_to_hex(to_integer(unsigned(debug_pc(3 DOWNTO 0))));
				WHEN DT_INST_TEXT =>
					display_next <= DT_INST_VALUE;
					debug_output3 <= "1111011"; -- I
					debug_output2 <= "0101011"; -- N
					debug_output1 <= "0010010"; -- S
					debug_output0 <= "0001111"; -- T
				WHEN DT_INST_VALUE =>
					display_next <= DT_OPR_TEXT;
					debug_output3 <= value_to_hex(to_integer(unsigned(debug_ir(31 DOWNTO 28))));
					debug_output2 <= value_to_hex(to_integer(unsigned(debug_ir(27 DOWNTO 24))));
					debug_output1 <= value_to_hex(to_integer(unsigned(debug_ir(23 DOWNTO 20))));
					debug_output0 <= value_to_hex(to_integer(unsigned(debug_ir(19 DOWNTO 16))));
				WHEN DT_OPR_TEXT =>
					debug_output3 <= "0100011"; -- O
					debug_output2 <= "0001100"; -- P
					debug_output1 <= "0101111"; -- R
					debug_output0 <= "1111111"; -- Blank
				WHEN DT_OPR_VALUE =>
					display_next <= DT_PC_TEXT;
					debug_output3 <= value_to_hex(to_integer(unsigned(debug_ir(15 DOWNTO 12))));
					debug_output2 <= value_to_hex(to_integer(unsigned(debug_ir(11 DOWNTO 8))));
					debug_output1 <= value_to_hex(to_integer(unsigned(debug_ir(7 DOWNTO 4))));
					debug_output0 <= value_to_hex(to_integer(unsigned(debug_ir(3 DOWNTO 0))));
			END CASE;
		END IF;
	END PROCESS;
	
	PROCESS(debug_key(3)) -- Check for button press to step ReCOP forward
	BEGIN
		IF rising_edge(debug_key(3)) THEN
			debug_step <= '1';
		ELSE
			debug_step <= '0';
		END IF;
	END PROCESS;
	
	PROCESS(debug_key(2)) -- Check for button press to cycle display
	BEGIN
		IF rising_edge(debug_key(2)) THEN
			display <= display_next;
		END IF;
	END PROCESS;
	
END ARCHITECTURE beh;