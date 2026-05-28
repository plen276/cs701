-- Zoran Salcic

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;

PACKAGE opcodes IS

	-- instruction format
	-- ---------------------------------------------
	-- |AM(2)|OP(6)|Rz(4)|Rx(4)|ADDR/VAL/OTHERs(16)|
	-- ---------------------------------------------

	-- addressing modes (AM)
	CONSTANT am_inherent  : bit_2 := "00";
	CONSTANT am_immediate : bit_2 := "01";
	CONSTANT am_direct    : bit_2 := "10";
	CONSTANT am_register  : bit_2 := "11";

	-----------------------------	
	--   normal instructions   --
	-----------------------------

	-- operations with immediate, direct and indirect AM
	-- immediate: LDR Rz #value
	-- indirect: LDR Rz $address
	-- direct: LDR Rz Rx
	CONSTANT ldr          : bit_6 := "000000";

	-- operations with direct and immediate AM
	-- immediate: STR Rz #value
	-- indirect: STR Rz Rx
	-- direct: STR Rx Op
	CONSTANT str          : bit_6 := "000010";

	-- operations with immediate and direct AM
	-- immediate: JMP #address 
	-- direct: JMP Rx 
	CONSTANT jmp          : bit_6 := "011000";

	-- operations with direct AM
	-- direct: PRESENT Rz Rx 
	CONSTANT present      : bit_6 := "011100";

	-- operations with immediate and direct AM
	CONSTANT andr         : bit_6 := "001000"; --  AND Rz Rx Op
	CONSTANT orr          : bit_6 := "001100"; --  OR Rz Rx Op
	CONSTANT addr         : bit_6 := "111000"; --  ADD Rz Rx Op
	CONSTANT subr         : bit_6 := "000100"; --  SUB Rz Op
	CONSTANT subvr        : bit_6 := "000011"; -- SUBV RZ Rx Op

	-- operations with inherent AM
	CONSTANT clfz         : bit_6 := "010000";
	CONSTANT cer          : bit_6 := "111100";
	CONSTANT ceot         : bit_6 := "111110";
	CONSTANT seot         : bit_6 := "111111";
	CONSTANT noop         : bit_6 := "110100";

	-- operations with immediate AM
	-- SZ Op
	CONSTANT sz           : bit_6 := "010100";

	-- operations with direct AM
	-- LER Rz
	CONSTANT ler          : bit_6 := "110110";

	----------------------------	
	--  special instructions  --
	----------------------------

	-- operations with direct AM
	-- direct: SSVOP Rx 
	CONSTANT ssvop        : bit_6 := "111011";

	-- operations with direct AM
	-- direct: SSOP Rx 
	CONSTANT ssop         : bit_6 := "111010";

	-- operations with direct AM
	-- direct: LSIP Rx 
	CONSTANT lsip         : bit_6 := "110111";

	---------------------------
	--  other instructions  --
	---------------------------
	-- operations with register and immediate AM
	-- register: DATACALL Rx
	-- immediate : DATACALL Rx #value
	CONSTANT datacall     : bit_6 := "101000";
	CONSTANT datacall2    : bit_6 := "101001";

	-- operations with immediate AM
	-- immediate : MAX Rz #value
	CONSTANT max          : bit_6 := "011110";

	-- operations with direct AM
	-- direct : STRPC Rz $address
	CONSTANT strpc        : bit_6 := "011101";

	-- operation with register AM
	-- register : SRES Rz
	CONSTANT sres         : bit_6 := "101010";

END opcodes;
