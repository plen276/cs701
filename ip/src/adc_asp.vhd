LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;
USE ieee.math_real.ALL; -- used ONLY to build the sine LUT constant

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- ADC-ASP  -  DDS signal source for the IP frequency-measurement
-- pipeline.
--
-- Unlike Lab 2's adc_asp (a bridge from the physical audio codec),
-- this ASP *emulates* an ADC: it synthesises a power-system signal
-- from an internal sine LUT using a DDS phase accumulator, so the
-- test frequency is tunable live by packet.
--
-- Drop-in compatible with the Lab 2 TDMA-MIN NoC (spec.md #6, #7):
--   * no reset port, no NODE_ID generic - the TdmaMin generate
--     loop only wires clock/slot/push/pull/send/recv
--   * all state is initialised at declaration (Lab 2 convention)
--   * idle cycles drive all-zeros: bit 31 = '0' makes the NI treat
--     it as "nothing to send" (TdmaMinInterface line 57)
--
-- Packet formats (routing dest travels on send.addr, NoC fabric,
-- NOT in the payload - Lab 2 convention, spec.md #4/#5):
--
--   Conf-ADC  (decoded, type "1010"):
--     31-28 type | 27-24 unused(0) | 23-20 Next | 19-18 SR
--       | 17 En | 16 Ch | 15-0 FTW
--     NOTE: bits 15-0 are "Unused" in the project-specs table;
--     this ASP repurposes them as the 16-bit DDS Frequency Tuning
--     Word (spec.md decision #8). Conf-ADC is a TEAM-SHARED packet
--     - this extension must be agreed team-wide (spec.md OPEN #1/#2).
--
--   Data-Audio (emitted, type "1000"):
--     31-28 "1000" | 27-24 Dest | 23-17 zeros | 16 Ch | 15-0 sample
--     Dest mirrors the forward node (Next) - the Lab 2 NoC routes on
--     send.addr, but Dest is also stamped in 27-24 so downstream
--     ASPs / ReCOP can read it from the payload (packet_format.md).
-- ============================================================

ENTITY adc_asp IS
	GENERIC (
		clock_hz      : POSITIVE := 50_000_000; -- system clock, for SR divider
		phase_bits    : POSITIVE := 16;         -- = Conf-ADC FTW field width
		lut_addr_bits : POSITIVE := 10          -- LUT depth = 2**lut_addr_bits
	);
	PORT
	(
		clock : IN STD_LOGIC;
		send  : OUT tdma_min_port;
		recv  : IN tdma_min_port
	);
END ENTITY;

ARCHITECTURE rtl OF adc_asp IS

	---------------------------------------------------------------------------
	-- Packet protocol constants (named, single source of truth)
	---------------------------------------------------------------------------
	CONSTANT TYPE_CONF_ADC         : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1010";
	CONSTANT TYPE_DATA_AUDIO       : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1000";

	-- Build a Data-Audio payload:
	--   type(31:28) | Dest(27:24) | Reserved 0s(23:17) | Ch(16) | sample(15:0)
	-- Defined once so the bit layout is not an opaque string literal.
	FUNCTION make_data_audio (dest : STD_LOGIC_VECTOR(3 DOWNTO 0);
		ch                             : STD_LOGIC;
		sample                         : signed(15 DOWNTO 0))
		RETURN tdma_min_data IS
	BEGIN
		RETURN TYPE_DATA_AUDIO & dest & "0000000" & ch &
		STD_LOGIC_VECTOR(sample);
	END FUNCTION;

	-- Routing address for the NoC fabric: 8-bit, low nibble = node id.
	FUNCTION route_addr (dest : STD_LOGIC_VECTOR(3 DOWNTO 0))
		RETURN tdma_min_addr IS
	BEGIN
		RETURN "0000" & dest;
	END FUNCTION;

	---------------------------------------------------------------------------
	-- Sine ROM: one full period, signed 16-bit, full-scale +/-32767.
	-- math_real is evaluated at elaboration to fill the constant; Quartus
	-- synthesises this as a ROM (no .mif needed).
	---------------------------------------------------------------------------
	CONSTANT lut_depth : POSITIVE := 2 ** lut_addr_bits;
	TYPE lut_t IS ARRAY(0 TO lut_depth - 1) OF signed(15 DOWNTO 0);

	FUNCTION build_sine RETURN lut_t IS
		VARIABLE t : lut_t;
	BEGIN
		FOR i IN t'RANGE LOOP
			t(i) := to_signed(
			INTEGER(round(sin(2.0 * MATH_PI * real(i)/real(lut_depth)) * 32767.0)),
			16);
		END LOOP;
		RETURN t;
	END FUNCTION;

	CONSTANT SINE_LUT : lut_t := build_sine;

	---------------------------------------------------------------------------
	-- Sample-rate divisor table, indexed by the 2-bit Conf-ADC SR field.
	-- OPEN DECISION #5 (spec.md): these Fs values are placeholders. Higher Fs
	-- gives more samples per 50 Hz period for the downstream filter; calibrate
	-- with the team / TA.
	--
	-- INVARIANT (see TestAspAdc D4 assertion): every entry must be >= 2.
	-- A divisor of 1 makes a channel emit every clock; the ch0-priority
	-- arbiter would then perpetually defer ch1 (ch1 starvation). All real
	-- (50 MHz) and tested configs satisfy this with large margin.
	---------------------------------------------------------------------------
	TYPE div_table_t IS ARRAY(0 TO 3) OF POSITIVE;
	CONSTANT SR_DIV : div_table_t := (
		0 => clock_hz / 8000,  -- SR=00 ->  8 kHz
		1 => clock_hz / 16000, -- SR=01 -> 16 kHz
		2 => clock_hz / 32000, -- SR=10 -> 32 kHz
		3 => clock_hz / 48000  -- SR=11 -> 48 kHz
	);

	---------------------------------------------------------------------------
	-- Per-channel configuration latched from Conf-ADC packets.
	---------------------------------------------------------------------------
	SIGNAL dest_0, dest_1     : STD_LOGIC_VECTOR(3 DOWNTO 0)      := "0010";
	SIGNAL rate_0, rate_1     : STD_LOGIC_VECTOR(1 DOWNTO 0)      := "00";
	SIGNAL enable_0, enable_1 : STD_LOGIC                         := '0';
	SIGNAL ftw_0, ftw_1       : unsigned(phase_bits - 1 DOWNTO 0) := (OTHERS => '0');

BEGIN

	---------------------------------------------------------------------------
	-- Conf-ADC decode. One configuration row per channel (selected by bit 16).
	-- A delivered packet is visible on recv.data for exactly one clock
	-- (combinational NoC fabric + single recv register), so a clocked
	-- decode latches each Conf-ADC exactly once.
	---------------------------------------------------------------------------
	decode : PROCESS (clock)
	BEGIN
		IF rising_edge(clock) THEN
			IF recv.data(31 DOWNTO 28) = TYPE_CONF_ADC THEN
				IF recv.data(16) = '0' THEN
					dest_0   <= recv.data(23 DOWNTO 20);
					rate_0   <= recv.data(19 DOWNTO 18);
					enable_0 <= recv.data(17);
					ftw_0    <= unsigned(recv.data(phase_bits - 1 DOWNTO 0));
				ELSE
					dest_1   <= recv.data(23 DOWNTO 20);
					rate_1   <= recv.data(19 DOWNTO 18);
					enable_1 <= recv.data(17);
					ftw_1    <= unsigned(recv.data(phase_bits - 1 DOWNTO 0));
				END IF;
			END IF;
		END IF;
	END PROCESS;

	---------------------------------------------------------------------------
	-- Signal generation + packet emission.
	-- Each channel has its own sample-rate counter and DDS phase accumulator:
	--   phase += FTW  ->  index = top lut_addr_bits of phase
	--   f_out = FTW * Fs / 2**phase_bits   (tunable independently of Fs)
	-- At most one packet is emitted per clock; if both channels are due in the
	-- same cycle, ch0 goes first and ch1 the next cycle (its sample is latched
	-- so it stays correct). Idle cycles send all-zeros.
	---------------------------------------------------------------------------
	generate_and_emit : PROCESS (clock)
		VARIABLE cnt_0, cnt_1     : NATURAL                           := 0;
		VARIABLE phase_0, phase_1 : unsigned(phase_bits - 1 DOWNTO 0) := (OTHERS => '0');
		VARIABLE idx_0, idx_1     : INTEGER RANGE 0 TO lut_depth - 1  := 0;
		VARIABLE pend_0, pend_1   : BOOLEAN                           := false;
		VARIABLE smp_0, smp_1     : signed(15 DOWNTO 0)               := (OTHERS => '0');
	BEGIN
		IF rising_edge(clock) THEN

			-- Channel 0 timer / DDS
			IF enable_0 = '1' THEN
				IF cnt_0 = 0 THEN
					cnt_0   := SR_DIV(to_integer(unsigned(rate_0))) - 1;
					phase_0 := phase_0 + ftw_0;
					idx_0   := to_integer(phase_0(phase_bits - 1 DOWNTO phase_bits - lut_addr_bits));
					smp_0   := SINE_LUT(idx_0);
					pend_0  := true;
				ELSE
					cnt_0 := cnt_0 - 1;
				END IF;
			END IF;

			-- Channel 1 timer / DDS
			IF enable_1 = '1' THEN
				IF cnt_1 = 0 THEN
					cnt_1   := SR_DIV(to_integer(unsigned(rate_1))) - 1;
					phase_1 := phase_1 + ftw_1;
					idx_1   := to_integer(phase_1(phase_bits - 1 DOWNTO phase_bits - lut_addr_bits));
					smp_1   := SINE_LUT(idx_1);
					pend_1  := true;
				ELSE
					cnt_1 := cnt_1 - 1;
				END IF;
			END IF;

			-- Emit one packet, ch0 priority
			IF pend_0 THEN
				send.addr <= route_addr(dest_0);
				send.data <= make_data_audio(dest_0, '0', smp_0);
				pend_0 := false;
			ELSIF pend_1 THEN
				send.addr <= route_addr(dest_1);
				send.data <= make_data_audio(dest_1, '1', smp_1);
				pend_1 := false;
			ELSE
				send.addr <= (OTHERS => '0');
				send.data <= (OTHERS => '0');
			END IF;

		END IF;
	END PROCESS;

END ARCHITECTURE;
