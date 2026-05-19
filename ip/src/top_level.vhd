LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- IP project DE1-SoC top level.
--
-- Purpose: give the Quartus project a synthesisable root so it
-- compiles and ModelSim can be launched from it. It also makes
-- the board do something visible (LED sine sweep) as a bring-up
-- sanity check.
--
-- Nodes on the 4-port TDMA-MIN NoC:
--   port 0  adc_asp          - the DDS ADC-ASP under development
--   port 1  config sender   - one-shot Conf-ADC at start-up
--                             (stand-in for ReCOP, which takes
--                              this role in GP-2)
--   port 2  monitor sink    - latches the streamed sample and
--                             drives LEDR / HEX
--   port 3  unused          - send tied to zeros
--
-- KEY(0) low = reset (re-arms the one-shot config).
-- LEDR      = top 10 bits of the latest sample (sine sweeps LEDs).
-- HEX3..0   = latest sample in hex. HEX5,HEX4 blank.
--
-- NOTE: ADC-ASP unit verification is done with tb/TestAspAdc
-- (no NoC, no FIFO). This top is for Quartus / board bring-up;
-- simulating it needs TdmaMinFifo compiled into library 'ip'
-- plus the Altera megafunction sim libraries.
-- ============================================================

ENTITY top_level IS
	GENERIC (
		ports : POSITIVE := 4
	);
	PORT
	(
		CLOCK_50 : IN STD_LOGIC;
		KEY      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		SW       : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
		LEDR     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
		HEX0     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX1     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX2     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX3     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX4     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX5     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE structural OF top_level IS

	SIGNAL clock          : STD_LOGIC;
	SIGNAL reset          : STD_LOGIC;

	SIGNAL send_port      : tdma_min_ports(0 TO ports - 1);
	SIGNAL recv_port      : tdma_min_ports(0 TO ports - 1);

	CONSTANT NODE_ADC     : NATURAL       := 0;
	CONSTANT NODE_CFG     : NATURAL       := 1;
	CONSTANT NODE_MON     : NATURAL       := 2;

	-- Conf-ADC: enable ch0, forward data to NODE_MON (addr 2), SR=00,
	-- FTW=410. With clock_hz=50e6 and SR=00, Fs=8 kHz, so
	-- f_out = 410 * 8000 / 65536 ~= 50.05 Hz.
	-- Layout: 31-28 type | 27-24 0 | 23-20 dest | 19-18 SR | 17 en | 16 ch | 15-0 FTW
	CONSTANT CONF_ADC_CH0 : tdma_min_data :=
	"1010" & "0000" & "0010" & "00" & '1' & '0' &
	STD_LOGIC_VECTOR(to_unsigned(410, 16));

	SIGNAL sample_latch  : signed(15 DOWNTO 0) := (OTHERS => '0');

	-- Minimal active-low hex digit decoder (avoids pulling in a
	-- separate hex_to_7seg file; segments are active low).
	FUNCTION to_seg (nib : STD_LOGIC_VECTOR(3 DOWNTO 0))
		RETURN STD_LOGIC_VECTOR IS
	BEGIN
		CASE nib IS
			WHEN x"0"   => RETURN "1000000";
			WHEN x"1"   => RETURN "1111001";
			WHEN x"2"   => RETURN "0100100";
			WHEN x"3"   => RETURN "0110000";
			WHEN x"4"   => RETURN "0011001";
			WHEN x"5"   => RETURN "0010010";
			WHEN x"6"   => RETURN "0000010";
			WHEN x"7"   => RETURN "1111000";
			WHEN x"8"   => RETURN "0000000";
			WHEN x"9"   => RETURN "0010000";
			WHEN x"A"   => RETURN "0001000";
			WHEN x"B"   => RETURN "0000011";
			WHEN x"C"   => RETURN "1000110";
			WHEN x"D"   => RETURN "0100001";
			WHEN x"E"   => RETURN "0000110";
			WHEN OTHERS => RETURN "0001110"; -- F
		END CASE;
	END FUNCTION;

BEGIN

	clock <= CLOCK_50;
	reset <= NOT KEY(0);

	---------------------------------------------------------------------------
	-- NoC fabric (one NI per port, generated inside TdmaMin)
	---------------------------------------------------------------------------
	noc : ENTITY work.TdmaMin
		GENERIC MAP(ports => ports)
		PORT MAP
		(
			clock => clock,
			sends => send_port,
			recvs => recv_port
		);

	---------------------------------------------------------------------------
	-- ADC-ASP under test
	---------------------------------------------------------------------------
	adc : ENTITY work.adc_asp
		GENERIC MAP(
			clock_hz      => 50_000_000,
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
	-- One-shot config sender (port 1). Emits CONF_ADC_CH0 once after
	-- reset is released, then stays quiet. Replaced by ReCOP in GP-2.
	---------------------------------------------------------------------------
	config : PROCESS (clock)
		VARIABLE armed  : BOOLEAN := TRUE;
		VARIABLE wait_c : NATURAL := 0;
	BEGIN
		IF rising_edge(clock) THEN
			IF reset = '1' THEN
				armed  := TRUE;
				wait_c := 0;
				send_port(NODE_CFG).addr <= (OTHERS => '0');
				send_port(NODE_CFG).data <= (OTHERS => '0');
			ELSIF armed THEN
				IF wait_c < 16 THEN
					wait_c := wait_c + 1;
					send_port(NODE_CFG).addr <= (OTHERS => '0');
					send_port(NODE_CFG).data <= (OTHERS => '0');
				ELSE
					-- deliver to the ADC node (routing addr = 0)
					send_port(NODE_CFG).addr <=
					STD_LOGIC_VECTOR(to_unsigned(NODE_ADC, tdma_min_addr'length));
					send_port(NODE_CFG).data <= CONF_ADC_CH0;
					armed := FALSE;
				END IF;
			ELSE
				send_port(NODE_CFG).addr <= (OTHERS => '0');
				send_port(NODE_CFG).data <= (OTHERS => '0');
			END IF;
		END IF;
	END PROCESS;

	---------------------------------------------------------------------------
	-- Monitor sink (port 2). Latches the streamed Data-Audio sample.
	---------------------------------------------------------------------------
	send_port(NODE_MON).addr <= (OTHERS => '0');
	send_port(NODE_MON).data <= (OTHERS => '0');

	monitor : PROCESS (clock)
	BEGIN
		IF rising_edge(clock) THEN
			IF recv_port(NODE_MON).data(31 DOWNTO 28) = "1000" THEN
				sample_latch <= signed(recv_port(NODE_MON).data(15 DOWNTO 0));
			END IF;
		END IF;
	END PROCESS;

	-- Unused port
	send_port(3).addr <= (OTHERS => '0');
	send_port(3).data <= (OTHERS => '0');

	---------------------------------------------------------------------------
	-- Board outputs
	---------------------------------------------------------------------------
	LEDR              <= STD_LOGIC_VECTOR(sample_latch(15 DOWNTO 6));

	HEX0              <= to_seg(STD_LOGIC_VECTOR(sample_latch(3 DOWNTO 0)));
	HEX1              <= to_seg(STD_LOGIC_VECTOR(sample_latch(7 DOWNTO 4)));
	HEX2              <= to_seg(STD_LOGIC_VECTOR(sample_latch(11 DOWNTO 8)));
	HEX3              <= to_seg(STD_LOGIC_VECTOR(sample_latch(15 DOWNTO 12)));
	HEX4              <= "1111111";
	HEX5              <= "1111111";

END ARCHITECTURE;
