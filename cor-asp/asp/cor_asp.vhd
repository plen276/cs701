-- ============================================================
-- cor_asp.vhd
--
-- Top-level entity for the Autocorrelation Application-Specific
-- Processor (COR-ASP), part of the COMPSYS 701 power-frequency
-- relay HMPSoC.
--
-- Black-box interface (compatible with any 32-bit / single-cycle
-- TDMA-MIN NoC node):
--
--   clk, reset
--   pkt_in       (32-bit)   - packet arriving from NoC
--   pkt_in_valid (1)        - one-cycle valid pulse
--   pkt_out      (32-bit)   - packet to inject into NoC
--   pkt_out_valid(1)        - one-cycle valid pulse
--
-- The ASP autonomously:
--   * absorbs configuration CMD packets sent by ReCOP / Nios II
--   * absorbs streaming DATA packets sent by the AVG-ASP
--   * runs the reference-point correlation kernel
--   * forwards each result as a DATA packet to the configured
--     destination (the PD-ASP by default)
--
-- See cor_asp_pkg.vhd for the packet format and command catalogue.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cor_asp_pkg.ALL;

ENTITY cor_asp IS
    GENERIC
    (
        DATA_WIDTH       : INTEGER := 16;
        ADDR_WIDTH       : INTEGER := 8;
        ACC_WIDTH        : INTEGER := 32;
        N_WIDTH          : INTEGER := 8;
        MY_NODE_ID       : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_COR;
        DEFAULT_DEST     : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_PD;
        DEFAULT_WINDOW   : INTEGER := 64;
        DEFAULT_INTERVAL : INTEGER := 1;
        DEFAULT_SHIFT    : INTEGER := 6
    );
    PORT
    (
        clk            : IN  STD_LOGIC;
        reset          : IN  STD_LOGIC;

        -- ====== NoC interface ======
        pkt_in         : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        pkt_in_valid   : IN  STD_LOGIC;
        pkt_out        : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        pkt_out_valid  : OUT STD_LOGIC;

        -- ====== Optional status (for board debug LEDs / HEX) ======
        dbg_enable     : OUT STD_LOGIC;
        dbg_busy       : OUT STD_LOGIC;
        dbg_window     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dbg_samples    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dbg_corrs      : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dbg_last_corr  : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END ENTITY cor_asp;

ARCHITECTURE structural OF cor_asp IS

    -- Memory <-> datapath signals
    SIGNAL sm_wr_en       : STD_LOGIC;
    SIGNAL sm_wr_addr     : STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL sm_wr_data     : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL sm_rd_addr_a   : STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL sm_rd_addr_b   : STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL sm_rd_data_a   : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL sm_rd_data_b   : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

    -- Control <-> datapath signals
    SIGNAL c_newest_addr  : STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL c_start        : STD_LOGIC;
    SIGNAL c_busy         : STD_LOGIC;
    SIGNAL c_result_v     : STD_LOGIC;
    SIGNAL c_result       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL c_result_full  : STD_LOGIC_VECTOR(ACC_WIDTH - 1 DOWNTO 0);
    SIGNAL c_half_window  : UNSIGNED(N_WIDTH - 1 DOWNTO 0);
    SIGNAL c_shift_amt    : UNSIGNED(4 DOWNTO 0);

    -- Latched last correlation (for debug)
    SIGNAL last_corr_r    : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- ============================================================
    -- Component declarations
    -- ============================================================
    COMPONENT sample_mem IS
        GENERIC (
            DATA_WIDTH : INTEGER := 16;
            ADDR_WIDTH : INTEGER := 8
        );
        PORT (
            clk       : IN  STD_LOGIC;
            wr_en     : IN  STD_LOGIC;
            wr_addr   : IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            wr_data   : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            rd_addr_a : IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            rd_data_a : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            rd_addr_b : IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            rd_data_b : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT cor_asp_datapath IS
        GENERIC (
            DATA_WIDTH : INTEGER := 16;
            ADDR_WIDTH : INTEGER := 8;
            ACC_WIDTH  : INTEGER := 32;
            N_WIDTH    : INTEGER := 8
        );
        PORT (
            clk            : IN  STD_LOGIC;
            reset          : IN  STD_LOGIC;
            half_window    : IN  UNSIGNED(N_WIDTH - 1 DOWNTO 0);
            shift_amt      : IN  UNSIGNED(4 DOWNTO 0);
            newest_addr    : IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            start          : IN  STD_LOGIC;
            busy           : OUT STD_LOGIC;
            result_valid   : OUT STD_LOGIC;
            result         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            result_full    : OUT STD_LOGIC_VECTOR(ACC_WIDTH - 1 DOWNTO 0);
            rd_addr_a      : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            rd_addr_b      : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            rd_data_a      : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            rd_data_b      : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT cor_asp_control IS
        GENERIC (
            DATA_WIDTH       : INTEGER := 16;
            ADDR_WIDTH       : INTEGER := 8;
            N_WIDTH          : INTEGER := 8;
            MY_NODE_ID       : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_COR;
            DEFAULT_DEST     : STD_LOGIC_VECTOR(3 DOWNTO 0) := NODE_ID_PD;
            DEFAULT_WINDOW   : INTEGER := 64;
            DEFAULT_INTERVAL : INTEGER := 1;
            DEFAULT_SHIFT    : INTEGER := 6
        );
        PORT (
            clk           : IN  STD_LOGIC;
            reset         : IN  STD_LOGIC;
            pkt_in        : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            pkt_in_valid  : IN  STD_LOGIC;
            pkt_out       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            pkt_out_valid : OUT STD_LOGIC;
            sm_wr_en      : OUT STD_LOGIC;
            sm_wr_addr    : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            sm_wr_data    : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            cor_start     : OUT STD_LOGIC;
            cor_busy      : IN  STD_LOGIC;
            cor_result_v  : IN  STD_LOGIC;
            cor_result    : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
            newest_addr   : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
            half_window   : OUT UNSIGNED(N_WIDTH - 1 DOWNTO 0);
            shift_amt     : OUT UNSIGNED(4 DOWNTO 0);
            st_enable     : OUT STD_LOGIC;
            st_window     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            st_dest       : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            st_samples    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            st_corrs      : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    -- ============================================================
    -- Sample memory (256 x 16 by default, true 2-read 1-write)
    -- ============================================================
    SMEM : sample_mem
        GENERIC MAP (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH
        )
        PORT MAP (
            clk       => clk,
            wr_en     => sm_wr_en,
            wr_addr   => sm_wr_addr,
            wr_data   => sm_wr_data,
            rd_addr_a => sm_rd_addr_a,
            rd_data_a => sm_rd_data_a,
            rd_addr_b => sm_rd_addr_b,
            rd_data_b => sm_rd_data_b
        );

    -- ============================================================
    -- Correlation datapath (pipelined MAC)
    -- ============================================================
    DP : cor_asp_datapath
        GENERIC MAP (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            ACC_WIDTH  => ACC_WIDTH,
            N_WIDTH    => N_WIDTH
        )
        PORT MAP (
            clk          => clk,
            reset        => reset,
            half_window  => c_half_window,
            shift_amt    => c_shift_amt,
            newest_addr  => c_newest_addr,
            start        => c_start,
            busy         => c_busy,
            result_valid => c_result_v,
            result       => c_result,
            result_full  => c_result_full,
            rd_addr_a    => sm_rd_addr_a,
            rd_addr_b    => sm_rd_addr_b,
            rd_data_a    => sm_rd_data_a,
            rd_data_b    => sm_rd_data_b
        );

    -- ============================================================
    -- Control unit + NoC interface (NI)
    -- ============================================================
    CU : cor_asp_control
        GENERIC MAP (
            DATA_WIDTH       => DATA_WIDTH,
            ADDR_WIDTH       => ADDR_WIDTH,
            N_WIDTH          => N_WIDTH,
            MY_NODE_ID       => MY_NODE_ID,
            DEFAULT_DEST     => DEFAULT_DEST,
            DEFAULT_WINDOW   => DEFAULT_WINDOW,
            DEFAULT_INTERVAL => DEFAULT_INTERVAL,
            DEFAULT_SHIFT    => DEFAULT_SHIFT
        )
        PORT MAP (
            clk           => clk,
            reset         => reset,
            pkt_in        => pkt_in,
            pkt_in_valid  => pkt_in_valid,
            pkt_out       => pkt_out,
            pkt_out_valid => pkt_out_valid,
            sm_wr_en      => sm_wr_en,
            sm_wr_addr    => sm_wr_addr,
            sm_wr_data    => sm_wr_data,
            cor_start     => c_start,
            cor_busy      => c_busy,
            cor_result_v  => c_result_v,
            cor_result    => c_result,
            newest_addr   => c_newest_addr,
            half_window   => c_half_window,
            shift_amt     => c_shift_amt,
            st_enable     => dbg_enable,
            st_window     => dbg_window,
            st_dest       => OPEN,
            st_samples    => dbg_samples,
            st_corrs      => dbg_corrs
        );

    -- ============================================================
    -- Latch last correlation for debug
    -- ============================================================
    PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                last_corr_r <= (OTHERS => '0');
            ELSIF c_result_v = '1' THEN
                last_corr_r <= c_result;
            END IF;
        END IF;
    END PROCESS;

    dbg_busy      <= c_busy;
    dbg_last_corr <= last_corr_r;

END ARCHITECTURE structural;
