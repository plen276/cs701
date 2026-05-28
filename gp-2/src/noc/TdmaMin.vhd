LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TdmaMin IS
	GENERIC (
		ports : POSITIVE
	);
	PORT
	(
		clock : IN STD_LOGIC;
		sends : IN tdma_min_ports(0 TO ports - 1);
		recvs : OUT tdma_min_ports(0 TO ports - 1)
	);
END ENTITY;

ARCHITECTURE rtl OF TdmaMin IS

	CONSTANT stages : POSITIVE := log2Ceil(ports);

	SIGNAL slot     : STD_LOGIC_VECTOR(stages - 1 DOWNTO 0);
	SIGNAL push     : tdma_min_datas(0 TO ports - 1);
	SIGNAL pull     : tdma_min_datas(0 TO ports - 1);

BEGIN

	slots : ENTITY work.TdmaMinSlots
		GENERIC MAP(
			stages => stages
		)
		PORT MAP
		(
			clock => clock,
			slot  => slot
		);

	fabric : ENTITY work.TdmaMinFabric
		GENERIC MAP(
			stages => stages,
			ports  => ports
		)
		PORT
		MAP (
		slot => slot,
		push => push,
		pull => pull
		);

	interfaces : FOR identity IN 0 TO ports - 1 GENERATE
		interface : ENTITY work.TdmaMinInterface
			GENERIC MAP(
				stages   => stages,
				identity => identity
			)
			PORT
			MAP (
			clock => clock,
			slot  => slot,
			push  => push(identity),
			pull  => pull(identity),

			send  => sends(identity),
			recv  => recvs(identity)
			);
	END GENERATE;

END ARCHITECTURE;
