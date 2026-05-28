LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY ip;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TdmaMinInterface IS
	GENERIC (
		stages   : POSITIVE;
		identity : NATURAL
	);
	PORT
	(
		clock : IN STD_LOGIC;
		slot  : IN STD_LOGIC_VECTOR(stages - 1 DOWNTO 0);
		push  : OUT tdma_min_data;
		pull  : IN tdma_min_data;

		send  : IN tdma_min_port;
		recv  : OUT tdma_min_port
	);
END ENTITY;

ARCHITECTURE rtl OF TdmaMinInterface IS

	CONSTANT id  : tdma_min_addr := STD_LOGIC_VECTOR(to_unsigned(identity, tdma_min_addr'length));
	SIGNAL addr  : tdma_min_addr;

	SIGNAL empty : STD_LOGIC;
	SIGNAL req   : STD_LOGIC := '0';
	SIGNAL ack   : STD_LOGIC := '0';
	SIGNAL enqu  : tdma_min_fifo;
	SIGNAL dequ  : tdma_min_fifo;

	SIGNAL todo  : tdma_min_port;
	SIGNAL ready : BOOLEAN;

BEGIN

	addr <= id XOR (id'high DOWNTO stages => '0') & slot;

	fifo : ENTITY ip.TdmaMinFifo
		PORT MAP
		(
			clock => clock,
			data  => enqu,
			rdreq => ack,
			wrreq => req,
			q     => dequ,
			empty => empty,
			full  => OPEN
		);

	-- Send interface connected to fifo
	enqu      <= send.addr & send.data;
	req       <= send.data(send.data'high);

	-- Next packet for network
	todo.addr <= dequ(dequ'high DOWNTO todo.data'length);
	todo.data <= dequ(todo.data'RANGE);

	-- Wait for network circuit
	ready     <= empty = '0' AND todo.addr = addr;
	ack       <= '1' WHEN ready ELSE
		'0';
	push <= todo.data WHEN ready ELSE
		(OTHERS => '0');

	-- Receive interface connected to network
	PROCESS (clock)
	BEGIN
		IF rising_edge(clock) THEN
			recv.addr <= addr;
			recv.data <= pull;
		END IF;
	END PROCESS;

END ARCHITECTURE;
