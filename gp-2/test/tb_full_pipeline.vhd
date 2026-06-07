LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- tb_full_pipeline  (W2.4 complete: full 4-ASP pipeline)
--
-- ADC -> AVG -> COR -> PD -> ReCOP over the real 8-port NoC.
-- Extends tb_cor_pipeline by instantiating PeakDetector on
-- port 4 and watching recvs(0) for PD result packets.
--
-- Topology
--   Port 0  ReCOP + recop_ni        (result destination)
--   Port 1  adc_asp                 (DDS sine, SR=48kHz, FTW=0x0044)
--   Port 2  avg_asp                 (moving average L=8)
--   Port 3  cor_asp via cor_asp_noc (window=8, interval=1, shift=3)
--   Port 4  PeakDetector            (En=1, results -> ReCOP)
--   Port 5..7  idle
--
-- Program (full_pipeline.asm, assembled to test.mif)
--   PD configured first (downstream-first ordering), ADC last.
--   PD enabled immediately so it starts cycling max/min/peak_time
--   output from reset values (zero) before real peaks arrive.
--
-- Checks
--   T1  A Data-Audio packet (bits 31:28 = "1000") arrives at
--       recvs(0) — proves PD is sending results to ReCOP via NoC.
--   T2  bits 27:26 of the packet are a valid PD sub-tag (01, 10,
--       or 11 — not 00) — confirms the sub-tag overwrite bug is fixed.
--   T3  bits 25:17 = "000000000" — padding zeros between sub-tag
--       and value are clean (regression for the bit-overwrite fix).
-- ============================================================

ENTITY tb_full_pipeline IS
END ENTITY tb_full_pipeline;

ARCHITECTURE sim OF tb_full_pipeline IS

    CONSTANT CLK_PERIOD : TIME := 20 ns;  -- 50 MHz sim clock
    CONSTANT NOC_PORTS  : POSITIVE := 8;

    SIGNAL clock      : STD_LOGIC := '0';
    SIGNAL reset      : STD_LOGIC := '1';
    SIGNAL debug_mode : STD_LOGIC := '0';
    SIGNAL debug_step : STD_LOGIC := '0';

    -- ReCOP <-> NI
    SIGNAL sip       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL sop       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr      : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL dpcr_load : STD_LOGIC;

    -- NoC fabric
    SIGNAL sends : tdma_min_ports(0 TO NOC_PORTS - 1);
    SIGNAL recvs : tdma_min_ports(0 TO NOC_PORTS - 1);

    -- ReCOP debug
    SIGNAL z_flag     : STD_LOGIC;
    SIGNAL pc_out     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_out     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_out : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_out     : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL state_out  : STD_LOGIC_VECTOR(2 DOWNTO 0);

    -- VHDL-93 hex print helpers
    FUNCTION nibble_to_hex (n : STD_LOGIC_VECTOR(3 DOWNTO 0)) RETURN CHARACTER IS
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

    FUNCTION slv_to_hex (v : STD_LOGIC_VECTOR) RETURN STRING IS
        CONSTANT n_nib : NATURAL := v'length / 4;
        VARIABLE s     : STRING(1 TO n_nib);
    BEGIN
        FOR i IN 0 TO n_nib - 1 LOOP
            s(i + 1) := nibble_to_hex(v(v'high - 4 * i DOWNTO v'high - 4 * i - 3));
        END LOOP;
        RETURN s;
    END FUNCTION;

BEGIN

    clk_gen : PROCESS
    BEGIN
        clock <= '0'; WAIT FOR CLK_PERIOD / 2;
        clock <= '1'; WAIT FOR CLK_PERIOD / 2;
    END PROCESS clk_gen;

    U_RECOP : ENTITY work.recop PORT MAP (
        clk        => clock,
        reset      => reset,
        z_flag     => z_flag,
        debug_mode => debug_mode,
        debug_step => debug_step,
        sip        => sip,
        sop        => sop,
        dpcr       => dpcr,
        dpcr_load  => dpcr_load,
        pc_out     => pc_out,
        rz_out     => rz_out,
        opcode_out => opcode_out,
        am_out     => am_out,
        state_out  => state_out
    );

    U_NI : ENTITY work.recop_ni PORT MAP (
        clock     => clock,
        reset     => reset,
        dpcr_in   => dpcr,
        dpcr_load => dpcr_load,
        sip_out   => sip,
        send      => sends(0),
        recv      => recvs(0)
    );

    U_ADC : ENTITY work.adc_asp PORT MAP (
        clock => clock,
        send  => sends(1),
        recv  => recvs(1)
    );

    U_AVG : ENTITY work.avg_asp PORT MAP (
        clock => clock,
        send  => sends(2),
        recv  => recvs(2)
    );

    U_COR : ENTITY work.cor_asp_noc PORT MAP (
        clock         => clock,
        reset         => reset,
        send          => sends(3),
        recv          => recvs(3),
        dbg_enable    => OPEN,
        dbg_busy      => OPEN,
        dbg_window    => OPEN,
        dbg_samples   => OPEN,
        dbg_corrs     => OPEN,
        dbg_last_corr => OPEN
    );

    U_PD : ENTITY work.PeakDetector PORT MAP (
        clock => clock,
        reset => reset,
        send  => sends(4),
        recv  => recvs(4)
    );

    gen_idle : FOR i IN 5 TO NOC_PORTS - 1 GENERATE
        sends(i).addr <= (OTHERS => '0');
        sends(i).data <= (OTHERS => '0');
    END GENERATE;

    U_NOC : ENTITY work.TdmaMin
        GENERIC MAP (ports => NOC_PORTS)
        PORT MAP (
            clock => clock,
            sends => sends,
            recvs => recvs
        );

    stim : PROCESS
        -- PD is enabled immediately on config, starts cycling
        -- max/min/peak_time from reset-initialised zero values.
        -- First PD packet arrives at recvs(0) within ~100 cycles
        -- (boot + config + NoC latency). 5000 cycles is generous.
        CONSTANT TIMEOUT_CYCLES : NATURAL := 5000;
        VARIABLE saw : BOOLEAN := FALSE;
    BEGIN
        reset <= '1';
        WAIT UNTIL rising_edge(clock);
        WAIT UNTIL rising_edge(clock);
        reset <= '0';

        -- T1: wait for first Data-Audio packet from PD at recvs(0)
        FOR j IN 0 TO TIMEOUT_CYCLES LOOP
            WAIT UNTIL rising_edge(clock);
            WAIT FOR 1 ns;
            IF recvs(0).data(31 DOWNTO 28) = "1000" THEN
                saw := TRUE;
                EXIT;
            END IF;
        END LOOP;

        ASSERT saw
            REPORT "T1 FAIL: no PD result packet at recvs(0) within "
                 & integer'image(TIMEOUT_CYCLES) & " cycles"
                 & " (last = 0x" & slv_to_hex(recvs(0).data) & ")"
            SEVERITY error;

        IF saw THEN
            REPORT "T1 PASS: PD result at recvs(0), data = 0x"
                 & slv_to_hex(recvs(0).data)
                SEVERITY note;

            -- T2: sub-tag bits 27:26 must be non-zero (01/10/11)
            ASSERT recvs(0).data(27 DOWNTO 26) /= "00"
                REPORT "T2 FAIL: sub-tag is 00 - overwrite bug not fixed,"
                     & " got 0x" & slv_to_hex(recvs(0).data)
                SEVERITY error;
            IF recvs(0).data(27 DOWNTO 26) /= "00" THEN
                REPORT "T2 PASS: PD sub-tag = "
                     & STD_LOGIC'image(recvs(0).data(27))
                     & STD_LOGIC'image(recvs(0).data(26))
                    SEVERITY note;
            END IF;

            -- T3: padding bits 25:17 must be zero (clean overwrite fix)
            ASSERT recvs(0).data(25 DOWNTO 17) = "000000000"
                REPORT "T3 FAIL: padding bits 25:17 not zero, got 0x"
                     & slv_to_hex(recvs(0).data)
                SEVERITY error;
            IF recvs(0).data(25 DOWNTO 17) = "000000000" THEN
                REPORT "T3 PASS: padding bits clean"
                    SEVERITY note;
            END IF;
        END IF;

        REPORT "==== tb_full_pipeline complete ====" SEVERITY note;
        WAIT;
    END PROCESS stim;

END ARCHITECTURE sim;
