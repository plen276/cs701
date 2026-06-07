-- ============================================================
-- tb_cor_unit.vhd
--
-- Isolation test for cor_asp ALONE (no NoC, no wrapper, no other
-- ASPs). Drives pkt_in / pkt_in_valid directly:
--   * configures window=64, interval=1, shift=20, enable
--   * streams a clean signed sine, ONE Data packet every SAMPLE_GAP
--     cycles (so the datapath is always idle when the next sample
--     lands -- exactly the steady-state COR sees in the system)
--   * logs result (16-bit packed) and result_full (40-bit acc) for
--     each correlation output.
--
-- Expected (from the ideal-fold-correlation Python check):
--   result_full swings ~ +/-1.6e10, peaks ~T/2 samples apart;
--   result (>>20) swings ~ +/-15000 as a clean 2x sinusoid.
-- If instead result is +/-2000 noise, the bug is inside cor_asp.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;
USE work.cor_asp_pkg.ALL;

ENTITY tb_cor_unit IS
END ENTITY tb_cor_unit;

ARCHITECTURE sim OF tb_cor_unit IS
    CONSTANT CLK_PERIOD  : TIME                          := 20 ns;
    CONSTANT SAMPLE_GAP  : INTEGER                       := 80;   -- cycles between samples (>= n+5)
    CONSTANT T_PERIOD    : REAL                          := 55.0; -- signal period in samples
    CONSTANT AMP         : REAL                          := 31835.0;

    SIGNAL clk           : STD_LOGIC                     := '0';
    SIGNAL reset         : STD_LOGIC                     := '1';
    SIGNAL pkt_in        : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL pkt_in_valid  : STD_LOGIC                     := '0';
    SIGNAL pkt_out       : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL pkt_out_valid : STD_LOGIC;

    -- expose the internal full accumulator via a hierarchical reference
    -- is not portable; instead read the 16-bit packed result from pkt_out
    -- and also the dbg_last_corr from the entity.
    SIGNAL dbg_last_corr : STD_LOGIC_VECTOR(15 DOWNTO 0);

    FUNCTION nib (n      : STD_LOGIC_VECTOR(3 DOWNTO 0)) RETURN CHARACTER IS
        CONSTANT hexs        : STRING := "0123456789ABCDEF";
    BEGIN
        RETURN hexs(to_integer(unsigned(n)) + 1);
    END FUNCTION;
    FUNCTION hx (v : STD_LOGIC_VECTOR(15 DOWNTO 0)) RETURN STRING IS
    BEGIN
        RETURN nib(v(15 DOWNTO 12)) & nib(v(11 DOWNTO 8))
        & nib(v(7 DOWNTO 4)) & nib(v(3 DOWNTO 0));
    END FUNCTION;
BEGIN

    clk <= NOT clk AFTER CLK_PERIOD/2;

    DUT : ENTITY work.cor_asp
        GENERIC MAP(
            MY_NODE_ID    => NODE_ID_COR,
            DEFAULT_DEST  => NODE_ID_PD,
            DEFAULT_SHIFT => 6
        )
        PORT MAP
        (
            clk           => clk,
            reset         => reset,
            pkt_in        => pkt_in,
            pkt_in_valid  => pkt_in_valid,
            pkt_out       => pkt_out,
            pkt_out_valid => pkt_out_valid,
            dbg_enable    => OPEN,
            dbg_busy      => OPEN,
            dbg_window    => OPEN,
            dbg_samples   => OPEN,
            dbg_corrs     => OPEN,
            dbg_last_corr => dbg_last_corr
        );

    -- log every correlation result packet COR emits
    log : PROCESS (clk)
        VARIABLE c : INTEGER := 0;
    BEGIN
        IF rising_edge(clk) THEN
            IF pkt_out_valid = '1' THEN
                REPORT "COR_OUT[" & INTEGER'image(c) & "] result=0x"
                    & hx(pkt_out(15 DOWNTO 0))
                    & " (" & INTEGER'image(to_integer(signed(pkt_out(15 DOWNTO 0)))) & ")";
                c := c + 1;
            END IF;
        END IF;
    END PROCESS;

    stim : PROCESS
        VARIABLE s            : INTEGER;
        TYPE real_arr IS ARRAY (NATURAL RANGE <>) OF REAL;
        CONSTANT PERIODS : real_arr := (60.0, 40.0, 30.0, 20.0, 17.0);

        PROCEDURE send_pkt (d : STD_LOGIC_VECTOR(31 DOWNTO 0)) IS
        BEGIN
            pkt_in       <= d;
            pkt_in_valid <= '1';
            WAIT UNTIL rising_edge(clk);
            pkt_in       <= (OTHERS => '0');
            pkt_in_valid <= '0';
        END PROCEDURE;

        PROCEDURE gap (n : INTEGER) IS
        BEGIN
            FOR i IN 1 TO n LOOP WAIT UNTIL rising_edge(clk);
            END LOOP;
        END PROCEDURE;
    BEGIN
        reset <= '1';
        gap(4);
        reset <= '0';
        gap(4);

        -- configure: window=64, interval=1, shift=20, enable
        -- Conf-DP = 1001 | dest(COR=3) | next(PD=4) | mode | value
        send_pkt(make_conf_dp(NODE_ID_COR, NODE_ID_PD, MODE_SET_WINDOW, x"0040"));
        gap(8);
        send_pkt(make_conf_dp(NODE_ID_COR, NODE_ID_PD, MODE_SET_INTERVAL, x"0001"));
        gap(8);
        send_pkt(make_conf_dp(NODE_ID_COR, NODE_ID_PD, MODE_SET_SHIFT, x"0014"));
        gap(8);
        send_pkt(make_conf_dp(NODE_ID_COR, NODE_ID_PD, MODE_SET_ENABLE, x"0001"));
        gap(8);

        -- sweep signal periods; for each, stream a clean sine
        FOR p IN PERIODS'RANGE LOOP
            REPORT "=== PERIOD T=" & INTEGER'image(INTEGER(PERIODS(p)))
                 & " (expect COR sign-change spacing ~T/2="
                 & INTEGER'image(INTEGER(PERIODS(p)/2.0)) & ") ===";
            FOR k IN 0 TO 200 LOOP
                s := INTEGER(round(AMP * sin(2.0 * MATH_PI * real(k)/PERIODS(p))));
                send_pkt(make_data(NODE_ID_COR, '0',
                STD_LOGIC_VECTOR(to_signed(s, 16))));
                gap(SAMPLE_GAP - 1);
            END LOOP;
        END LOOP;

        REPORT "tb_cor_unit done";
        WAIT;
    END PROCESS;

END ARCHITECTURE sim;
