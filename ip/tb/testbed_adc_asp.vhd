LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- TESTBED for the ADC-ASP (as opposed to the unit testbench
-- TestAspAdc, which pokes the DUT ports directly).
--
-- This exercises the ADC-ASP under "realistic external
-- requirements" (BRIEF): it runs INSIDE the real TDMA-MIN NoC,
-- configured by packets that travel THROUGH the network, with
-- the streamed samples received THROUGH the network by a sink.
--
--   port 0  adc_asp        - DUT
--   port 1  configurator  - one-shot Conf-ADC packets (ReCOP
--                           stand-in; GP-2 replaces this)
--   port 2  sink          - receives Data-Audio over the NoC
--   port 3  unused        - tied off
--
-- Realistic-config note: in the full pipeline the order is
-- Conf-DAC -> Conf-DP -> Conf-ADC (project-specs line 95).
-- Only Conf-ADC applies here (no DAC/DP nodes yet).
--
-- ModelSim needs altera_mf (scfifo) + the 'ip' library for
-- TdmaMinFifo - see the run notes at the bottom of this file.
-- ============================================================

ENTITY testbed_adc_asp IS
END ENTITY;

ARCHITECTURE sim OF testbed_adc_asp IS

	CONSTANT PORT
	S                  : POSITIVE  := 4;
	CONSTANT CLK_HALF  : TIME      := 10 ns; -- 20 ns period

	CONSTANT NODE_ADC  : NATURAL   := 0;
	CONSTANT NODE_CFG  : NATURAL   := 1;
	CONSTANT NODE_SINK : NATURAL   := 2;

	SIGNAL clock       : STD_LOGIC := '1';
	SIGNAL stop        : BOOLEAN   := false;

	SIGNAL send_port   : tdma_min_ports(0 TO PORT
	S - 1);
	SIGNAL recv_port : tdma_min_ports(0 TO PORT
	S - 1);

	-- Sink observation (for waveform + end-of-sim check)
	SIGNAL rx_valid         : STD_LOGIC;
	SIGNAL rx_ch            : STD_LOGIC;
	SIGNAL rx_sample        : signed(15 DOWNTO 0);
	SIGNAL rx_cnt0          : NATURAL := 0;
	SIGNAL rx_cnt1          : NATURAL := 0;

	-- Conf-ADC packet builder (type "1010"), per report/packet_format.md.
	-- (The `dest` arg populates the Next field 23-20 - the ADC's forward
	-- node; legacy arg name kept until the entity-naming pass.)
	--   31-28 type | 27-24 Dest | 23-20 Next | 19-18 SR | 17 En | 16 Ch | 15-0 FTW
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

	---------------------------------------------------------------------------
	-- Clock
	---------------------------------------------------------------------------
	clock <= NOT clock AFTER CLK_HALF WHEN NOT stop ELSE
		'0';

	---------------------------------------------------------------------------
	-- NoC fabric (instantiates one TdmaMinInterface + TdmaMinFifo per port)
	---------------------------------------------------------------------------
	noc : ENTITY work.TdmaMin
		GENERIC MAP(
			ports => PORT
			S)
		PORT MAP
		(
			clock => clock,
			sends => send_port,
			recvs => recv_port
		);
	);

	---------------------------------------------------------------------------
	-- DUT: ADC-ASP on port 0.  Small clock_hz so SR_DIV is sim-friendly
	-- (Fs = 80000/8000 = 8 kHz at SR=00); the DDS math is unchanged.
	---------------------------------------------------------------------------
	dut : ENTITY work.adc_asp
		GENERIC MAP(
			clock_hz      => 80_000,
			phase_bits    => 16,
			lut_addr_bits => 10
		)
		PORT
		MAP (
		clock => clock,
		send  => send_port(NODE_ADC),
		recv  => recv_port(NODE_ADC)
		);

	---------------------------------------------------------------------------
	-- Configurator (port 1): emits Conf-ADC packets THROUGH the NoC to the
	-- ADC node.  Each packet is held for exactly one clock so the NI FIFO
	-- enqueues a single copy (req = send.data(31)); then it idles with zeros.
	---------------------------------------------------------------------------
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

		-- Enable CH1 -> sink, FTW=4096 (500 Hz, dual-channel + arbitration)
		send_pkt(NODE_ADC, conf_adc("0010", "00", '1', '1', 4096));

		WAIT FOR 30 us;

		-- Live retune CH0 to FTW=1024 (125 Hz) - frequency change by packet
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

	---------------------------------------------------------------------------
	-- Sink (port 2): receives Data-Audio over the NoC, counts per channel.
	---------------------------------------------------------------------------
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
				-- Verify the payload Dest (27:24) end-to-end through the
				-- real NoC: it must equal the configured Next, which here
				-- is the sink's own node id.
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

-- ============================================================
-- ModelSim run notes
-- ============================================================
-- TdmaMinFifo wraps Altera's scfifo, so the altera_mf simulation
-- library is required, and TdmaMinFifo must live in library 'ip'
-- (TdmaMinInterface does: library ip; entity ip.TdmaMinFifo).
--
--   # Altera megafunction sim library (path per Quartus install)
--   vlib altera_mf
--   vmap altera_mf altera_mf
--   vcom -work altera_mf \
--     "$QUARTUS_ROOTDIR/eda/sim_lib/altera_mf_components.vhd"
--   vcom -work altera_mf \
--     "$QUARTUS_ROOTDIR/eda/sim_lib/altera_mf.vhd"
--
--   # FIFO into library 'ip'
--   vlib ip
--   vcom -work ip ip/ip/TdmaMinFifo/TdmaMinFifo.vhd
--
--   # Design + testbed into work (order matters)
--   vlib work
--   vcom ip/src/TdmaMin/TdmaMinTypes.vhd
--   vcom ip/src/TdmaMin/TdmaMinSlots.vhd
--   vcom ip/src/TdmaMin/TdmaMinSwitch.vhd
--   vcom ip/src/TdmaMin/TdmaMinStage.vhd
--   vcom ip/src/TdmaMin/TdmaMinFabric.vhd
--   vcom ip/src/TdmaMin/TdmaMinInterface.vhd
--   vcom ip/src/TdmaMin/TdmaMin.vhd
--   vcom ip/src/adc_asp.vhd
--   vcom ip/tb/testbed_adc_asp.vhd
--
--   vsim -L altera_mf -L ip work.testbed_adc_asp
--   add wave -radix decimal sim:/testbed_adc_asp/rx_sample
--   add wave sim:/testbed_adc_asp/rx_valid sim:/testbed_adc_asp/rx_ch \
--            sim:/testbed_adc_asp/rx_cnt0 sim:/testbed_adc_asp/rx_cnt1
--   run -all
