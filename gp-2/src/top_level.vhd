LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- top_level
--
-- DE1-SoC board top for GP-2.
--
-- Clock: CLOCK_50 (50 MHz) feeds system_pll_10, which outputs 10 MHz on
-- outclk_0 -> sys_clk. Everything downstream runs on 10 MHz.
-- The 50 MHz target failed setup timing (-7 ns slack, IR->regfile-write path);
-- 25 MHz gives ~13 ns margin without touching the ReCOP architecture.
-- ADC sample-rate divisors are computed against 10 MHz via the clock_hz
-- generic override on the adc_asp instantiation below.
--
-- Node identity / addressing:
--   A node's NoC identity IS its port index. TdmaMin assigns each
--   TdmaMinInterface a hardwired `identity` = port number via its
--   generate loop, and that interface answers to address = identity.
--   Therefore ReCOP needs NO explicit ID generic: its identity is
--   structurally fixed to port 0 by the wiring below. A node only
--   needs to know OTHER nodes' ids (to address them), which is carried
--   at run time in each packet's DEST/NEXT nibble set by the ReCOP
--   configuration program. The canonical id<->port map is:
--
--   NoC port 0  ReCOP + recop_ni            (id 0)
--   NoC port 1  adc_asp  (DDS sine source)  (id 1)
--   NoC port 2  avg_asp  (moving-average)   (id 2)
--   NoC port 3  cor_asp via cor_asp_noc     (id 3)
--   NoC port 4  PeakDetector (pd_asp)       (id 4)
--   NoC port 5  RESERVED for Nios II bridge (W7, deferred)
--   NoC port 6  RESERVED for reconfig node  (W6)
--   NoC port 7  spare
--
--   Reference data pipeline (configured by the ReCOP boot program):
--     ADC(1) -> AVG(2) -> COR(3) -> PD(4)   [results -> ReCOP(0)]
--
-- Board controls:
--   CLOCK_50    50 MHz board clock (input to PLL)
--   KEY(0)      reset (active-low button -> active-high internal reset)
--   KEY(3)      debug step (rising edge advances FSM in debug mode)
--   SW(0)       debug_mode (1 = freeze FSM)
--   SW(1)       display select on HEX3..HEX0:
--                 '0' = PC, '1' = SOP (last value written by SSOP)
--
-- Board observables:
--   LEDR(9)     debug_mode
--   LEDR(8)     z_flag
--   LEDR(7:2)   opcode
--   LEDR(1:0)   AM
--   HEX5:HEX4   FSM state (low nibble shown on HEX4)
--   HEX3:HEX0   PC or SOP (per SW(1))
--
-- Supersedes top_smoke.vhd (the W2.1-era compile-check top).
-- ============================================================

ENTITY top_level IS
    GENERIC (
        -- Defaults are board values; a testbench overrides them small so
        -- key debounce and HEX refresh happen in a few cycles, not ms.
        DEB_TICKS   : NATURAL := 26000;    -- debounce sample period - 1 (~2.6 ms @10 MHz)
        HEX_REFRESH : NATURAL := 2_500_000 -- HEX latch period - 1 (~4 Hz @10 MHz)
    );
    PORT
    (
        CLOCK_50 : IN STD_LOGIC;
        KEY      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        SW       : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        LEDR     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
        HEX0     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX1     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX2     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX3     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX4     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX5     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END ENTITY top_level;

ARCHITECTURE rtl OF top_level IS

    -- ===== Clock + reset =====
    SIGNAL sys_clk       : STD_LOGIC; -- 10 MHz PLL output, drives everything
    SIGNAL pll_locked    : STD_LOGIC; -- PLL lock indicator
    SIGNAL key0_reset    : STD_LOGIC; -- raw active-high reset from KEY(0)
    SIGNAL reset         : STD_LOGIC; -- gated reset (held until PLL locked)

    -- ===== Board controls =====
    SIGNAL debug_mode    : STD_LOGIC;
    SIGNAL key3_reg      : STD_LOGIC := '1';
    SIGNAL debug_step    : STD_LOGIC := '0';

    -- ===== ReCOP <-> NI =====
    SIGNAL sip_sig       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL sop_sig       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr_sig      : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL dpcr_load_sig : STD_LOGIC;

    -- ===== Memory-mapped board I/O (W5) =====
    SIGNAL io_sw_sig     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_events_sig : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_led_sig    : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_hex_sig    : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_period_sig : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_clear_sig  : STD_LOGIC;
    -- KEY debounce (sampled at DEB_TICKS): sticky press flags
    -- bit0 = KEY1 (mode), bit1 = KEY2 (ack)
    SIGNAL deb_cnt       : UNSIGNED(15 DOWNTO 0)         := (OTHERS => '0');
    SIGNAL key1_prev     : STD_LOGIC                     := '1';
    SIGNAL key2_prev     : STD_LOGIC                     := '1';
    SIGNAL events_reg    : STD_LOGIC_VECTOR(1 DOWNTO 0)  := "00";
    -- HEX display throttle (~4 Hz): a slow snapshot so fast values are readable
    SIGNAL ref_cnt       : UNSIGNED(23 DOWNTO 0)         := (OTHERS => '0');
    SIGNAL hex_disp      : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    -- Debug-display segment source for HEX4 (FSM state)
    SIGNAL state_seg     : STD_LOGIC_VECTOR(6 DOWNTO 0);

    -- ===== ReCOP debug surface =====
    SIGNAL pc_sig        : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_sig        : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_sig    : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_sig        : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL state_sig     : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL z_flag_sig    : STD_LOGIC;

    -- ===== Display mux =====
    SIGNAL display_val   : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- ===== NoC fabric =====
    CONSTANT NOC_PORTS   : POSITIVE := 8;
    SIGNAL sends         : tdma_min_ports(0 TO NOC_PORTS - 1);
    SIGNAL recvs         : tdma_min_ports(0 TO NOC_PORTS - 1);

    COMPONENT recop IS
        PORT
        (
            clk            : IN STD_LOGIC;
            reset          : IN STD_LOGIC;
            z_flag         : OUT STD_LOGIC;
            debug_mode     : IN STD_LOGIC;
            debug_step     : IN STD_LOGIC;
            sip            : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            sop            : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dpcr           : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            dpcr_load      : OUT STD_LOGIC;
            io_sw          : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            io_events      : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            io_led         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            io_hex         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            io_period      : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            io_event_clear : OUT STD_LOGIC;
            pc_out         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rz_out         : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            opcode_out     : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
            am_out         : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            state_out      : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT recop_ni IS
        PORT
        (
            clock      : IN STD_LOGIC;
            reset      : IN STD_LOGIC;
            dpcr_in    : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
            dpcr_load  : IN STD_LOGIC;
            sip_out    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            period_out : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            send       : OUT tdma_min_port;
            recv       : IN tdma_min_port
        );
    END COMPONENT;

    COMPONENT TdmaMin IS
        GENERIC (ports : POSITIVE);
        PORT
        (
            clock : IN STD_LOGIC;
            sends : IN tdma_min_ports(0 TO ports - 1);
            recvs : OUT tdma_min_ports(0 TO ports - 1)
        );
    END COMPONENT;

    COMPONENT adc_asp IS
        GENERIC (
            clock_hz      : POSITIVE := 50_000_000;
            phase_bits    : POSITIVE := 16;
            lut_addr_bits : POSITIVE := 10
        );
        PORT
        (
            clock : IN STD_LOGIC;
            send  : OUT tdma_min_port;
            recv  : IN tdma_min_port
        );
    END COMPONENT;

    COMPONENT avg_asp IS
        PORT
        (
            clock : IN STD_LOGIC;
            send  : OUT tdma_min_port;
            recv  : IN tdma_min_port
        );
    END COMPONENT;

    COMPONENT hex_to_7seg IS
        PORT
        (
            hex_in  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
            seg_out : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT system_pll_10 IS
        PORT
        (
            refclk   : IN STD_LOGIC;
            rst      : IN STD_LOGIC;
            outclk_0 : OUT STD_LOGIC;
            locked   : OUT STD_LOGIC
        );
    END COMPONENT;

    COMPONENT cor_asp_noc IS
        GENERIC (
            MY_NODE_ID   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011"; -- port 3
            DEFAULT_DEST : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100"  -- port 4 (PD slot)
        );
        PORT
        (
            clock         : IN STD_LOGIC;
            reset         : IN STD_LOGIC;
            send          : OUT tdma_min_port;
            recv          : IN tdma_min_port;
            dbg_enable    : OUT STD_LOGIC;
            dbg_busy      : OUT STD_LOGIC;
            dbg_window    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dbg_samples   : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dbg_corrs     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dbg_last_corr : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

    -- PeakDetector (pd_asp): teammate IP. Exposes the tdma_min_port
    -- record directly, so it drops straight onto a NoC port with no
    -- adapter. It consumes Data packets (type 1000) routed to it and,
    -- once enabled by its own config packet (type 1100), reports peaks.
    -- See header note re: enabling PD output before driving the NoC.
    COMPONENT PeakDetector IS
        PORT
        (
            clock : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            send  : OUT tdma_min_port;
            recv  : IN tdma_min_port
        );
    END COMPONENT;

BEGIN

    -- ===== Clock generation =====
    -- CLOCK_50 (50 MHz) -> system_pll_10 -> 10 MHz sys_clk.
    -- PLL rst is active-high; tie to KEY(0) reset so PLL re-locks on reset.
    key0_reset <= NOT KEY(0);

    U_PLL : system_pll_10 PORT MAP
    (
        refclk   => CLOCK_50,
        rst      => key0_reset,
        outclk_0 => sys_clk,
        locked   => pll_locked
    );

    -- Hold design in reset until KEY(0) released AND PLL locked.
    reset      <= key0_reset OR NOT pll_locked;
    -- FSM-freeze single-stepping needs a dedicated switch, and the W5 board
    -- map has none spare, so freeze is disabled for the application build.
    -- KEY(3)/debug_step wiring is kept (inert while debug_mode = '0').
    debug_mode <= '0';

    -- KEY(3) rising-edge detector -> single-cycle debug_step pulse
    step_detect : PROCESS (sys_clk)
    BEGIN
        IF rising_edge(sys_clk) THEN
            key3_reg   <= KEY(3);
            debug_step <= '0';
            IF KEY(3) = '0' AND key3_reg = '1' THEN
                debug_step <= '1';
            END IF;
        END IF;
    END PROCESS step_detect;

    -- ===== Board input to ReCOP (memory-mapped) =====
    -- KEY debounce + sticky event latch.
    -- The keys are sampled only once per DEB_TICKS cycles (~2.6 ms on the
    -- board). Bounce (sub-ms) settles between samples, so one physical press
    -- registers exactly one event. A press (active-low: high-then-low across
    -- two samples) sets a sticky flag the ReCOP program reads at $FF1 and
    -- clears by writing $FF1 (io_clear_sig). KEY1=cycle mode, KEY2=ack.
    debounce : PROCESS (sys_clk)
    BEGIN
        IF rising_edge(sys_clk) THEN
            IF reset = '1' THEN
                deb_cnt    <= (OTHERS => '0');
                events_reg <= "00";
                key1_prev  <= '1';
                key2_prev  <= '1';
            ELSE
                IF io_clear_sig = '1' THEN
                    events_reg <= "00";
                END IF;
                IF deb_cnt >= DEB_TICKS THEN
                    deb_cnt <= (OTHERS => '0');
                    -- sample tick: detect a fresh press, then re-arm on release
                    IF key1_prev = '1' AND KEY(1) = '0' THEN
                        events_reg(0) <= '1';
                    END IF;
                    IF key2_prev = '1' AND KEY(2) = '0' THEN
                        events_reg(1) <= '1';
                    END IF;
                    key1_prev <= KEY(1);
                    key2_prev <= KEY(2);
                ELSE
                    deb_cnt <= deb_cnt + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS debounce;

    -- Switches presented as a 16-bit word at $FF0.
    io_sw_sig     <= "000000" & SW;
    io_events_sig <= "00000000000000" & events_reg;

    -- HEX display throttle: latch io_hex into hex_disp at ~HEX_REFRESH so a
    -- fast-changing value is sampled slowly enough to read on the 7-seg.
    hex_throttle : PROCESS (sys_clk)
    BEGIN
        IF rising_edge(sys_clk) THEN
            IF reset = '1' THEN
                ref_cnt  <= (OTHERS => '0');
                hex_disp <= (OTHERS => '0');
            ELSIF ref_cnt >= HEX_REFRESH THEN
                ref_cnt  <= (OTHERS => '0');
                hex_disp <= io_hex_sig;
            ELSE
                ref_cnt <= ref_cnt + 1;
            END IF;
        END IF;
    END PROCESS hex_throttle;

    -- ===== ReCOP core =====
    U_RECOP : recop PORT
    MAP
    (
    clk            => sys_clk,
    reset          => reset,
    z_flag         => z_flag_sig,
    debug_mode     => debug_mode,
    debug_step     => debug_step,
    sip            => sip_sig,
    sop            => sop_sig,
    dpcr           => dpcr_sig,
    dpcr_load      => dpcr_load_sig,
    io_sw          => io_sw_sig,
    io_events      => io_events_sig,
    io_led         => io_led_sig,
    io_hex         => io_hex_sig,
    io_period      => io_period_sig,
    io_event_clear => io_clear_sig,
    pc_out         => pc_sig,
    rz_out         => rz_sig,
    opcode_out     => opcode_sig,
    am_out         => am_sig,
    state_out      => state_sig
    );

    -- ===== Network interface (ReCOP <-> NoC port 0) =====
    U_NI : recop_ni PORT
    MAP (
    clock      => sys_clk,
    reset      => reset,
    dpcr_in    => dpcr_sig,
    dpcr_load  => dpcr_load_sig,
    sip_out    => sip_sig,
    period_out => io_period_sig,
    send       => sends(0),
    recv       => recvs(0)
    );

    -- ===== ASPs (verified in sim through W2.3) =====
    -- Override clock_hz so the DDS SR_DIV table matches the 10 MHz sys_clk.
    U_ADC : adc_asp
    GENERIC MAP(clock_hz => 10_000_000)
    PORT
    MAP (
    clock => sys_clk,
    send  => sends(1),
    recv  => recvs(1)
    );

    U_AVG : avg_asp PORT
    MAP (
    clock => sys_clk,
    send  => sends(2),
    recv  => recvs(2)
    );

    -- ===== COR-ASP via adapter (NoC port 3) =====
    -- Wrapper defaults already set MY_NODE_ID="0011" and DEFAULT_DEST="0100",
    -- so no GENERIC MAP override needed at this site.
    U_COR : cor_asp_noc PORT
    MAP (
    clock         => sys_clk,
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

    -- ===== PD-ASP (NoC port 4) =====
    -- PeakDetector uses the tdma_min_port record natively, so it wires
    -- straight to the fabric. Active-high reset shared with the system.
    U_PD : PeakDetector PORT
    MAP (
    clock => sys_clk,
    reset => reset,
    send  => sends(4),
    recv  => recvs(4)
    );

    -- ===== Ports 5..7 idle (reserved per topology comment in header) =====
    gen_unused : FOR i IN 5 TO NOC_PORTS - 1 GENERATE
        sends(i).addr <= (OTHERS => '0');
        sends(i).data <= (OTHERS => '0');
    END GENERATE;

    -- ===== NoC fabric =====
    U_NOC : TdmaMin
    GENERIC MAP(ports => NOC_PORTS)
    PORT
    MAP (
    clock => sys_clk,
    sends => sends,
    recvs => recvs
    );

    -- ===== Board observables =====
    -- SW(7) selects the display source without rebuilding the bitstream:
    --   SW(7)='0' : APPLICATION view  - LEDs/HEX driven by the ReCOP
    --               program via memory-mapped $FF2 (LED) and $FF3 (HEX).
    --   SW(7)='1' : DEBUG view        - PC on HEX3:0, FSM state on HEX4,
    --               {debug_mode,z,opcode,am} on LEDR (the GP-1 surface).
    LEDR <= (debug_mode & z_flag_sig & opcode_sig & am_sig) WHEN SW(7) = '1' ELSE
        io_led_sig(9 DOWNTO 0);

    display_val <= pc_sig WHEN SW(7) = '1' ELSE
        hex_disp;

    H_D0 : hex_to_7seg PORT
    MAP (hex_in => display_val(3 DOWNTO 0), seg_out => HEX0);
    H_D1 : hex_to_7seg PORT
    MAP (hex_in => display_val(7 DOWNTO 4), seg_out => HEX1);
    H_D2 : hex_to_7seg PORT
    MAP (hex_in => display_val(11 DOWNTO 8), seg_out => HEX2);
    H_D3 : hex_to_7seg PORT
    MAP (hex_in => display_val(15 DOWNTO 12), seg_out => HEX3);

    -- HEX4 shows FSM state in debug view, blanked in application view.
    H_S : hex_to_7seg PORT
    MAP (hex_in => '0' & state_sig, seg_out => state_seg);
    HEX4 <= state_seg WHEN SW(7) = '1' ELSE
        (OTHERS         => '1');
    HEX5 <= (OTHERS => '1');

END ARCHITECTURE rtl;
