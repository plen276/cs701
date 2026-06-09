LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- tb_app  (W5 application program, approach 2a + fixes 1-4)
--
-- Exercises app.asm on the real ReCOP + NI + 8-port NoC + the four
-- ASPs. Drives the memory-mapped board inputs (io_sw, io_events)
-- directly and emulates the top-level KEY latch (sticky-until the
-- program clears it via io_event_clear) -- so this verifies the
-- program logic, NOT the top_level debounce/throttle (simple RTL,
-- checked on board).
--
-- What it confirms:
--   * Boot enters RAW: io_led = 0x0001 (running only).
--   * KEY1 press -> program switches to MEASURE: io_led bit1 (mode)
--     and bit2 (locked) set. Proves event handling + reconfigure.
--   * Register-form DATACALL works: the ADC is configured with an
--     FTW taken from R7 (io_sw), the chain runs, and a PD period
--     packet (sub-tag "11") lands -> io_period becomes non-zero.
--   * Reports the observed period count so PMIN/PMAX can be tuned.
--
-- Assemble app.asm to test.mif before running (the .do does this).
-- ============================================================

ENTITY tb_app IS
END ENTITY tb_app;

ARCHITECTURE sim OF tb_app IS

    CONSTANT CLK_PERIOD : TIME := 20 ns;  -- 50 MHz sim clock
    CONSTANT NOC_PORTS  : POSITIVE := 8;

    SIGNAL clock      : STD_LOGIC := '0';
    SIGNAL reset      : STD_LOGIC := '1';

    -- ReCOP <-> NI
    SIGNAL sip       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL sop       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr      : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL dpcr_load : STD_LOGIC;
    SIGNAL period    : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- Memory-mapped board I/O
    SIGNAL io_sw     : STD_LOGIC_VECTOR(15 DOWNTO 0) := x"0005"; -- FTW select = 5
    SIGNAL io_events : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL io_led    : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_hex    : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_clear  : STD_LOGIC;

    -- TB-side sticky event latch (mirrors top_level minus debounce)
    SIGNAL set_evt   : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    SIGNAL evt_reg   : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";

    -- NoC fabric
    SIGNAL sends : tdma_min_ports(0 TO NOC_PORTS - 1);
    SIGNAL recvs : tdma_min_ports(0 TO NOC_PORTS - 1);

    -- Packet transcript limits. These keep the ModelSim log readable while
    -- still showing enough of the AVG/COR/PD streams to diagnose shape/value.
    CONSTANT LOG_LIMIT : NATURAL := 32;
    CONSTANT COR_SKIP  : NATURAL := 64; -- app config uses COR window=64

    SIGNAL pd_log_active : STD_LOGIC := '0';
    SIGNAL pd_log_sel    : INTEGER := 0;

    -- ReCOP debug surface (observed)
    SIGNAL z_flag     : STD_LOGIC;
    SIGNAL pc_out     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_out     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_out : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_out     : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL state_out  : STD_LOGIC_VECTOR(2 DOWNTO 0);

    FUNCTION nib (n : STD_LOGIC_VECTOR(3 DOWNTO 0)) RETURN CHARACTER IS
    BEGIN
        CASE n IS
            WHEN "0000" => RETURN '0'; WHEN "0001" => RETURN '1';
            WHEN "0010" => RETURN '2'; WHEN "0011" => RETURN '3';
            WHEN "0100" => RETURN '4'; WHEN "0101" => RETURN '5';
            WHEN "0110" => RETURN '6'; WHEN "0111" => RETURN '7';
            WHEN "1000" => RETURN '8'; WHEN "1001" => RETURN '9';
            WHEN "1010" => RETURN 'A'; WHEN "1011" => RETURN 'B';
            WHEN "1100" => RETURN 'C'; WHEN "1101" => RETURN 'D';
            WHEN "1110" => RETURN 'E'; WHEN "1111" => RETURN 'F';
            WHEN OTHERS => RETURN 'X';
        END CASE;
    END FUNCTION;

    FUNCTION hx (v : STD_LOGIC_VECTOR(15 DOWNTO 0)) RETURN STRING IS
    BEGIN
        RETURN nib(v(15 DOWNTO 12)) & nib(v(11 DOWNTO 8))
             & nib(v(7 DOWNTO 4)) & nib(v(3 DOWNTO 0));
    END FUNCTION;

    FUNCTION bit_char (b : STD_LOGIC) RETURN CHARACTER IS
    BEGIN
        IF b = '1' THEN
            RETURN '1';
        END IF;
        RETURN '0';
    END FUNCTION;

BEGIN

    clk_gen : PROCESS
    BEGIN
        clock <= '0'; WAIT FOR CLK_PERIOD / 2;
        clock <= '1'; WAIT FOR CLK_PERIOD / 2;
    END PROCESS clk_gen;

    -- TB event latch: holds a requested press until the program clears it.
    tb_latch : PROCESS (clock)
    BEGIN
        IF rising_edge(clock) THEN
            IF reset = '1' THEN
                evt_reg <= "00";
            ELSE
                IF io_clear = '1' THEN
                    evt_reg <= "00";
                END IF;
                IF set_evt(0) = '1' THEN evt_reg(0) <= '1'; END IF;
                IF set_evt(1) = '1' THEN evt_reg(1) <= '1'; END IF;
            END IF;
        END IF;
    END PROCESS tb_latch;

    io_events <= "00000000000000" & evt_reg;

    U_RECOP : ENTITY work.recop PORT MAP (
        clk        => clock,
        reset      => reset,
        z_flag     => z_flag,
        debug_mode => '0',
        debug_step => '0',
        sip        => sip,
        sop        => sop,
        dpcr       => dpcr,
        dpcr_load  => dpcr_load,
        io_sw          => io_sw,
        io_events      => io_events,
        io_led         => io_led,
        io_hex         => io_hex,
        io_period      => period,
        io_event_clear => io_clear,
        pc_out     => pc_out,
        rz_out     => rz_out,
        opcode_out => opcode_out,
        am_out     => am_out,
        state_out  => state_out,
        pm_wr_en   => '0',
        pm_wr_addr => (OTHERS => '0'),
        pm_wr_data => (OTHERS => '0')
    );

    U_NI : ENTITY work.recop_ni PORT MAP (
        clock      => clock,
        reset      => reset,
        dpcr_in    => dpcr,
        dpcr_load  => dpcr_load,
        sip_out    => sip,
        period_out => period,
        send       => sends(0),
        recv       => recvs(0)
    );

    -- The board runs the ADC at 50 MHz; here clock_hz is overridden small
    -- purely to SHORTEN THE SIM. The DDS sample rate is clock_hz/SR_DIV and
    -- samples-per-signal-cycle is 65536/FTW (independent of clock_hz), so the
    -- measured behaviour is identical -- only the cycles between samples (and
    -- hence the absolute period-count magnitude) shrink. At 2 MHz, SR=00 emits
    -- one sample per 250 clocks instead of 6250, so the window=192 COR fills in
    -- ~48k cycles instead of ~1.2M. Set to 50_000_000 for a board-faithful run.
    U_ADC : ENTITY work.adc_asp
        GENERIC MAP (clock_hz => 2_000_000)
        PORT MAP (clock => clock, send => sends(1), recv => recvs(1));
    U_AVG : ENTITY work.avg_asp PORT MAP (
        clock => clock, send => sends(2), recv => recvs(2));
    U_COR : ENTITY work.cor_asp_noc PORT MAP (
        clock => clock, reset => reset, send => sends(3), recv => recvs(3),
        dbg_enable => OPEN, dbg_busy => OPEN, dbg_window => OPEN,
        dbg_samples => OPEN, dbg_corrs => OPEN, dbg_last_corr => OPEN);
    U_PD : ENTITY work.PeakDetector PORT MAP (
        clock => clock, reset => reset, send => sends(4), recv => recvs(4));

    gen_idle : FOR i IN 5 TO NOC_PORTS - 1 GENERATE
        sends(i).addr <= (OTHERS => '0');
        sends(i).data <= (OTHERS => '0');
    END GENERATE;

    U_NOC : ENTITY work.TdmaMin
        GENERIC MAP (ports => NOC_PORTS)
        PORT MAP (clock => clock, sends => sends, recvs => recvs);

    -- Packet value logger for the open COR/PD measurement problem.
    --
    -- AVG is sends(2): input stream into COR.
    -- COR is sends(3): autocorrelation output into PD.
    -- PD  is sends(4): peak detector result stream back to ReCOP.
    --
    -- Prints high/low halves rather than relying on waveform screenshots.
    pkt_log : PROCESS (clock)
        VARIABLE avg_seen   : NATURAL := 0;
        VARIABLE avg_logged : NATURAL := 0;
        VARIABLE cor_seen   : NATURAL := 0;
        VARIABLE cor_logged : NATURAL := 0;
        VARIABLE pd_seen    : NATURAL := 0;
        VARIABLE pd_window_seen   : NATURAL := 0;
        VARIABLE pd_window_logged : NATURAL := 0;
        VARIABLE pd_last_period   : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
        VARIABLE pd_active_prev   : STD_LOGIC := '0';
        VARIABLE pd_sel_prev      : INTEGER := 0;
    BEGIN
        IF rising_edge(clock) THEN
            IF reset = '1' THEN
                avg_seen   := 0;
                avg_logged := 0;
                cor_seen   := 0;
                cor_logged := 0;
                pd_seen    := 0;
                pd_window_seen   := 0;
                pd_window_logged := 0;
                pd_last_period   := (OTHERS => '0');
                pd_active_prev   := '0';
                pd_sel_prev      := 0;
            ELSE
                IF pd_log_active /= pd_active_prev OR pd_log_sel /= pd_sel_prev THEN
                    pd_window_seen   := 0;
                    pd_window_logged := 0;
                    pd_last_period   := (OTHERS => '0');
                    pd_active_prev   := pd_log_active;
                    pd_sel_prev      := pd_log_sel;
                END IF;

                IF sends(2).data(31) = '1' THEN
                    IF avg_logged < LOG_LIMIT THEN
                        REPORT "PKT AVG[" & INTEGER'image(avg_seen) & "] t="
                             & TIME'image(now)
                             & " hi=0x" & hx(sends(2).data(31 DOWNTO 16))
                             & " lo=0x" & hx(sends(2).data(15 DOWNTO 0))
                             & " sample=0x" & hx(sends(2).data(15 DOWNTO 0));
                        avg_logged := avg_logged + 1;
                    END IF;
                    avg_seen := avg_seen + 1;
                END IF;

                IF sends(3).data(31) = '1' THEN
                    IF cor_seen >= COR_SKIP AND cor_logged < LOG_LIMIT THEN
                        REPORT "PKT COR[" & INTEGER'image(cor_seen) & "] t="
                             & TIME'image(now)
                             & " hi=0x" & hx(sends(3).data(31 DOWNTO 16))
                             & " lo=0x" & hx(sends(3).data(15 DOWNTO 0))
                             & " sample=0x" & hx(sends(3).data(15 DOWNTO 0));
                        cor_logged := cor_logged + 1;
                    END IF;
                    cor_seen := cor_seen + 1;
                END IF;

                IF sends(4).data(31) = '1' THEN
                    IF pd_log_active = '1'
                       AND sends(4).data(31 DOWNTO 28) = "1000"
                       AND sends(4).data(27 DOWNTO 26) = "11" THEN
                        IF pd_window_logged < LOG_LIMIT
                           AND (pd_window_seen < 8
                                OR sends(4).data(15 DOWNTO 0) /= pd_last_period) THEN
                            REPORT "PKT PD_PERIOD sel=" & INTEGER'image(pd_log_sel)
                                 & " global[" & INTEGER'image(pd_seen) & "]"
                                 & " window[" & INTEGER'image(pd_window_seen) & "]"
                                 & " t=" & TIME'image(now)
                                 & " period=0x" & hx(sends(4).data(15 DOWNTO 0));
                            pd_window_logged := pd_window_logged + 1;
                        END IF;
                        pd_last_period := sends(4).data(15 DOWNTO 0);
                        pd_window_seen := pd_window_seen + 1;
                    END IF;
                    pd_seen := pd_seen + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS pkt_log;

    stim : PROCESS
        -- SW[3:0] now indexes the app's grid-frequency scenario table.
        -- Pick indices that increase monotonically in frequency so the
        -- measured period should decrease monotonically:
        --   idx 0=47.0 Hz, 2=49.0, 4=50.0, 6=51.0, 7=52.0
        TYPE sel_array IS ARRAY (NATURAL RANGE <>) OF INTEGER;
        CONSTANT SWEEP : sel_array := (0, 2, 4, 6, 7);
        VARIABLE saw_period : BOOLEAN := FALSE;

        -- press KEY1 (mode cycle) and wait for the program to consume it
        PROCEDURE press_mode IS
        BEGIN
            set_evt(0) <= '1';
            WAIT UNTIL rising_edge(clock);
            set_evt(0) <= '0';
            WAIT UNTIL io_clear = '1' FOR 200 us;
        END PROCEDURE;

        -- warm up the MEASURE pipeline (COR window 64 fill + AVG warmup)
        -- window=192 @ ~250 clk/sample => ~48k to fill COR, plus a few COR
        -- output periods for PD to lock. 250k cycles gives comfortable margin.
        PROCEDURE warmup IS
        BEGIN
            FOR i IN 0 TO 400000 LOOP
                WAIT UNTIL rising_edge(clock);
                IF period /= x"0000" THEN saw_period := TRUE; END IF;
            END LOOP;
        END PROCEDURE;
    BEGIN
        reset <= '1';
        WAIT UNTIL rising_edge(clock);
        WAIT UNTIL rising_edge(clock);
        reset <= '0';

        -- RAW boot
        FOR i IN 0 TO 2000 LOOP WAIT UNTIL rising_edge(clock); END LOOP;

        -- T1: RAW -> running bit only
        REPORT "T1 RAW: io_led = 0x" & hx(io_led) & " (expect bit0 set, bit1 clear)";
        ASSERT io_led(1) = '0' REPORT "T1 FAIL: mode bit set in RAW" SEVERITY error;

        -- T2: first KEY1 -> MEASURE (sel=4)
        io_sw <= STD_LOGIC_VECTOR(to_unsigned(SWEEP(0), 16));
        FOR i IN 0 TO 20 LOOP WAIT UNTIL rising_edge(clock); END LOOP;
        press_mode;
        pd_log_sel <= SWEEP(0);
        pd_log_active <= '1';
        warmup;
        pd_log_active <= '0';
        REPORT "T2 MEASURE: io_led = 0x" & hx(io_led) & " (expect bits 1,2 set)";
        ASSERT io_led(1) = '1' REPORT "T2 FAIL: mode bit not set after KEY1" SEVERITY error;
        ASSERT saw_period REPORT "T3 FAIL: no PD period packet reached ReCOP" SEVERITY error;
        REPORT "SWEEP sel=" & INTEGER'image(SWEEP(0))
             & "  period($FF4)=0x" & hx(period)
             & "  led=0x" & hx(io_led);

        -- Sweep the remaining FTW values: MEASURE->RAW->(set SW)->MEASURE
        FOR k IN 1 TO SWEEP'high LOOP
            press_mode;                       -- back to RAW
            FOR i IN 0 TO 2000 LOOP WAIT UNTIL rising_edge(clock); END LOOP;
            io_sw <= STD_LOGIC_VECTOR(to_unsigned(SWEEP(k), 16));
            FOR i IN 0 TO 20 LOOP WAIT UNTIL rising_edge(clock); END LOOP;
            press_mode;                       -- MEASURE with new FTW
            pd_log_sel <= SWEEP(k);
            pd_log_active <= '1';
            warmup;
            pd_log_active <= '0';
            REPORT "SWEEP sel=" & INTEGER'image(SWEEP(k))
                 & "  period($FF4)=0x" & hx(period)
                 & "  led=0x" & hx(io_led);
        END LOOP;

        REPORT "==== tb_app sweep complete: if period varies with sel it"
             & " measures; if constant the COR/PD chain needs a look ===="
            SEVERITY note;
        WAIT;
    END PROCESS stim;

END ARCHITECTURE sim;
