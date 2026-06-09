LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- tb_reconfig_demo  (W6.4)
--
-- End-to-end sim of the ReCOP self-reload board demo. This is the
-- first TB that exercises the full runtime PM-reload datapath:
--
--   ReCOP(0) --DATACALL--> recop_ni --> TdmaMin fabric -->
--   reconfig_node(6) --> prog_mem_dp port B (inside ReCOP)
--
-- ReCOP runs reconfig_demo.asm from test.mif. It shows a BEFORE
-- state, then (on a simulated KEY1) streams "Program B" into PM at
-- word 0x1000 through the reconfig node and jumps to it. Program B
-- writes the AFTER state, which can only happen if the words it
-- executes were genuinely written into PM at runtime.
--
-- Topology
--   Port 0  ReCOP + recop_ni
--   Port 6  reconfig_node  (drives ReCOP's pm_wr_* port)
--   Ports 1..5, 7  idle
--
-- Checks
--   T1  io_hex reaches 0x1111  (BEFORE state -- loader is running)
--   T2  first PM write is addr 0x1000, data 0x4010 (the reconfig
--       path actually wrote Program B's first word)
--   T3  io_hex reaches the SWITCH value 0x0155 (AFTER state -- ReCOP
--       executed words loaded at 0x1000 with an operator-chosen value
--       that could not have been in the bitstream)  <-- end-to-end proof
--   T4  io_led = 0x0002         (AFTER LED state)
--   T5  after changing io_sw, io_hex STAYS 0x0155 -- the value is frozen
--       into PM code, not read live (the reconfiguration signature)
-- ============================================================

ENTITY tb_reconfig_demo IS
END ENTITY tb_reconfig_demo;

ARCHITECTURE sim OF tb_reconfig_demo IS

    CONSTANT CLK_PERIOD : TIME := 20 ns;
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

    -- Memory-mapped board I/O
    SIGNAL io_events : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL io_sw     : STD_LOGIC_VECTOR(15 DOWNTO 0) := x"0155"; -- operator value at reload
    SIGNAL io_led    : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_hex    : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_clear  : STD_LOGIC;

    -- ReCOP <-> reconfig PM write port
    SIGNAL pm_wr_en   : STD_LOGIC;
    SIGNAL pm_wr_addr : STD_LOGIC_VECTOR(14 DOWNTO 0);
    SIGNAL pm_wr_data : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- ReCOP debug
    SIGNAL pc_out     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_out     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_out : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_out     : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL state_out  : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL z_flag     : STD_LOGIC;

    -- NoC fabric
    SIGNAL sends : tdma_min_ports(0 TO NOC_PORTS - 1);
    SIGNAL recvs : tdma_min_ports(0 TO NOC_PORTS - 1);

    -- First-write capture (combinational monitor below)
    SIGNAL first_wr_seen : BOOLEAN := FALSE;
    SIGNAL first_wr_addr : STD_LOGIC_VECTOR(14 DOWNTO 0) := (OTHERS => '0');
    SIGNAL first_wr_data : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    CONSTANT EXP_FIRST_ADDR : STD_LOGIC_VECTOR(14 DOWNTO 0)
        := STD_LOGIC_VECTOR(TO_UNSIGNED(16#1000#, 15));
    CONSTANT EXP_FIRST_DATA : STD_LOGIC_VECTOR(15 DOWNTO 0) := x"4010";

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
        CONSTANT n_nib : NATURAL := (v'length + 3) / 4;
        VARIABLE padded : STD_LOGIC_VECTOR(n_nib * 4 - 1 DOWNTO 0) := (OTHERS => '0');
        VARIABLE s      : STRING(1 TO n_nib);
    BEGIN
        padded(v'length - 1 DOWNTO 0) := v;
        FOR i IN 0 TO n_nib - 1 LOOP
            s(n_nib - i) := nibble_to_hex(padded(4 * i + 3 DOWNTO 4 * i));
        END LOOP;
        RETURN s;
    END FUNCTION;

BEGIN

    clk_gen : PROCESS
    BEGIN
        clock <= '0'; WAIT FOR CLK_PERIOD / 2;
        clock <= '1'; WAIT FOR CLK_PERIOD / 2;
    END PROCESS clk_gen;

    -- ===== ReCOP core (port 0) =====
    U_RECOP : ENTITY work.recop PORT MAP (
        clk            => clock,
        reset          => reset,
        z_flag         => z_flag,
        debug_mode     => debug_mode,
        debug_step     => debug_step,
        sip            => sip,
        sop            => sop,
        dpcr           => dpcr,
        dpcr_load      => dpcr_load,
        io_sw          => io_sw,
        io_events      => io_events,
        io_led         => io_led,
        io_hex         => io_hex,
        io_period      => (OTHERS => '0'),
        io_event_clear => io_clear,
        pc_out         => pc_out,
        rz_out         => rz_out,
        opcode_out     => opcode_out,
        am_out         => am_out,
        state_out      => state_out,
        pm_wr_en       => pm_wr_en,
        pm_wr_addr     => pm_wr_addr,
        pm_wr_data     => pm_wr_data
    );

    -- ===== Network interface (port 0) =====
    U_NI : ENTITY work.recop_ni PORT MAP (
        clock      => clock,
        reset      => reset,
        dpcr_in    => dpcr,
        dpcr_load  => dpcr_load,
        sip_out    => sip,
        period_out => OPEN,
        send       => sends(0),
        recv       => recvs(0)
    );

    -- ===== Reconfig node (port 6) drives ReCOP's PM write port =====
    U_RECONFIG : ENTITY work.reconfig_node PORT MAP (
        clock      => clock,
        reset      => reset,
        send       => sends(6),
        recv       => recvs(6),
        pm_wr_en   => pm_wr_en,
        pm_wr_addr => pm_wr_addr,
        pm_wr_data => pm_wr_data
    );

    -- ===== Idle ports (1..5, 7) =====
    gen_idle : FOR i IN 0 TO NOC_PORTS - 1 GENERATE
        idle_port : IF i /= 0 AND i /= 6 GENERATE
            sends(i).addr <= (OTHERS => '0');
            sends(i).data <= (OTHERS => '0');
        END GENERATE;
    END GENERATE;

    -- ===== 8-port TdmaMin fabric =====
    U_NOC : ENTITY work.TdmaMin
        GENERIC MAP (ports => NOC_PORTS)
        PORT MAP (
            clock => clock,
            sends => sends,
            recvs => recvs
        );

    -- ===== Capture the first PM write (for T2) =====
    capture : PROCESS (clock)
    BEGIN
        IF rising_edge(clock) THEN
            IF pm_wr_en = '1' AND NOT first_wr_seen THEN
                first_wr_seen <= TRUE;
                first_wr_addr <= pm_wr_addr;
                first_wr_data <= pm_wr_data;
            END IF;
        END IF;
    END PROCESS capture;

    -- ===== Stimulus + checks =====
    stim : PROCESS
        CONSTANT BOOT_TIMEOUT   : NATURAL := 2000;
        CONSTANT RELOAD_TIMEOUT : NATURAL := 6000;
        VARIABLE saw_before : BOOLEAN := FALSE;
        VARIABLE saw_after  : BOOLEAN := FALSE;
        VARIABLE saw_led    : BOOLEAN := FALSE;
    BEGIN
        reset <= '1';
        WAIT UNTIL rising_edge(clock);
        WAIT UNTIL rising_edge(clock);
        reset <= '0';

        -- T1: loader reaches the BEFORE state (HEX = 0x1111)
        FOR i IN 0 TO BOOT_TIMEOUT LOOP
            WAIT UNTIL rising_edge(clock);
            WAIT FOR 1 ns;
            IF io_hex = x"1111" THEN
                saw_before := TRUE;
                EXIT;
            END IF;
        END LOOP;
        ASSERT saw_before
            REPORT "T1 FAIL: loader never reached BEFORE state (io_hex=0x1111); last io_hex=0x"
                 & slv_to_hex(io_hex)
            SEVERITY error;
        IF saw_before THEN
            REPORT "T1 PASS: BEFORE state io_hex=0x1111" SEVERITY note;
        END IF;

        -- Simulate a KEY1 press: set the event flag and hold it.
        -- The loader reads $FF1 bit0, falls through the wait loop, and
        -- never re-reads it, so holding it high is safe.
        io_events(0) <= '1';

        -- T3: wait for the AFTER state -- HEX = the switch value (0x0155)
        -- the loader captured and baked into Program B's LDR immediate.
        FOR i IN 0 TO RELOAD_TIMEOUT LOOP
            WAIT UNTIL rising_edge(clock);
            WAIT FOR 1 ns;
            IF io_hex = x"0155" THEN
                saw_after := TRUE;
                EXIT;
            END IF;
        END LOOP;

        -- T2: the reconfig path wrote Program B's first word at 0x1000.
        ASSERT first_wr_seen
            REPORT "T2 FAIL: reconfig node never asserted a PM write"
            SEVERITY error;
        IF first_wr_seen THEN
            ASSERT first_wr_addr = EXP_FIRST_ADDR AND first_wr_data = EXP_FIRST_DATA
                REPORT "T2 FAIL: first PM write was addr=0x" & slv_to_hex(first_wr_addr)
                     & " data=0x" & slv_to_hex(first_wr_data)
                     & " (expected addr=0x1000 data=0x4010)"
                SEVERITY error;
            IF first_wr_addr = EXP_FIRST_ADDR AND first_wr_data = EXP_FIRST_DATA THEN
                REPORT "T2 PASS: first PM write addr=0x1000 data=0x4010" SEVERITY note;
            END IF;
        END IF;

        ASSERT saw_after
            REPORT "T3 FAIL: AFTER state (io_hex=0x0155 = switch value) not reached within "
                 & integer'image(RELOAD_TIMEOUT) & " cycles; last io_hex=0x"
                 & slv_to_hex(io_hex)
            SEVERITY error;
        IF saw_after THEN
            REPORT "T3 PASS: AFTER state io_hex=0x0155 (ReCOP executed the operator-chosen"
                 & " value loaded into PM)" SEVERITY note;

            -- T4: AFTER LED state. Program B writes the LED two
            -- instructions after HEX, so poll for it rather than checking
            -- the same cycle the HEX state was detected.
            FOR i IN 0 TO 200 LOOP
                IF io_led = x"0002" THEN
                    saw_led := TRUE;
                    EXIT;
                END IF;
                WAIT UNTIL rising_edge(clock);
                WAIT FOR 1 ns;
            END LOOP;
            ASSERT saw_led
                REPORT "T4 FAIL: expected io_led=0x0002, got 0x" & slv_to_hex(io_led)
                SEVERITY error;
            IF saw_led THEN
                REPORT "T4 PASS: AFTER LED state io_led=0x0002" SEVERITY note;
            END IF;

            -- T5: the value is FROZEN into PM code. Move the switches now;
            -- a live read would track them, but Program B never re-reads
            -- $FF0 (it spins after writing), so io_hex must stay 0x0155.
            io_sw <= x"02AA";
            FOR i IN 0 TO 500 LOOP
                WAIT UNTIL rising_edge(clock);
            END LOOP;
            WAIT FOR 1 ns;
            ASSERT io_hex = x"0155"
                REPORT "T5 FAIL: io_hex changed to 0x" & slv_to_hex(io_hex)
                     & " when switches moved -- value was not baked into PM"
                SEVERITY error;
            IF io_hex = x"0155" THEN
                REPORT "T5 PASS: io_hex frozen at 0x0155 after switches moved to 0x02AA"
                     & " (value is compiled into PM, not read live)" SEVERITY note;
            END IF;
        END IF;

        REPORT "==== tb_reconfig_demo complete ====" SEVERITY note;
        WAIT;
    END PROCESS stim;

END ARCHITECTURE sim;
