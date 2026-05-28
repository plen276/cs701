LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

PACKAGE TdmaMinTypes IS

	SUBTYPE tdma_min_addr IS STD_LOGIC_VECTOR(7 DOWNTO 0);
	SUBTYPE tdma_min_data IS STD_LOGIC_VECTOR(31 DOWNTO 0);
	SUBTYPE tdma_min_fifo IS STD_LOGIC_VECTOR(39 DOWNTO 0);

	TYPE tdma_min_port IS RECORD
		addr : tdma_min_addr;
		data : tdma_min_data;
	END RECORD;

	TYPE tdma_min_datas IS ARRAY (NATURAL RANGE <>) OF tdma_min_data;
	TYPE tdma_min_ports IS ARRAY (NATURAL RANGE <>) OF tdma_min_port;

	FUNCTION log2Ceil (x : POSITIVE) RETURN NATURAL;

END PACKAGE;

PACKAGE BODY TdmaMinTypes IS

	FUNCTION log2Ceil (x : POSITIVE) RETURN NATURAL IS
		VARIABLE i           : NATURAL := 0;
	BEGIN
		WHILE (2 ** i < x) AND i < 31 LOOP
			i := i + 1;
		END LOOP;
		RETURN i;
	END FUNCTION;

END PACKAGE BODY;
