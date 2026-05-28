LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TdmaMinSwitch IS
	PORT
	(
		s : IN STD_LOGIC;
		a : IN tdma_min_data;
		b : IN tdma_min_data;
		x : OUT tdma_min_data;
		y : OUT tdma_min_data
	);
END ENTITY;

ARCHITECTURE rtl OF TdmaMinSwitch IS
BEGIN

	x <= a WHEN s = '0' ELSE
		b;
	y <= b WHEN s = '0' ELSE
		a;

END ARCHITECTURE;
