-- ============================================================
-- cor_asp_control.vhd
--
-- Control unit + Network Interface (NI) of the autocorrelation
-- ASP.  Holds all configuration registers, parses 32-bit NoC
-- packets, manages the circular sample buffer, schedules
-- correlation computations and forms outgoing DATA packets.
--
-- Top-level FSM (one state per cycle, Moore):
--
--    IDLE -+-> on incoming CMD : update config register; back to IDLE
--          |
--          +-> on incoming DATA: write sample, advance wr_ptr,
--          |                    increment interval counter; if
--          |                    counter >= interval and ENABLE='1'
--          |                    set trig pulse so datapath starts
--          |
--          +-> on result_valid : latch correlation into the
--                                outgoing packet register and
--                                assert pkt_out_valid for 1 cycle
--
-- The datapath runs independently of this FSM after `trig` is
-- pulsed: it returns `cor_busy` while computing and pulses
-- `result_valid` when done.  If a new sample arrives while the
-- datapath is still busy, the new sample is still written to
-- the buffer, but no fresh start is issued (we wait for the
-- current correlation to finish).
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cor_asp_pkg.ALL;

ENTITY cor_asp_control IS
    GENERIC
    (
        DATA_WIDTH      : INTEGER := 16;
        ADDR_WIDTH      : INTEGER := 8;
        N_WIDTH         : INTEGER := 8;
        MY_NODE_ID      : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_COR;
        DEFAULT_DEST    : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_PD;
        DEFAULT_WINDOW  : INTEGER := 64;   -- 2n
        DEFAULT_INTERVAL: INTEGER := 1;    -- new correlation every input
        DEFAULT_SHIFT   : INTEGER := 6
    );
    PORT
    (
        clk           : IN  STD_LOGIC;
        reset         : IN  STD_LOGIC;

        -- ==================== Incoming NoC port ====================
        pkt_in        : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        pkt_in_valid  : IN  STD_LOGIC;

        -- ==================== Outgoing NoC port ====================
        pkt_out       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        pkt_out_valid : OUT STD_LOGIC;

        -- ==================== Sample memory write =================
        sm_wr_en      : OUT STD_LOGIC;
        sm_wr_addr    : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        sm_wr_data    : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

        -- ==================== Datapath hand-shake ==================
        cor_start     : OUT STD_LOGIC;
        cor_busy      : IN  STD_LOGIC;
        cor_result_v  : IN  STD_LOGIC;
        cor_result    : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
        newest_addr   : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        half_window   : OUT UNSIGNED(N_WIDTH - 1 DOWNTO 0);
        shift_amt     : OUT UNSIGNED(4 DOWNTO 0);

        -- ==================== Debug / status ========================
        st_enable     : OUT STD_LOGIC;
        st_window     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        st_dest       : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        st_samples    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        st_corrs      : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END ENTITY cor_asp_control;

ARCHITECTURE rtl OF cor_asp_control IS

    -- ============================================================
    -- Configuration registers (set by CMD packets, used internally)
    -- ============================================================
    SIGNAL cfg_window      : UNSIGNED(15 DOWNTO 0)
        := TO_UNSIGNED(DEFAULT_WINDOW, 16);
    SIGNAL cfg_dest        : STD_LOGIC_VECTOR(3 DOWNTO 0) := DEFAULT_DEST;
    SIGNAL cfg_src_filter  : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_ANY;
    SIGNAL cfg_interval    : UNSIGNED(15 DOWNTO 0)
        := TO_UNSIGNED(DEFAULT_INTERVAL, 16);
    SIGNAL cfg_shift       : UNSIGNED(4 DOWNTO 0)
        := TO_UNSIGNED(DEFAULT_SHIFT, 5);
    SIGNAL cfg_enable      : STD_LOGIC := '0';

    -- ============================================================
    -- Sample buffer pointer and counters
    -- ============================================================
    SIGNAL wr_ptr          : UNSIGNED(ADDR_WIDTH - 1 DOWNTO 0)
        := (OTHERS => '0');
    SIGNAL newest_addr_r   : UNSIGNED(ADDR_WIDTH - 1 DOWNTO 0)
        := (OTHERS => '0');
    SIGNAL interval_cnt    : UNSIGNED(15 DOWNTO 0) := (OTHERS => '0');

    -- ============================================================
    -- Status counters (visible via STATUS packets / debug bus)
    -- ============================================================
    SIGNAL sample_cnt      : UNSIGNED(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL corr_cnt        : UNSIGNED(15 DOWNTO 0) := (OTHERS => '0');

    -- ============================================================
    -- Decoded packet fields (combinational)
    -- ============================================================
    SIGNAL pkt_dest        : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL pkt_src         : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL pkt_type        : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL pkt_cmd         : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL pkt_payload     : STD_LOGIC_VECTOR(15 DOWNTO 0);

    SIGNAL pkt_for_us      : STD_LOGIC;
    SIGNAL pkt_from_ok     : STD_LOGIC;
    SIGNAL is_cmd          : STD_LOGIC;
    SIGNAL is_data         : STD_LOGIC;
    SIGNAL is_ctrl         : STD_LOGIC;

    -- ============================================================
    -- Output packet register (1-deep)
    -- ============================================================
    SIGNAL out_pkt_r       : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL out_valid_r     : STD_LOGIC := '0';

    -- ============================================================
    -- Internal start pulse
    -- ============================================================
    SIGNAL trig            : STD_LOGIC;

BEGIN

    -- ============================================================
    -- Packet decode (combinational)
    -- ============================================================
    pkt_dest    <= pkt_in(PKT_DEST_HI DOWNTO PKT_DEST_LO);
    pkt_src     <= pkt_in(PKT_SRC_HI  DOWNTO PKT_SRC_LO);
    pkt_type    <= pkt_in(PKT_TYPE_HI DOWNTO PKT_TYPE_LO);
    pkt_cmd     <= pkt_in(PKT_CMD_HI  DOWNTO PKT_CMD_LO);
    pkt_payload <= pkt_in(PKT_PAY_HI  DOWNTO PKT_PAY_LO);

    pkt_for_us  <= '1' WHEN pkt_dest = MY_NODE_ID ELSE '0';
    pkt_from_ok <= '1' WHEN (cfg_src_filter = NODE_ID_ANY)
                          OR (pkt_src = cfg_src_filter) ELSE '0';
    is_cmd      <= '1' WHEN pkt_in_valid = '1' AND pkt_for_us = '1'
                          AND pkt_type = PKT_TYPE_CMD  ELSE '0';
    is_data     <= '1' WHEN pkt_in_valid = '1' AND pkt_for_us = '1'
                          AND pkt_from_ok = '1'
                          AND pkt_type = PKT_TYPE_DATA ELSE '0';
    is_ctrl     <= '1' WHEN pkt_in_valid = '1' AND pkt_for_us = '1'
                          AND pkt_type = PKT_TYPE_CTRL ELSE '0';

    -- ============================================================
    -- Output ports
    -- ============================================================
    sm_wr_en    <= is_data;
    sm_wr_addr  <= STD_LOGIC_VECTOR(wr_ptr);
    sm_wr_data  <= pkt_payload;

    newest_addr <= STD_LOGIC_VECTOR(newest_addr_r);
    half_window <= resize(shift_right(cfg_window, 1), N_WIDTH);
    shift_amt   <= cfg_shift;

    cor_start   <= trig;
    pkt_out     <= out_pkt_r;
    pkt_out_valid <= out_valid_r;

    st_enable   <= cfg_enable;
    st_window   <= STD_LOGIC_VECTOR(cfg_window);
    st_dest     <= cfg_dest;
    st_samples  <= STD_LOGIC_VECTOR(sample_cnt);
    st_corrs    <= STD_LOGIC_VECTOR(corr_cnt);

    -- ============================================================
    -- Sequential logic
    -- ============================================================
    PROCESS (clk)
        VARIABLE want_trig : STD_LOGIC;
    BEGIN
        IF rising_edge(clk) THEN
            -- defaults
            trig        <= '0';
            out_valid_r <= '0';
            want_trig   := '0';

            IF reset = '1' THEN
                cfg_window     <= TO_UNSIGNED(DEFAULT_WINDOW,   16);
                cfg_dest       <= DEFAULT_DEST;
                cfg_src_filter <= NODE_ID_ANY;
                cfg_interval   <= TO_UNSIGNED(DEFAULT_INTERVAL, 16);
                cfg_shift      <= TO_UNSIGNED(DEFAULT_SHIFT,    5);
                cfg_enable     <= '0';
                wr_ptr         <= (OTHERS => '0');
                newest_addr_r  <= (OTHERS => '0');
                interval_cnt   <= (OTHERS => '0');
                sample_cnt     <= (OTHERS => '0');
                corr_cnt       <= (OTHERS => '0');
                out_pkt_r      <= (OTHERS => '0');
            ELSE
                -- ============== Handle CMD packets ==============
                IF is_cmd = '1' THEN
                    CASE pkt_cmd IS
                        WHEN CMD_SET_WINDOW =>
                            -- accept only even windows in [4, 256]
                            IF unsigned(pkt_payload) >= 4
                               AND unsigned(pkt_payload) <= 256
                               AND pkt_payload(0) = '0' THEN
                                cfg_window <= unsigned(pkt_payload);
                            END IF;
                        WHEN CMD_SET_DEST =>
                            cfg_dest <= pkt_payload(3 DOWNTO 0);
                        WHEN CMD_SET_INTERVAL =>
                            IF unsigned(pkt_payload) /= 0 THEN
                                cfg_interval <= unsigned(pkt_payload);
                            END IF;
                        WHEN CMD_SET_SHIFT =>
                            cfg_shift <= unsigned(pkt_payload(4 DOWNTO 0));
                        WHEN CMD_SET_ENABLE =>
                            cfg_enable <= pkt_payload(0);
                            interval_cnt <= (OTHERS => '0');
                        WHEN CMD_RESET_BUF =>
                            wr_ptr        <= (OTHERS => '0');
                            newest_addr_r <= (OTHERS => '0');
                            interval_cnt  <= (OTHERS => '0');
                            sample_cnt    <= (OTHERS => '0');
                            corr_cnt      <= (OTHERS => '0');
                        WHEN CMD_SET_SRC =>
                            cfg_src_filter <= pkt_payload(3 DOWNTO 0);
                        WHEN OTHERS =>
                            NULL;
                    END CASE;
                END IF;

                -- ============== Handle DATA packets =============
                IF is_data = '1' THEN
                    -- Write into circular buffer
                    newest_addr_r <= wr_ptr;
                    wr_ptr        <= wr_ptr + 1;
                    sample_cnt    <= sample_cnt + 1;
                    interval_cnt  <= interval_cnt + 1;

                    -- If enabled and we have collected enough new samples
                    -- since the last correlation, trigger the datapath
                    -- (only if it is currently idle).
                    IF cfg_enable = '1'
                       AND cor_busy = '0'
                       AND (interval_cnt + 1) >= cfg_interval THEN
                        want_trig := '1';
                    END IF;
                END IF;

                -- ============== Handle CTRL packets =============
                -- (currently only CMD_RESET_BUF is supported via CMD;
                --  CTRL packets are reserved for system-wide use)
                IF is_ctrl = '1' THEN
                    -- Reserved: in future, broadcast reset / enable
                    NULL;
                END IF;

                -- ============== Issue trig (1-cycle pulse) ======
                IF want_trig = '1' THEN
                    trig         <= '1';
                    interval_cnt <= (OTHERS => '0');
                END IF;

                -- ============== Handle correlation result =======
                IF cor_result_v = '1' THEN
                    out_pkt_r <= pkt_pack(
                        cfg_dest,
                        MY_NODE_ID,
                        PKT_TYPE_DATA,
                        x"0",
                        cor_result);
                    out_valid_r <= '1';
                    corr_cnt    <= corr_cnt + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;
