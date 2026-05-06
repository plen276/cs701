LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TestTopLevel IS
	GENERIC (
		ports : POSITIVE := 8
	);
END ENTITY;

ARCHITECTURE sim OF TestTopLevel IS

	SIGNAL clock     : STD_LOGIC := '1';

	SIGNAL send_port : tdma_min_ports(0 TO ports - 1);
	SIGNAL recv_port : tdma_min_ports(0 TO ports - 1);

BEGIN

	clock <= NOT clock AFTER 10 ns;

	tdma_min : ENTITY work.TdmaMin
		GENERIC MAP(
			ports => ports
		)
		PORT MAP
		(
			clock => clock,
			sends => send_port,
			recvs => recv_port
		);

	asp_adc : ENTITY work.TestAdc
		GENERIC MAP(
			forward => 3
		)
		PORT
		MAP (
		clock => clock,
		send  => send_port(0),
		recv  => recv_port(0)
		);

	asp_dac : ENTITY work.TestDac
		PORT
		MAP (
		clock => clock,
		send  => send_port(1),
		recv  => recv_port(1)
		);

	dp_asp : ENTITY work.DpAsp
		PORT
		MAP (
		clock => clock,
		key   => "1111",
		send  => send_port(3),
		recv  => recv_port(3)
		);

END ARCHITECTURE;
