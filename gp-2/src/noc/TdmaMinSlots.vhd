LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

ENTITY TdmaMinSlots IS
	GENERIC (
		stages : POSITIVE
	);
	PORT
	(
		clock : IN STD_LOGIC;
		slot  : OUT STD_LOGIC_VECTOR(stages - 1 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF TdmaMinSlots IS

	SIGNAL count : unsigned(stages - 1 DOWNTO 0) := (OTHERS => '0');

BEGIN

	PROCESS (clock)
	BEGIN
		IF rising_edge(clock) THEN
			count <= count + 1;
		END IF;
	END PROCESS;

	slot <= STD_LOGIC_VECTOR(count);

END ARCHITECTURE;
