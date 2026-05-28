LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TdmaMinStage IS
	GENERIC (
		terminals : POSITIVE
	);
	PORT
	(
		s : IN STD_LOGIC;
		i : IN tdma_min_datas(0 TO terminals - 1);
		o : OUT tdma_min_datas(0 TO terminals - 1)
	);
END ENTITY;

ARCHITECTURE rtl OF TdmaMinStage IS
BEGIN

	switches : FOR index IN 0 TO terminals/2 - 1 GENERATE
		switch : ENTITY work.TdmaMinSwitch
			PORT MAP
			(
				s => s,
				a => i(index),
				b => i(index + terminals/2),
				x => o(index * 2),
				y => o(index * 2 + 1)
			);
	END GENERATE;

END ARCHITECTURE;
