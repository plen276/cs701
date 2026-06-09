LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- tb_reconfig
--
-- Unit testbench for gp-2/src/recop/reconfig_node.vhd.
-- Tests the reconfig node in isolation (no prog_mem_dp or
-- NoC fabric — just the packet decode and write-port outputs).
--
-- Conf-Prog packet format (type 1111):
--   31:28  type  1111
--   27:24  dest  0110  (port 6)
--   23:20  sub-command
--   19:16  unused
--   15:0   payload
--
-- T1  After reset, pm_wr_en is low and pm_wr_addr/data are zero.
-- T2  Non-Conf-Prog packet (type != 1111) -> pm_wr_en stays low.
-- T3  SET_ADDR (sub 0001) latches the write pointer.
-- T4  WRITE_WORD (sub 0010) asserts pm_wr_en for exactly one cycle
--     with the correct address and data.
-- T5  Auto-increment: a second WRITE_WORD writes to addr+1.
-- T6  A new SET_ADDR repositions the pointer; next WRITE_WORD
--     uses the new base address.
-- ============================================================

ENTITY tb_reconfig IS
END ENTITY tb_reconfig;

ARCHITECTURE sim OF tb_reconfig IS

    CONSTANT CLK_PERIOD : TIME := 40 ns; -- 25 MHz

    SIGNAL clock      : STD_LOGIC := '0';
    SIGNAL reset      : STD_LOGIC := '1';
    SIGNAL send       : tdma_min_port;
    SIGNAL recv       : tdma_min_port := (addr => (OTHERS => '0'),
                                          data => (OTHERS => '0'));
    SIGNAL pm_wr_en   : STD_LOGIC;
    SIGNAL pm_wr_addr : STD_LOGIC_VECTOR(14 DOWNTO 0);
    SIGNAL pm_wr_data : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- Conf-Prog type / sub-command constants
    --   type=1111  dest=0110  sub=0001  unused=0000  payload[14:0]
    --   type=1111  dest=0110  sub=0010  unused=0000  payload[15:0]
    CONSTANT PREF : STD_LOGIC_VECTOR(15 DOWNTO 0) := x"F610"; -- SET_ADDR prefix
    CONSTANT PWRD : STD_LOGIC_VECTOR(15 DOWNTO 0) := x"F620"; -- WRITE_WORD prefix

    -- Build a SET_ADDR packet: sets write pointer to addr
    FUNCTION pkt_set_addr (addr : STD_LOGIC_VECTOR(14 DOWNTO 0))
        RETURN STD_LOGIC_VECTOR IS
    BEGIN
        RETURN PREF & '0' & addr;
    END FUNCTION;

    -- Build a WRITE_WORD packet: writes data to current pointer
    FUNCTION pkt_write_word (data : STD_LOGIC_VECTOR(15 DOWNTO 0))
        RETURN STD_LOGIC_VECTOR IS
    BEGIN
        RETURN PWRD & data;
    END FUNCTION;

    -- Inject one packet for exactly one clock cycle, then go idle.
    PROCEDURE inject (
        SIGNAL recv_s : OUT tdma_min_port;
        CONSTANT pkt  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0)
    ) IS BEGIN
        recv_s <= (addr => (OTHERS => '0'), data => pkt);
        WAIT FOR CLK_PERIOD;
        recv_s <= (addr => (OTHERS => '0'), data => (OTHERS => '0'));
    END PROCEDURE;

    -- Nibble -> hex char helper for assertion messages
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
            WHEN OTHERS => RETURN '?';
        END CASE;
    END FUNCTION;

    FUNCTION to_hex16 (v : STD_LOGIC_VECTOR(15 DOWNTO 0)) RETURN STRING IS
    BEGIN
        RETURN "0x" &
               nibble_to_hex(v(15 DOWNTO 12)) & nibble_to_hex(v(11 DOWNTO 8)) &
               nibble_to_hex(v(7  DOWNTO 4))  & nibble_to_hex(v(3  DOWNTO 0));
    END FUNCTION;

    COMPONENT reconfig_node IS
        PORT
        (
            clock      : IN  STD_LOGIC;
            reset      : IN  STD_LOGIC;
            send       : OUT tdma_min_port;
            recv       : IN  tdma_min_port;
            pm_wr_en   : OUT STD_LOGIC;
            pm_wr_addr : OUT STD_LOGIC_VECTOR(14 DOWNTO 0);
            pm_wr_data : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    clock <= NOT clock AFTER CLK_PERIOD / 2;

    UUT : reconfig_node PORT MAP
    (
        clock      => clock,
        reset      => reset,
        send       => send,
        recv       => recv,
        pm_wr_en   => pm_wr_en,
        pm_wr_addr => pm_wr_addr,
        pm_wr_data => pm_wr_data
    );

    stimulus : PROCESS
    BEGIN

        -- ===== Reset =====
        reset <= '1';
        WAIT FOR 3 * CLK_PERIOD;
        reset <= '0';
        WAIT FOR CLK_PERIOD;

        -- ---------------------------------------------------------
        -- T1  After reset, write enable is low.
        -- ---------------------------------------------------------
        ASSERT pm_wr_en = '0'
            REPORT "T1 FAIL: pm_wr_en not low after reset"
            SEVERITY FAILURE;
        ASSERT pm_wr_addr = (14 DOWNTO 0 => '0')
            REPORT "T1 FAIL: pm_wr_addr not zero after reset"
            SEVERITY FAILURE;
        REPORT "T1 PASS: idle after reset";

        -- ---------------------------------------------------------
        -- T2  Non-Conf-Prog packet (type 1000, Data-Audio) is ignored.
        -- ---------------------------------------------------------
        inject(recv, x"81000000");
        WAIT FOR CLK_PERIOD;
        ASSERT pm_wr_en = '0'
            REPORT "T2 FAIL: pm_wr_en raised on non-Conf-Prog packet"
            SEVERITY FAILURE;
        REPORT "T2 PASS: non-Conf-Prog packet ignored";

        -- ---------------------------------------------------------
        -- T3  SET_ADDR to address 0x0010 latches the pointer.
        --     (Verified implicitly by T4 which checks the write addr.)
        -- ---------------------------------------------------------
        inject(recv, pkt_set_addr("0000000" & x"10")); -- addr = 0x0010
        WAIT FOR CLK_PERIOD;
        ASSERT pm_wr_en = '0'
            REPORT "T3 FAIL: pm_wr_en raised on SET_ADDR"
            SEVERITY FAILURE;
        REPORT "T3 PASS: SET_ADDR does not assert write enable";

        -- ---------------------------------------------------------
        -- T4  WRITE_WORD 0xABCD -> pm_wr_en='1', addr=0x0010,
        --     data=0xABCD for exactly one cycle.
        --
        -- Timing: inject() returns right after the clock edge that
        -- sampled the WRITE_WORD packet.  At that point wr_en_reg
        -- has already been set to '1' (registered output from that
        -- same edge), so pm_wr_en is '1' immediately.  The NEXT
        -- rising edge (one CLK_PERIOD later) resets wr_en_reg to '0'
        -- via the default assignment — that's the one-shot check.
        -- ---------------------------------------------------------
        inject(recv, pkt_write_word(x"ABCD"));
        -- Check immediately: pm_wr_en was set on the rising edge
        -- inside inject and is '1' until the next rising edge.
        ASSERT pm_wr_en = '1'
            REPORT "T4 FAIL: pm_wr_en not asserted after WRITE_WORD"
            SEVERITY FAILURE;
        ASSERT pm_wr_addr = "0000000" & x"10"
            REPORT "T4 FAIL: pm_wr_addr wrong, got " & to_hex16('0' & pm_wr_addr)
            SEVERITY FAILURE;
        ASSERT pm_wr_data = x"ABCD"
            REPORT "T4 FAIL: pm_wr_data wrong, got " & to_hex16(pm_wr_data)
            SEVERITY FAILURE;
        REPORT "T4 PASS: WRITE_WORD fires with correct addr and data";

        -- One-shot: wait past the next rising edge; wr_en_reg resets to '0'.
        WAIT FOR CLK_PERIOD;
        ASSERT pm_wr_en = '0'
            REPORT "T4 FAIL: pm_wr_en not cleared after one cycle"
            SEVERITY FAILURE;
        REPORT "T4 PASS: pm_wr_en is one-shot";

        -- ---------------------------------------------------------
        -- T5  Auto-increment: second WRITE_WORD writes to 0x0011.
        -- ---------------------------------------------------------
        inject(recv, pkt_write_word(x"1234"));
        ASSERT pm_wr_en = '1'
            REPORT "T5 FAIL: pm_wr_en not asserted on second WRITE_WORD"
            SEVERITY FAILURE;
        ASSERT pm_wr_addr = "0000000" & x"11"
            REPORT "T5 FAIL: pm_wr_addr not auto-incremented, got " & to_hex16('0' & pm_wr_addr)
            SEVERITY FAILURE;
        ASSERT pm_wr_data = x"1234"
            REPORT "T5 FAIL: pm_wr_data wrong on second write"
            SEVERITY FAILURE;
        REPORT "T5 PASS: address auto-incremented to 0x0011";

        WAIT FOR CLK_PERIOD;

        -- ---------------------------------------------------------
        -- T6  SET_ADDR repositions the pointer; next write uses it.
        -- ---------------------------------------------------------
        inject(recv, pkt_set_addr("0000000" & x"02")); -- addr = 0x0002
        WAIT FOR CLK_PERIOD;
        inject(recv, pkt_write_word(x"5678"));
        ASSERT pm_wr_en = '1'
            REPORT "T6 FAIL: pm_wr_en not asserted after repositioned SET_ADDR"
            SEVERITY FAILURE;
        ASSERT pm_wr_addr = "0000000" & x"02"
            REPORT "T6 FAIL: pm_wr_addr not repositioned, got " & to_hex16('0' & pm_wr_addr)
            SEVERITY FAILURE;
        ASSERT pm_wr_data = x"5678"
            REPORT "T6 FAIL: pm_wr_data wrong after reposition"
            SEVERITY FAILURE;
        REPORT "T6 PASS: SET_ADDR repositioned write pointer correctly";

        WAIT FOR CLK_PERIOD;

        -- ---------------------------------------------------------
        -- T7  send port is always idle (bit 31 never set).
        -- ---------------------------------------------------------
        ASSERT send.data(31) = '0'
            REPORT "T7 FAIL: send.data(31) was set (would enqueue spurious NoC packet)"
            SEVERITY FAILURE;
        REPORT "T7 PASS: send port permanently idle";

        REPORT "All reconfig_node tests PASSED";
        WAIT;
    END PROCESS stimulus;

END ARCHITECTURE sim;
