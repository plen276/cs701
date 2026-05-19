LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- End-to-end pipeline testbed: ADC-ASP -> AVG-ASP over the real
-- TDMA-MIN NoC.
--   port 0  adc_asp       - DDS signal source
--   port 1  configurator  - Conf-DP then Conf-ADC (realistic
--                           order: configure downstream first,
--                           start the source last; ReCOP does
--                           this in GP-2)
--   port 2  avg_asp       - moving-average filter
--   port 3  sink          - receives filtered samples
-- The source is a sine (exact maths is checked by tb_avg_asp); here
-- the check is the physical property that a moving average attenuates
-- a non-DC sine, so peak|post| <= peak|pre|.

ENTITY testbed_pipeline IS
END ENTITY;

ARCHITECTURE sim OF testbed_pipeline IS

	CONSTANT NUM_PORTS      : POSITIVE  := 4;
	CONSTANT CLK_HALF       : TIME      := 10 ns;

	CONSTANT NODE_ADC       : NATURAL   := 0;
	CONSTANT NODE_CFG       : NATURAL   := 1;
	CONSTANT NODE_AVG       : NATURAL   := 2;
	CONSTANT NODE_SINK      : NATURAL   := 3;

	SIGNAL clock            : STD_LOGIC := '1';
	SIGNAL stop             : BOOLEAN   := false;

	SIGNAL send_port        : tdma_min_ports(0 TO NUM_PORTS - 1);
	SIGNAL recv_port        : tdma_min_ports(0 TO NUM_PORTS - 1);

	-- Snoop points
	SIGNAL pre_valid        : STD_LOGIC; -- ADC -> AVG
	SIGNAL pre_sample       : signed(15 DOWNTO 0);
	SIGNAL post_valid       : STD_LOGIC; -- AVG -> sink
	SIGNAL post_sample      : signed(15 DOWNTO 0);

	SIGNAL measuring        : BOOLEAN := false;
	SIGNAL peak_pre         : NATURAL := 0;
	SIGNAL peak_post        : NATURAL := 0;
	SIGNAL rx_cnt           : NATURAL := 0;

	FUNCTION conf_adc (dest : STD_LOGIC_VECTOR(3 DOWNTO 0);
		rate                    : STD_LOGIC_VECTOR(1 DOWNTO 0);
		en                      : STD_LOGIC;
		ch                      : STD_LOGIC;
		ftw                     : INTEGER) RETURN tdma_min_data IS
	BEGIN
		RETURN "1010" & "0000" & dest & rate & en & ch &
		STD_LOGIC_VECTOR(to_unsigned(ftw, 16));
	END FUNCTION;

	FUNCTION conf_dp (nx : STD_LOGIC_VECTOR(3 DOWNTO 0);
		mode                 : STD_LOGIC_VECTOR(3 DOWNTO 0))
		RETURN tdma_min_data IS
	BEGIN
		RETURN "1001" & "0000" & nx & mode & x"0000";
	END FUNCTION;

BEGIN

	clock <= NOT clock AFTER CLK_HALF WHEN NOT stop ELSE
		'0';

	noc : ENTITY work.TdmaMin
		GENERIC MAP(ports => NUM_PORTS)
		PORT MAP
		(
			clock => clock,
			sends => send_port,
			recvs => recv_port
		);

	-- ADC-ASP (small clock_hz so SR_DIV is sim-friendly)
	adc : ENTITY work.adc_asp
		GENERIC MAP(clock_hz => 80_000, phase_bits => 16, lut_addr_bits => 10)
		PORT
		MAP
		(
		clock => clock,
		send  => send_port(NODE_ADC),
		recv  => recv_port(NODE_ADC)
		);

	avg : ENTITY work.avg_asp
		PORT
		MAP
		(
		clock => clock,
		send  => send_port(NODE_AVG),
		recv  => recv_port(NODE_AVG)
		);

	-- Configure downstream first (AVG: forward to sink, L=8), then
	-- start the source (ADC: forward to AVG, ch0, FTW=4096 ~= 500 Hz at
	-- Fs=8 kHz, where an L=8 moving average attenuates ~0.64).
	configurator : PROCESS
		PROCEDURE send_pkt (dst : NATURAL; pkt : tdma_min_data) IS
		BEGIN
			send_port(NODE_CFG).addr <=
			STD_LOGIC_VECTOR(to_unsigned(dst, tdma_min_addr'length));
			send_port(NODE_CFG).data <= pkt;
			WAIT FOR 20 ns;
			send_port(NODE_CFG).addr <= (OTHERS => '0');
			send_port(NODE_CFG).data <= (OTHERS => '0');
		END PROCEDURE;
	BEGIN
		send_port(NODE_CFG).addr <= (OTHERS => '0');
		send_port(NODE_CFG).data <= (OTHERS => '0');
		WAIT FOR 200 ns;

		-- 1) configure AVG: Next = sink(3), Mode = 0010 (L=8)
		send_pkt(NODE_AVG, conf_dp("0011", "0010"));
		WAIT FOR 200 ns;

		-- 2) start ADC: dest = AVG(2), SR=00, en, ch0, FTW=4096
		send_pkt(NODE_ADC, conf_adc("0010", "00", '1', '0', 4096));

		-- let the ADC + AVG warmups pass before measuring
		WAIT FOR 5 us;
		measuring <= true;

		WAIT FOR 40 us;
		measuring <= false;
		WAIT FOR 1 us;

		ASSERT rx_cnt > 0
		REPORT "PIPELINE FAIL: no filtered samples reached the sink"
			SEVERITY error;
		ASSERT peak_pre > 1000
		REPORT "PIPELINE FAIL: pre-filter signal too small / absent"
			SEVERITY error;
		ASSERT peak_post <= peak_pre + 2
		REPORT "PIPELINE FAIL: moving average did not attenuate "
			& "(post=" & INTEGER'image(peak_post)
			& " pre=" & INTEGER'image(peak_pre) & ")"
			SEVERITY error;
		REPORT "testbed_pipeline finished: peak_pre=" & INTEGER'image(peak_pre)
			& " peak_post=" & INTEGER'image(peak_post)
			& " rx_cnt=" & INTEGER'image(rx_cnt) SEVERITY note;

		stop <= true;
		WAIT;
	END PROCESS;

	-- Sink (port 3): receive-only
	send_port(NODE_SINK).addr <= (OTHERS => '0');
	send_port(NODE_SINK).data <= (OTHERS => '0');

	-- Snoop + peak tracking
	pre_valid                 <= '1' WHEN recv_port(NODE_AVG).data(31 DOWNTO 28) = "1000"
		ELSE
		'0';
	pre_sample <= signed(recv_port(NODE_AVG).data(15 DOWNTO 0));
	post_valid <= '1' WHEN recv_port(NODE_SINK).data(31 DOWNTO 28) = "1000"
		ELSE
		'0';
	post_sample <= signed(recv_port(NODE_SINK).data(15 DOWNTO 0));

	track : PROCESS (clock)
		VARIABLE a : NATURAL;
	BEGIN
		IF rising_edge(clock) THEN
			IF measuring THEN
				IF pre_valid = '1' THEN
					-- payload Dest (27:24) of ADC->AVG must be the AVG node
					-- (the ADC's configured Next), end-to-end via the NoC
					ASSERT recv_port(NODE_AVG).data(27 DOWNTO 24)
					= STD_LOGIC_VECTOR(to_unsigned(NODE_AVG, 4))
					REPORT "pre Data-Audio Dest (27:24) /= AVG node"
						SEVERITY error;
					a := ABS(to_integer(pre_sample));
					IF a > peak_pre THEN
						peak_pre <= a;
					END IF;
				END IF;
				IF post_valid = '1' THEN
					-- payload Dest (27:24) of AVG->sink must be the sink
					-- node (the AVG's configured Next)
					ASSERT recv_port(NODE_SINK).data(27 DOWNTO 24)
					= STD_LOGIC_VECTOR(to_unsigned(NODE_SINK, 4))
					REPORT "post Data-Audio Dest (27:24) /= sink node"
						SEVERITY error;
					rx_cnt <= rx_cnt + 1;
					a := ABS(to_integer(post_sample));
					IF a > peak_post THEN
						peak_post <= a;
					END IF;
				END IF;
			END IF;
		END IF;
	END PROCESS;

END ARCHITECTURE;
