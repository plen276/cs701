LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- Minimal synthesisable root: instantiates both ASPs (ADC -> AVG) so
-- the Quartus project has a valid top-level entity and both designs
-- are compiled. Per-ASP resource/Fmax figures are obtained by setting
-- the individual ASP as the top-level entity; this file is only the
-- project's compile root and is not a board design.

ENTITY top_level IS
	GENERIC (
		ports : POSITIVE := 4
	);
	PORT
	(
		clock    : IN STD_LOGIC;
		recv_in  : IN tdma_min_data;
		send_out : OUT tdma_min_data
	);
END ENTITY;

ARCHITECTURE structural OF top_level IS

	SIGNAL adc_recv  : tdma_min_port;
	SIGNAL adc_send  : tdma_min_port;
	SIGNAL avg_send  : tdma_min_port;

	SIGNAL send_port : tdma_min_ports(0 TO ports - 1);
	SIGNAL recv_port : tdma_min_ports(0 TO ports - 1);

BEGIN

	adc_recv.addr <= (OTHERS => '0');
	adc_recv.data <= recv_in;

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

	adc : ENTITY work.adc_asp
		PORT
		MAP
		(
		clock => clock,
		send  => adc_send,
		recv  => adc_recv
		);

	avg : ENTITY work.avg_asp
		PORT
		MAP
		(
		clock => clock,
		send  => avg_send,
		recv  => adc_send
		);

	send_out <= avg_send.data;

END ARCHITECTURE;
