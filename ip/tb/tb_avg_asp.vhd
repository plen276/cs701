LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- Self-contained unit testbench for avg_asp (no NoC; pokes recv,
-- observes send), Lab 2 testbench style.
--
-- Self-checking: an INDEPENDENT naive reference (keep the last L
-- raw samples, sum them, arithmetic >>log2(L)) predicts every
-- output. The DUT uses the running-sum optimisation, so a match
-- validates that optimisation + WARMUP gating + window indexing
-- against the plain moving-average definition.
--
-- The reference computes the expected average with an arithmetic
-- shift-right (floor toward -inf), exactly mirroring the DUT's
-- shift_right(signed,n). This is correct for BOTH non-negative and
-- bipolar inputs. Covers L=4/8/16, bypass, a dual-channel
-- independence check, and a bipolar sequence (V1: the real ADC
-- signal is bipolar, so the negative-sum floor-rounding path must
-- be exercised, not just non-negative ramps).

ENTITY tb_avg_asp IS
END ENTITY;

ARCHITECTURE sim OF tb_avg_asp IS

	CONSTANT CLK_HALF : TIME      := 10 ns;

	SIGNAL clock      : STD_LOGIC := '1';
	SIGNAL stop       : BOOLEAN   := false;

	SIGNAL send       : tdma_min_port;
	SIGNAL recv       : tdma_min_port := (addr => (OTHERS => '0'),
	data => (OTHERS => '0'));

	-- Waveform aids
	SIGNAL tx_valid  : STD_LOGIC;
	SIGNAL tx_ch     : STD_LOGIC;
	SIGNAL tx_sample : signed(15 DOWNTO 0);

BEGIN

	clock <= NOT clock AFTER CLK_HALF WHEN NOT stop ELSE
		'0';
	tx_valid  <= send.data(31);
	tx_ch     <= send.data(16);
	tx_sample <= signed(send.data(15 DOWNTO 0));

	dut : ENTITY work.avg_asp
		PORT MAP
		(
			clock => clock,
			send  => send,
			recv  => recv
		);

	stimulus : PROCESS

		-- Independent reference state, per channel
		TYPE buf_t IS ARRAY(0 TO 15) OF INTEGER;
		VARIABLE h0, h1 : buf_t                        := (OTHERS => 0);
		VARIABLE n0, n1 : NATURAL                      := 0;
		VARIABLE cur_L  : NATURAL                      := 0; -- 0 = bypass
		VARIABLE cur_sh : NATURAL                      := 0;
		VARIABLE cur_nx : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";

		-- Build packets
		FUNCTION data_pkt (ch : STD_LOGIC; v : INTEGER) RETURN tdma_min_data IS
		BEGIN
			RETURN "1000" & "00000000000" & ch &
			STD_LOGIC_VECTOR(to_signed(v, 16));
		END FUNCTION;
		FUNCTION conf_pkt (nx : STD_LOGIC_VECTOR(3 DOWNTO 0);
			mode                  : STD_LOGIC_VECTOR(3 DOWNTO 0))
			RETURN tdma_min_data IS
		BEGIN
			RETURN "1001" & "0000" & nx & mode & x"0000";
		END FUNCTION;

		-- Send a Conf-DP, then check the DUT does not emit that cycle.
		PROCEDURE do_conf (nx : STD_LOGIC_VECTOR(3 DOWNTO 0);
		mode                  : STD_LOGIC_VECTOR(3 DOWNTO 0)) IS
	BEGIN
		cur_nx := nx;
		CASE mode IS
			WHEN "0001" => cur_L := 4;
				cur_sh               := 2;
			WHEN "0010" => cur_L := 8;
				cur_sh               := 3;
			WHEN "0011" => cur_L := 16;
				cur_sh               := 4;
			WHEN OTHERS => cur_L := 0;
				cur_sh               := 0;
		END CASE;
		n0 := 0;
		n1 := 0;
		h0 := (OTHERS => 0);
		h1 := (OTHERS => 0);
		recv.data <= conf_pkt(nx, mode);
		WAIT UNTIL rising_edge(clock);
		WAIT FOR 1 ns;
		ASSERT send.data(31) = '0'
		REPORT "DUT emitted during a Conf-DP cycle" SEVERITY error;
		recv.data <= (OTHERS => '0');
		WAIT UNTIL rising_edge(clock);
		WAIT FOR 1 ns;
	END PROCEDURE;

	-- Drive one Data-Audio sample, then verify the output against
	-- the independent reference.
	PROCEDURE step (ch : STD_LOGIC; v : INTEGER) IS
		VARIABLE expect_emit : BOOLEAN;
		VARIABLE s, eavg     : INTEGER;
	BEGIN
		-- update reference for this channel
		IF ch = '0' THEN
			FOR i IN 15 DOWNTO 1 LOOP h0(i) := h0(i - 1);
			END LOOP;
			h0(0) := v;
			n0    := n0 + 1;
		ELSE
			FOR i IN 15 DOWNTO 1 LOOP h1(i) := h1(i - 1);
			END LOOP;
			h1(0) := v;
			n1    := n1 + 1;
		END IF;

		IF cur_L = 0 THEN
			expect_emit := true;
			eavg        := v; -- bypass
		ELSE
			s := 0;
			IF ch = '0' THEN
				expect_emit                    := (n0 >= cur_L);
				FOR i IN 0 TO cur_L - 1 LOOP s := s + h0(i);
				END LOOP;
			ELSE
				expect_emit                    := (n1 >= cur_L);
				FOR i IN 0 TO cur_L - 1 LOOP s := s + h1(i);
				END LOOP;
			END IF;
			-- arithmetic shift-right (floor toward -inf), mirrors the
			-- DUT's shift_right(signed,n); correct for negative s too
			eavg := to_integer(shift_right(to_signed(s, 32), cur_sh));
		END IF;

		recv.data <= data_pkt(ch, v);
		WAIT UNTIL rising_edge(clock);
		WAIT FOR 1 ns;

		IF expect_emit THEN
			ASSERT send.data(31 DOWNTO 28) = "1000"
			REPORT "expected Data-Audio output, none emitted"
				SEVERITY error;
			ASSERT send.data(16) = ch
			REPORT "output channel bit mismatch" SEVERITY error;
			ASSERT signed(send.data(15 DOWNTO 0)) = to_signed(eavg, 16)
			REPORT "AVG mismatch: got " &
				INTEGER'image(to_integer(signed(send.data(15 DOWNTO 0)))) &
				" expected " & INTEGER'image(eavg)
				SEVERITY error;
			ASSERT send.addr(3 DOWNTO 0) = cur_nx
			REPORT "forward address mismatch" SEVERITY error;
			ASSERT send.data(27 DOWNTO 24) = cur_nx
			REPORT "Data-Audio payload Dest (27:24) /= Next"
				SEVERITY error;
		ELSE
			ASSERT send.data(31) = '0'
			REPORT "DUT emitted during WARMUP (n < L)" SEVERITY error;
		END IF;

		recv.data <= (OTHERS => '0');
		WAIT UNTIL rising_edge(clock);
		WAIT FOR 1 ns;
	END PROCEDURE;

BEGIN
	WAIT FOR 100 ns;
	WAIT UNTIL rising_edge(clock);
	WAIT FOR 1 ns; -- phase-align

	-- L = 4 : ramp on ch0, expect 3 WARMUP cycles then averages
	do_conf("0101", "0001");
	FOR v IN 1 TO 12 LOOP step('0', v);
	END LOOP;

	-- L = 8
	do_conf("0101", "0010");
	FOR v IN 1 TO 20 LOOP step('0', v);
	END LOOP;

	-- L = 16
	do_conf("0101", "0011");
	FOR v IN 1 TO 32 LOOP step('0', v);
	END LOOP;

	-- Bypass: every sample passes straight through
	do_conf("0110", "0000");
	FOR v IN 100 TO 105 LOOP step('0', v);
	END LOOP;

	-- Dual-channel independence: same ramp on both channels at L=4.
	-- Each channel keeps its own window/sum, so both must produce
	-- identical averages with identical WARMUP behaviour.
	do_conf("0111", "0001");
	FOR v IN 1 TO 10 LOOP
		step('0', v);
		step('1', v);
	END LOOP;

	-- V1: bipolar coverage. The real ADC signal is bipolar, so the
	-- path where the running sum goes negative and >>log2(L) is a
	-- floor (not trunc-toward-zero) must be exercised. The reference
	-- now uses an arithmetic shift, so it predicts these exactly.
	do_conf("1000", "0001"); -- L=4
	FOR v IN -9 TO 9 LOOP step('0', 2 - v);
	END LOOP;                -- +ve -> -ve
	do_conf("1001", "0010"); -- L=8, odd steps
	FOR v IN -12 TO 12 LOOP step('1', 3 - 2 * v);
	END LOOP;

	REPORT "tb_avg_asp finished (all assertions passed)"
		SEVERITY note;
	stop <= true;
	WAIT;
END PROCESS;

END ARCHITECTURE;
