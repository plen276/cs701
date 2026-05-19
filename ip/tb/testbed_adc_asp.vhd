LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- System testbed: the ADC-ASP inside the real TDMA-MIN NoC, configured
-- by packets that travel through the network, with the streamed
-- samples received through the network by a sink.
--   port 0  adc_asp        - DUT
--   port 1  configurator  - one-shot Conf-ADC packets (ReCOP
--                           stand-in; GP-2 replaces this)
--   port 2  sink          - receives Data-Audio over the NoC
--   port 3  unused        - tied off
-- The DUT uses a small clock_hz so the sample-rate divider is short;

ENTITY testbed_adc_asp IS
END ENTITY;

ARCHITECTURE sim OF testbed_adc_asp IS

	CONSTANT NUM_PORTS      : POSITIVE  := 4;
	CONSTANT CLK_HALF       : TIME      := 10 ns; -- 20 ns period

	CONSTANT NODE_ADC       : NATURAL   := 0;
	CONSTANT NODE_CFG       : NATURAL   := 1;
	CONSTANT NODE_SINK      : NATURAL   := 2;

	SIGNAL clock            : STD_LOGIC := '1';
	SIGNAL stop             : BOOLEAN   := false;

	SIGNAL send_port        : tdma_min_ports(0 TO NUM_PORTS - 1);
	SIGNAL recv_port        : tdma_min_ports(0 TO NUM_PORTS - 1);

	-- Sink observation (for waveform + end-of-sim check)
	SIGNAL rx_valid         : STD_LOGIC;
	SIGNAL rx_ch            : STD_LOGIC;
	SIGNAL rx_sample        : signed(15 DOWNTO 0);
	SIGNAL rx_cnt0          : NATURAL := 0;
	SIGNAL rx_cnt1          : NATURAL := 0;

	-- The `dest` argument populates the Next field (23-20), the ADC's
	-- forward node.
	FUNCTION conf_adc (dest : STD_LOGIC_VECTOR(3 DOWNTO 0);
		rate                    : STD_LOGIC_VECTOR(1 DOWNTO 0);
		en                      : STD_LOGIC;
		ch                      : STD_LOGIC;
		ftw                     : INTEGER) RETURN tdma_min_data IS
	BEGIN
		RETURN "1010" & "0000" & dest & rate & en & ch &
		STD_LOGIC_VECTOR(to_unsigned(ftw, 16));
	END FUNCTION;

BEGIN

	clock <= NOT clock AFTER CLK_HALF WHEN NOT stop ELSE
		'0';

	-- NoC fabric (instantiates one TdmaMinInterface + TdmaMinFifo per port)
	noc : ENTITY work.TdmaMin
		GENERIC MAP(ports => NUM_PORTS)
		PORT MAP
		(
			clock => clock,
			sends => send_port,
			recvs => recv_port
		);

	-- DUT: ADC-ASP on port 0.  Small clock_hz so SR_DIV is sim-friendly
	-- (Fs = 80000/8000 = 8 kHz at SR=00); the DDS math is unchanged.
	dut : ENTITY work.adc_asp
		GENERIC MAP(
			clock_hz      => 80_000,
			phase_bits    => 16,
			lut_addr_bits => 10
		)
		PORT
		MAP
		(
		clock => clock,
		send  => send_port(NODE_ADC),
		recv  => recv_port(NODE_ADC)
		);

	-- Configurator: each packet is held one clock so the NI FIFO
	-- enqueues a single copy (req = send.data(31)); then idles with zeros.
	configurator : PROCESS
		-- Send one packet to a destination node, held 1 clock period.
		PROCEDURE send_pkt (dst : NATURAL; pkt : tdma_min_data) IS
		BEGIN
			send_port(NODE_CFG).addr <=
			STD_LOGIC_VECTOR(to_unsigned(dst, tdma_min_addr'length));
			send_port(NODE_CFG).data <= pkt;
			WAIT FOR 20 ns; -- one clock period
			send_port(NODE_CFG).addr <= (OTHERS => '0');
			send_port(NODE_CFG).data <= (OTHERS => '0');
		END PROCEDURE;
	BEGIN
		send_port(NODE_CFG).addr <= (OTHERS => '0');
		send_port(NODE_CFG).data <= (OTHERS => '0');
		WAIT FOR 200 ns; -- let the NoC settle

		-- Enable CH0 -> sink, FTW=2048 (250 Hz @ 8 kHz, 32 samples/period)
		send_pkt(NODE_ADC, conf_adc("0010", "00", '1', '0', 2048));
		WAIT FOR 200 ns;

		-- Enable CH1 -> sink, FTW=4096 (500 Hz; dual-channel)
		send_pkt(NODE_ADC, conf_adc("0010", "00", '1', '1', 4096));

		WAIT FOR 30 us;

		-- Live retune CH0 to FTW=1024 (125 Hz)
		send_pkt(NODE_ADC, conf_adc("0010", "00", '1', '0', 1024));

		WAIT FOR 30 us;

		-- Disable CH1 only; CH0 keeps streaming
		send_pkt(NODE_ADC, conf_adc("0010", "00", '0', '1', 4096));

		WAIT FOR 15 us;

		ASSERT rx_cnt0 > 0
		REPORT "TESTBED FAIL: no CH0 samples arrived through the NoC"
			SEVERITY error;
		ASSERT rx_cnt1 > 0
		REPORT "TESTBED FAIL: no CH1 samples arrived through the NoC"
			SEVERITY error;
		REPORT "testbed_adc_asp finished: ch0=" & INTEGER'image(rx_cnt0) &
			" ch1=" & INTEGER'image(rx_cnt1) SEVERITY note;

		stop <= true;
		WAIT;
	END PROCESS;

	-- Sink (port 2): receives Data-Audio over the NoC, counts per channel.
	send_port(NODE_SINK).addr <= (OTHERS => '0');
	send_port(NODE_SINK).data <= (OTHERS => '0');

	rx_valid                  <= '1' WHEN recv_port(NODE_SINK).data(31 DOWNTO 28) = "1000"
		ELSE
		'0';
	rx_ch     <= recv_port(NODE_SINK).data(16);
	rx_sample <= signed(recv_port(NODE_SINK).data(15 DOWNTO 0));

	sink : PROCESS (clock)
	BEGIN
		IF rising_edge(clock) THEN
			IF rx_valid = '1' THEN
				-- Verify the payload Dest (27:24) end-to-end must equal the
				-- configured Next, i.e. the sink's own node id.
				ASSERT recv_port(NODE_SINK).data(27 DOWNTO 24)
				= STD_LOGIC_VECTOR(to_unsigned(NODE_SINK, 4))
				REPORT "Data-Audio payload Dest (27:24) /= configured Next"
					SEVERITY error;
				IF rx_ch = '0' THEN
					rx_cnt0 <= rx_cnt0 + 1;
				ELSE
					rx_cnt1 <= rx_cnt1 + 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	-- Unused port
	send_port(3).addr <= (OTHERS => '0');
	send_port(3).data <= (OTHERS => '0');

END ARCHITECTURE;
