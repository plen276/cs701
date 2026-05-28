-- Zoran Salcic

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;

PACKAGE various_constants IS
	-- ALU operation selection alu_sel
	CONSTANT alu_add  : bit_3 := "000";
	CONSTANT alu_sub  : bit_3 := "001";
	CONSTANT alu_and  : bit_3 := "010";
	CONSTANT alu_or   : bit_3 := "011";
	CONSTANT alu_idle : bit_3 := "100";
	CONSTANT alu_max  : bit_3 := "101";
END various_constants;
