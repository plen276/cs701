LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TdmaMinFabric IS
	GENERIC (
		stages : POSITIVE;
		ports  : POSITIVE
	);
	PORT
	(
		slot : IN STD_LOGIC_VECTOR(stages - 1 DOWNTO 0);
		push : IN tdma_min_datas(0 TO ports - 1);
		pull : OUT tdma_min_datas(0 TO ports - 1)
	);
END ENTITY;

ARCHITECTURE rtl OF TdmaMinFabric IS

	CONSTANT terminals : POSITIVE := 2 ** stages;

	TYPE links_t IS ARRAY (stages DOWNTO 0) OF tdma_min_datas(0 TO terminals - 1);
	SIGNAL links : links_t;

BEGIN

	links(stages)(ports TO terminals - 1) <= (OTHERS => (OTHERS => '0'));
	links(stages)(0 TO ports - 1)         <= push;
	pull                                  <= links(0)(0 TO ports - 1);

	staging : FOR index IN stages - 1 DOWNTO 0 GENERATE
		stage : ENTITY work.TdmaMinStage
			GENERIC MAP(
				terminals => terminals
			)
			PORT MAP
			(
				s => slot(index),
				i => links(index + 1),
				o => links(index)
			);
	END GENERATE;

END ARCHITECTURE;
