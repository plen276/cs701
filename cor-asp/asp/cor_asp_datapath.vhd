-- ============================================================
-- cor_asp_datapath.vhd
--
-- Datapath for the autocorrelation (reference-point detector)
-- ASP. Implements the kernel:
--
--   corr = f(k)*f(k-1) + f(k+1)*f(k-2) + ... + f(k+n-1)*f(k-n)
--
-- The 2n-sample window is centred around index k. The control
-- unit asserts ``start`` after a new averaged sample has been
-- written to ``sample_mem``; ``newest_addr`` points to the
-- location of that newest sample.  The datapath then schedules
-- n=window/2 multiply-accumulate iterations.
--
-- Stages (pipelined per iteration i = 0 .. n-1):
--
--   AG  (cycle t   ) : drive rd_addr_a(i), rd_addr_b(i) to RAM
--   MR  (cycle t+1 ) : RAM presents data_a(i), data_b(i)
--   MUL (cycle t+2 ) : prod_reg <= data_a(i) * data_b(i)
--   ACC (cycle t+3 ) : acc_reg  <= acc_reg + prod_reg
--
-- Throughput is therefore 1 pair / cycle once the pipeline is
-- primed; a window of 2n=64 finishes in n+3 = 35 cycles
-- (~ 0.7 us at 50 MHz, well under the 62.5 us between consecutive
-- 16 kHz samples).
--
-- Output is right-shifted by a programmable amount so the 32-bit
-- accumulator can be packed into the 16-bit NoC payload while
-- preserving the monotonic ordering needed by the downstream
-- peak detector.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY cor_asp_datapath IS
    GENERIC
    (
        DATA_WIDTH : INTEGER := 16;
        ADDR_WIDTH : INTEGER := 8;
        ACC_WIDTH  : INTEGER := 32;
        N_WIDTH    : INTEGER := 8   -- n = window/2, up to 2^N_WIDTH
    );
    PORT
    (
        clk            : IN STD_LOGIC;
        reset          : IN STD_LOGIC;

        -- Configuration
        half_window    : IN UNSIGNED(N_WIDTH - 1 DOWNTO 0); -- n = window/2
        shift_amt      : IN UNSIGNED(4 DOWNTO 0);           -- 0..31

        -- From NI: address of the newest sample written
        newest_addr    : IN STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);

        -- Control hand-shake
        start          : IN  STD_LOGIC;  -- 1-cycle pulse from FSM
        busy           : OUT STD_LOGIC;
        result_valid   : OUT STD_LOGIC;  -- 1-cycle pulse
        result         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        result_full    : OUT STD_LOGIC_VECTOR(ACC_WIDTH - 1 DOWNTO 0);

        -- Sample memory read interface
        rd_addr_a      : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        rd_addr_b      : OUT STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        rd_data_a      : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        rd_data_b      : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0)
    );
END ENTITY cor_asp_datapath;

ARCHITECTURE rtl OF cor_asp_datapath IS

    -- Internal "phase" counter sweeps from 0 to n+2, where
    --   phase  in [0  .. n-1] : drive addresses for iteration phase
    --   phase  in [1  .. n  ] : RAM is reading iteration phase-1
    --   phase  in [2  .. n+1] : multiply iteration phase-2  (latch prod)
    --   phase  in [3  .. n+2] : accumulate iteration phase-3
    -- A `running` flag tells the rest of the world that a calc is in
    -- progress.  Once phase reaches n+3 (= n + pipeline_depth) we
    -- emit result_valid and go back to idle.
    SIGNAL phase           : UNSIGNED(N_WIDTH + 1 DOWNTO 0);
    SIGNAL running         : STD_LOGIC := '0';

    -- Captured at the start of a calculation: the address of the
    -- sample at the "centre" of the window, k = newest - n + 1.
    SIGNAL corr_origin     : UNSIGNED(ADDR_WIDTH - 1 DOWNTO 0);

    -- Latched window and shift so mid-run config changes do not
    -- corrupt an in-flight correlation.
    SIGNAL half_window_r   : UNSIGNED(N_WIDTH - 1 DOWNTO 0);
    SIGNAL shift_amt_r     : UNSIGNED(4 DOWNTO 0);

    -- Pipeline-valid bits track which stages currently hold a
    -- valid item.
    SIGNAL ag_valid        : STD_LOGIC;
    SIGNAL ag_valid_r      : STD_LOGIC; -- aligned with mem read output
    SIGNAL mul_valid_r     : STD_LOGIC; -- aligned with prod_reg
    SIGNAL acc_valid_r     : STD_LOGIC; -- last accumulate happened

    SIGNAL prod_reg        : UNSIGNED(2*DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL acc_reg         : UNSIGNED(ACC_WIDTH - 1 DOWNTO 0);
    SIGNAL result_reg      : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL result_full_reg : STD_LOGIC_VECTOR(ACC_WIDTH - 1 DOWNTO 0);
    SIGNAL result_valid_r  : STD_LOGIC;

    SIGNAL i_idx           : UNSIGNED(N_WIDTH - 1 DOWNTO 0);
    SIGNAL addr_a_int      : UNSIGNED(ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL addr_b_int      : UNSIGNED(ADDR_WIDTH - 1 DOWNTO 0);

BEGIN

    -- ============================================================
    -- Output drivers
    -- ============================================================
    busy         <= running;
    result       <= result_reg;
    result_full  <= result_full_reg;
    result_valid <= result_valid_r;

    -- ============================================================
    -- Address generation (AG)
    -- ag_valid is '1' on cycles that issue a valid pair.
    -- ============================================================
    ag_valid   <= '1' WHEN running = '1' AND phase < ('0' & half_window_r) ELSE '0';
    i_idx      <= phase(N_WIDTH - 1 DOWNTO 0);
    addr_a_int <= corr_origin + i_idx;
    addr_b_int <= corr_origin - 1 - i_idx;
    rd_addr_a  <= STD_LOGIC_VECTOR(addr_a_int);
    rd_addr_b  <= STD_LOGIC_VECTOR(addr_b_int);

    -- ============================================================
    -- Sequencer + pipeline
    -- ============================================================
    PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                running        <= '0';
                phase          <= (OTHERS => '0');
                corr_origin    <= (OTHERS => '0');
                half_window_r  <= (OTHERS => '0');
                shift_amt_r    <= (OTHERS => '0');
                ag_valid_r     <= '0';
                mul_valid_r    <= '0';
                acc_valid_r    <= '0';
                prod_reg       <= (OTHERS => '0');
                acc_reg        <= (OTHERS => '0');
                result_reg     <= (OTHERS => '0');
                result_full_reg<= (OTHERS => '0');
                result_valid_r <= '0';
            ELSE
                -- default: result_valid only pulses for one cycle
                result_valid_r <= '0';

                -- start a new computation
                IF start = '1' AND running = '0' THEN
                    -- k = newest - n + 1  (in mod 2^ADDR_WIDTH arithmetic)
                    corr_origin   <= unsigned(newest_addr) - resize(half_window, ADDR_WIDTH) + 1;
                    half_window_r <= half_window;
                    shift_amt_r   <= shift_amt;
                    phase         <= (OTHERS => '0');
                    acc_reg       <= (OTHERS => '0');
                    running       <= '1';
                ELSIF running = '1' THEN
                    -- advance the phase counter
                    phase <= phase + 1;
                END IF;

                -- Pipeline valid propagation (only meaningful while running)
                ag_valid_r  <= ag_valid AND running;
                mul_valid_r <= ag_valid_r;

                -- Stage MUL : product of the RAM outputs
                IF ag_valid_r = '1' THEN
                    prod_reg <= unsigned(rd_data_a) * unsigned(rd_data_b);
                END IF;

                -- Stage ACC : accumulate
                IF mul_valid_r = '1' THEN
                    acc_reg <= acc_reg
                             + resize(prod_reg, ACC_WIDTH);
                    acc_valid_r <= '1';
                END IF;

                -- Termination
                --
                -- For n=half_window the timeline (n=4 example) is:
                --   start at C0 -> running=1, phase=0
                --   addresses issued at C1..C4 (phase 0..3 entering cycle)
                --   prod_reg captures pair i at C(2+i) rising edge
                --   acc accumulates  pair i at C(3+i) rising edge
                --   last acc finishes at C(n+2) rising edge, so acc
                --   first holds the full sum entering C(n+3).
                --
                -- Therefore we latch the result at phase = n+2
                -- (i.e. entering C(n+3)) giving total latency n+3.
                IF running = '1' AND phase = ('0' & half_window_r) + 2 THEN
                    result_full_reg <= STD_LOGIC_VECTOR(acc_reg);
                    result_reg <= STD_LOGIC_VECTOR(
                        resize(shift_right(acc_reg,
                                           TO_INTEGER(shift_amt_r)), 16));
                    result_valid_r <= '1';
                    running        <= '0';
                    acc_valid_r    <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;
