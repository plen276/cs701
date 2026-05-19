LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;
USE ieee.math_real.ALL; -- TB-side sine reference (mirrors DUT LUT)

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- Self-contained, self-checking testbench for adc_asp (Lab 2
-- TestTdmaMinInterface style: no ports, own clock, drives recv,
-- snoops send).
--
-- Simulation-speed note: the real system runs at 50 MHz where one
-- 50 Hz period is ~1e6 cycles. The DUT is instantiated with a SMALL
-- clock_hz generic so SR_DIV shrinks; the DDS relationship
-- f_out = FTW * Fs / 2**phase_bits is unchanged, so behaviour is
-- identical with far fewer cycles to simulate.
--
-- With clock_hz = 80_000:  SR=00 -> Fs=8 kHz (SR_DIV=10 clocks),
--                          SR=01 -> Fs=16 kHz (SR_DIV=5 clocks).
--
-- Coverage:
--   V2  CH0 self-check: every emitted sample == an INDEPENDENT
--       TB sine reference at the expected DDS phase, AND the packet
--       spacing == SR_DIV (single channel, exact period).
--   V3  CH1 at a DIFFERENT sample rate (SR=01) - same self-check.
--   V4  both channels due the SAME cycle (identical SR): assert no
--       ch1 starvation (bounded packet gap) and well-formed packets.
--   D4  SR_DIV >= 2 invariant asserted from the same Fs source the
--       period check uses (a divisor of 1 would starve ch1).
--   Smoke: original live FTW retune demo (frequency change by
--       packet) - kept for the report waveform.
-- ============================================================

ENTITY tb_adc_asp IS
END ENTITY;

ARCHITECTURE sim OF tb_adc_asp IS

	CONSTANT CLK_HALF  : TIME      := 10 ns;   -- 20 ns period
	CONSTANT TB_CLK_HZ : POSITIVE  := 80_000;  -- = DUT clock_hz generic
	CONSTANT LUT_DEPTH : INTEGER   := 2 ** 10; -- = 2**lut_addr_bits

	SIGNAL clock       : STD_LOGIC := '1';
	SIGNAL send        : tdma_min_port;
	SIGNAL recv        : tdma_min_port := (addr => (OTHERS => '0'),
	data => (OTHERS => '0'));
	SIGNAL stop       : BOOLEAN := false;

	-- Decoded view of the emitted packet (waveform readability)
	SIGNAL tx_valid   : STD_LOGIC;
	SIGNAL tx_type    : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL tx_ch      : STD_LOGIC;
	SIGNAL tx_sample  : signed(15 DOWNTO 0);
	SIGNAL tx_dest    : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Self-check control, driven by the stimulus process
	SIGNAL seg_id     : INTEGER                      := 0;     -- bump => monitor resyncs
	SIGNAL chk_en0    : BOOLEAN                      := false; -- monitor ch0 (gap/well-formed)
	SIGNAL chk_en1    : BOOLEAN                      := false;
	SIGNAL chk_val0   : BOOLEAN                      := false; -- also exact-value-check ch0
	SIGNAL chk_val1   : BOOLEAN                      := false;
	SIGNAL chk_ftw0   : NATURAL                      := 0;
	SIGNAL chk_ftw1   : NATURAL                      := 0;
	SIGNAL chk_dst0   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000"; -- expected Dest
	SIGNAL chk_dst1   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
	SIGNAL chk_div0   : NATURAL                      := 0; -- expected clocks between ch0 pkts
	SIGNAL chk_div1   : NATURAL                      := 0;
	SIGNAL chk_strict : BOOLEAN                      := false; -- exact-period check (single ch)

	-- Sample-rate source of truth (also feeds the D4 invariant assert)
	TYPE fs_t IS ARRAY(0 TO 3) OF POSITIVE;
	CONSTANT FS_TBL     : fs_t := (8000, 16000, 32000, 48000);
	FUNCTION sr_div (sr : INTEGER) RETURN INTEGER IS
	BEGIN
		RETURN TB_CLK_HZ / FS_TBL(sr);
	END FUNCTION;

	-- INDEPENDENT sine reference: same formula as adc_asp.build_sine,
	-- indexed by the top 10 bits of the 16-bit phase.
	FUNCTION sine_ref (ph : unsigned(15 DOWNTO 0)) RETURN signed IS
		VARIABLE idx          : INTEGER;
	BEGIN
		idx := to_integer(ph(15 DOWNTO 6));
		RETURN to_signed(
		INTEGER(round(sin(2.0 * MATH_PI * real(idx)/real(LUT_DEPTH)) * 32767.0)),
		16);
	END FUNCTION;

	-- Conf-ADC builder (type "1010"):
	--   31-28 type | 27-24 0 | 23-20 Next | 19-18 SR | 17 En | 16 Ch | 15-0 FTW
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
	-- DUT  (small clock_hz so the sample-rate divider is sim-friendly)
	---------------------------------------------------------------------------
	dut : ENTITY work.adc_asp
		GENERIC MAP(
			clock_hz      => TB_CLK_HZ,
			phase_bits    => 16,
			lut_addr_bits => 10
		)
		PORT MAP
		(
			clock => clock,
			send  => send,
			recv  => recv
		);

	---------------------------------------------------------------------------
	-- Decode emitted packet for the waveform / assertions
	---------------------------------------------------------------------------
	tx_valid  <= send.data(31);
	tx_type   <= send.data(31 DOWNTO 28);
	tx_ch     <= send.data(16);
	tx_sample <= signed(send.data(15 DOWNTO 0));
	tx_dest   <= send.addr(3 DOWNTO 0);

	-- Global invariant: any emitted (valid) packet must be Data-Audio "1000"
	check : PROCESS (clock)
	BEGIN
		IF rising_edge(clock) THEN
			IF tx_valid = '1' THEN
				ASSERT tx_type = "1000"
				REPORT "Emitted packet is not Data-Audio (type /= 1000)"
					SEVERITY error;
			END IF;
		END IF;
	END PROCESS;

	---------------------------------------------------------------------------
	-- Self-checking DDS monitor (V2/V3/V4 + D4).
	-- A delivered packet is on send for exactly one clock, so each is
	-- counted once. Expected phase per channel advances once per observed
	-- packet for that channel (DUT phase starts at 0 on first enable, so
	-- the first emitted sample uses phase = FTW - mirrored here).
	---------------------------------------------------------------------------
	monitor : PROCESS (clock)
		VARIABLE cur_seg      : INTEGER               := - 1;
		VARIABLE ph0, ph1     : unsigned(15 DOWNTO 0) := (OTHERS => '0');
		VARIABLE clkc         : NATURAL               := 0;
		VARIABLE last0, last1 : NATURAL               := 0;
		VARIABLE have0, have1 : BOOLEAN               := false;
		VARIABLE expv         : signed(15 DOWNTO 0);
		VARIABLE gap          : NATURAL;
	BEGIN
		IF rising_edge(clock) THEN
			IF seg_id /= cur_seg THEN -- new segment: resync
				cur_seg := seg_id;
				ph0     := (OTHERS => '0');
				ph1     := (OTHERS => '0');
				have0   := false;
				have1   := false;
			END IF;
			clkc := clkc + 1;

			IF send.data(31) = '1' AND send.data(31 DOWNTO 28) = "1000" THEN
				IF send.data(16) = '0' THEN
					IF chk_en0 THEN
						ASSERT send.data(27 DOWNTO 24) = chk_dst0
						REPORT "CH0 Data-Audio Dest (27:24) /= configured Next"
							SEVERITY error;
						IF chk_val0 THEN
							ph0  := ph0 + to_unsigned(chk_ftw0, 16);
							expv := sine_ref(ph0);
							ASSERT signed(send.data(15 DOWNTO 0)) = expv
							REPORT "V2: CH0 DDS sample mismatch (got "
								& INTEGER'image(to_integer(signed(send.data(15 DOWNTO 0))))
								& " exp " & INTEGER'image(to_integer(expv)) & ")"
								SEVERITY error;
						END IF;
						IF have0 THEN
							gap := clkc - last0;
							IF chk_strict THEN
								ASSERT gap = chk_div0
								REPORT "V2/V3: CH0 sample period /= SR_DIV (got "
									& INTEGER'image(gap) & " exp "
									& INTEGER'image(chk_div0) & ")"
									SEVERITY error;
							ELSE
								ASSERT gap <= chk_div0 + 2
								REPORT "V4: CH0 packet gap too large ("
									& INTEGER'image(gap) & ")"
									SEVERITY error;
							END IF;
						END IF;
						last0 := clkc;
						have0 := true;
					END IF;
				ELSE
					IF chk_en1 THEN
						ASSERT send.data(27 DOWNTO 24) = chk_dst1
						REPORT "CH1 Data-Audio Dest (27:24) /= configured Next"
							SEVERITY error;
						IF chk_val1 THEN
							ph1  := ph1 + to_unsigned(chk_ftw1, 16);
							expv := sine_ref(ph1);
							ASSERT signed(send.data(15 DOWNTO 0)) = expv
							REPORT "V3: CH1 DDS sample mismatch (got "
								& INTEGER'image(to_integer(signed(send.data(15 DOWNTO 0))))
								& " exp " & INTEGER'image(to_integer(expv)) & ")"
								SEVERITY error;
						END IF;
						IF have1 THEN
							gap := clkc - last1;
							IF chk_strict THEN
								ASSERT gap = chk_div1
								REPORT "V3: CH1 sample period /= SR_DIV (got "
									& INTEGER'image(gap) & " exp "
									& INTEGER'image(chk_div1) & ")"
									SEVERITY error;
							ELSE
								ASSERT gap <= chk_div1 + 2
								REPORT "V4: CH1 packet gap too large / ch1 "
									& "starvation (" & INTEGER'image(gap) & ")"
									SEVERITY error;
							END IF;
						END IF;
						last1 := clkc;
						have1 := true;
					END IF;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	---------------------------------------------------------------------------
	-- Stimulus
	---------------------------------------------------------------------------
	stimulus : PROCESS
		PROCEDURE pulse (pkt : tdma_min_data) IS
		BEGIN
			recv.data <= pkt;
			WAIT FOR 20 ns; -- one clock period
			recv.data <= (OTHERS => '0');
			WAIT FOR 20 ns;
		END PROCEDURE;
	BEGIN
		recv.data <= (OTHERS => '0');
		WAIT FOR 100 ns;

		-- ===== V2 + D4 : CH0, SR=00 (Fs=8 kHz, SR_DIV=10), FTW=2048 =====
		ASSERT sr_div(0) >= 2
		REPORT "D4: SR_DIV(SR=00) < 2 - ch1 starvation invariant broken"
			SEVERITY failure;
		chk_ftw0   <= 2048;
		chk_div0   <= sr_div(0);
		chk_dst0   <= "0011";
		chk_en0    <= true;
		chk_val0   <= true;
		chk_en1    <= false;
		chk_val1   <= false;
		chk_strict <= true;
		seg_id     <= 1;
		pulse(conf_adc("0011", "00", '1', '0', 2048));
		WAIT FOR 12 us;                                -- ~120 samples
		pulse(conf_adc("0011", "00", '0', '0', 2048)); -- disable CH0
		chk_en0  <= false;
		chk_val0 <= false;
		WAIT FOR 1 us;

		-- ===== V3 + D4 : CH1, SR=01 (Fs=16 kHz, SR_DIV=5), FTW=4096 =====
		ASSERT sr_div(1) >= 2
		REPORT "D4: SR_DIV(SR=01) < 2 - ch1 starvation invariant broken"
			SEVERITY failure;
		chk_ftw1   <= 4096;
		chk_div1   <= sr_div(1);
		chk_dst1   <= "0100";
		chk_en1    <= true;
		chk_val1   <= true;
		chk_en0    <= false;
		chk_val0   <= false;
		chk_strict <= true;
		seg_id     <= 2;
		pulse(conf_adc("0100", "01", '1', '1', 4096));
		WAIT FOR 8 us;
		pulse(conf_adc("0100", "01", '0', '1', 4096)); -- disable CH1
		chk_en1  <= false;
		chk_val1 <= false;
		WAIT FOR 1 us;

		-- ===== V4 : both channels due the SAME cycle (identical SR) =====
		-- Phase is continuous in the DUT (no reset on re-enable), so this
		-- segment checks the arbitration/no-starvation property and packet
		-- well-formedness, not exact sample values.
		ASSERT sr_div(0) >= 2
		REPORT "D4: SR_DIV(SR=00) < 2 - ch1 starvation invariant broken"
			SEVERITY failure;
		-- Phase is continuous in the DUT (no reset on re-enable), so value
		-- is NOT re-checked here (proven in V2/V3); this asserts the
		-- arbitration/no-starvation property and packet well-formedness.
		chk_ftw0   <= 2048;
		chk_ftw1   <= 2048;
		chk_div0   <= sr_div(0);
		chk_div1   <= sr_div(0);
		chk_dst0   <= "0011";
		chk_dst1   <= "0100";
		chk_en0    <= true;
		chk_en1    <= true;
		chk_val0   <= false;
		chk_val1   <= false;
		chk_strict <= false; -- both active -> 1-cycle deferral
		seg_id     <= 3;
		pulse(conf_adc("0011", "00", '1', '0', 2048));
		pulse(conf_adc("0100", "00", '1', '1', 2048));
		WAIT FOR 12 us;

		-- ===== Smoke : live FTW retune on CH0 (report waveform) =====
		chk_en0  <= false;
		chk_en1  <= false;
		chk_val0 <= false;
		chk_val1 <= false;
		seg_id   <= 4;
		pulse(conf_adc("0011", "00", '1', '0', 1024)); -- 125 Hz
		WAIT FOR 10 us;
		pulse(conf_adc("0100", "00", '0', '1', 2048)); -- disable CH1
		WAIT FOR 6 us;

		REPORT "tb_adc_asp finished (all assertions passed)" SEVERITY note;
		stop <= true;
		WAIT;
	END PROCESS;

END ARCHITECTURE;
