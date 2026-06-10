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
-- Clocking -- two domains from one PLL:
--   CLOCK_50 (50 MHz) -> system_pll_10 ->
--     outclk_0 = 10 MHz -> sys_clk  : the CRITICAL part (ReCOP, recop_ni, NoC,
--                                     ASPs, reconfig node) runs here. 10 MHz
--                                     because ReCOP cannot close timing higher
--                                     -- the IR->regfile-write path is the
--                                     limiter (the 50 MHz target failed setup).
--     outclk_1 = 50 MHz -> nios_clk : the Nios II subsystem runs here -- fast
--                                     enough for reliable JTAG download/debug
--                                     (10 MHz is too slow relative to JTAG TCK).
--
--   The two domains meet ONLY inside the Nios Qsys system, at its Avalon-MM
--   clock-crossing bridge: the Nios CPU/JTAG-UART/on-chip RAM are on 50 MHz,
--   while noc_avalon_bridge and recop_reset_pio sit on the 10 MHz side of that
--   bridge. So everything that touches the NoC (sends(5)/recvs(5)) and the
--   ReCOP reset (the recop_reset_pio output) is generated in the 10 MHz domain
--   -- no CDC on the NoC fabric or the ReCOP reset path; the sole crossing is
--   the proven Avalon clock-crossing bridge. See gp-2/docs/w7-nios-plan.md.
--
--   ADC sample-rate divisors are computed against 10 MHz via the clock_hz
--   generic override on the adc_asp instantiation below.
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
--   NoC port 5  Nios II bridge             (id 5)
--   NoC port 6  RESERVED for reconfig node  (W6)
--   NoC port 7  spare
--
--   Reference data pipeline (configured by the ReCOP boot program):
--     ADC(1) -> AVG(2) -> COR(3) -> PD(4)   [results -> ReCOP(0)]
--
-- Board controls (application build):
--   CLOCK_50    50 MHz board clock (input to PLL -> 10 MHz sys_clk + 50 MHz nios_clk)
--   KEY(0)      reset (active-low button -> active-high internal reset)
--   KEY(1)      cycle operating mode  RAW <-> MEASURE   (debounced, $FF1 bit0)
--   KEY(2)      acknowledge / clear the alarm latch      (debounced, $FF1 bit1)
--   KEY(3)      unused (debug-step scaffolding, inert)
--   SW(3:0)     FTW scenario select -- emulated grid frequency. Read at $FF0
--               only when a mode is (re)configured, so press KEY(1) to apply a
--               new setting. See the FTW table below.
--   SW(5:4)     ADC sample rate (00=8kHz default, 01=16k, 10=32k, 11=48k),
--               overlaid onto the Conf-ADC SR field by app.asm. Keep at 00 for
--               the calibrated alarm demo (FTW table / band assume 8 kHz).
--   SW(9:6)     unused (SW(7) view / SW(9) freeze were the old debug surface,
--               now disconnected -- see debug_mode note in the architecture).
--
-- Board observables (all driven by the ReCOP program via $FF2 LED / $FF3 HEX):
--   LEDR(0)     running heartbeat (lit while the main loop executes)
--   LEDR(1)     mode      (0 = RAW, 1 = MEASURE)
--   LEDR(2)     MEASURE pipeline active (lights together with LEDR(1))
--   LEDR(9:7)   alarm     (period outside the accept band; KEY(2) clears)
--   LEDR(6:3)   unused
--   HEX3:HEX0   RAW: latest raw ADC sample;  MEASURE: PD period count ($FF4)
--   HEX5:HEX4   blank
--
-- FTW switch table (SW[3:0]) -- emulated grid frequency and the 16-bit FTW the
-- app loads into the ADC-ASP.  FTW = round(f * 65536 / 8000) at ADC SR=00 (8kHz).
-- Accept band 48.5..51.5 Hz inclusive (validated on board: all 16 settings
-- behave as below, with the 48.5 Hz / 51.5 Hz endpoints reading in-band).
-- PMIN/PMAX live in test/app.asm (the authoritative copy of these values).
--   SW  f(Hz)   FTW      expected        SW  f(Hz)   FTW      expected
--   0   47.00   0x0181   ALARM (low)     8   47.50   0x0185   ALARM (low)
--   1   48.00   0x0189   ALARM (low)     9   48.50   0x018D   ok
--   2   49.00   0x0191   ok              A   49.25   0x0193   ok
--   3   49.50   0x0195   ok              B   49.75   0x0197   ok
--   4   50.00   0x019A   ok (nominal)    C   50.25   0x019C   ok
--   5   50.50   0x019E   ok              D   50.75   0x01A0   ok
--   6   51.00   0x01A2   ok              E   51.50   0x01A6   ok
--   7   52.00   0x01AA   ALARM (high)    F   52.50   0x01AE   ALARM (high)
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
    SIGNAL sys_clk              : STD_LOGIC; -- 10 MHz PLL output, drives everything
    SIGNAL nios_clk             : STD_LOGIC; -- 50 MHz PLL output, drives Nios
    SIGNAL pll_locked           : STD_LOGIC; -- PLL lock indicator
    SIGNAL key0_reset           : STD_LOGIC; -- raw active-high reset from KEY(0)
    SIGNAL reset                : STD_LOGIC; -- gated reset (held until PLL locked)
    SIGNAL nios_reset_n         : STD_LOGIC; -- active-low reset for Platform Designer

    -- ===== Board controls =====
    SIGNAL debug_mode           : STD_LOGIC;
    SIGNAL key3_reg             : STD_LOGIC := '1';
    SIGNAL debug_step           : STD_LOGIC := '0';

    -- ===== ReCOP <-> NI =====
    SIGNAL sip_sig              : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL sop_sig              : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr_sig             : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL dpcr_load_sig        : STD_LOGIC;

    -- ===== Memory-mapped board I/O (W5) =====
    SIGNAL io_sw_sig            : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_events_sig        : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_led_sig           : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_hex_sig           : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_period_sig        : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL io_clear_sig         : STD_LOGIC;
    -- KEY debounce (sampled at DEB_TICKS): sticky press flags
    -- bit0 = KEY1 (mode), bit1 = KEY2 (ack)
    SIGNAL deb_cnt              : UNSIGNED(15 DOWNTO 0)         := (OTHERS => '0');
    SIGNAL key1_prev            : STD_LOGIC                     := '1';
    SIGNAL key2_prev            : STD_LOGIC                     := '1';
    SIGNAL events_reg           : STD_LOGIC_VECTOR(1 DOWNTO 0)  := "00";
    -- HEX display throttle (~4 Hz): a slow snapshot so fast values are readable
    SIGNAL ref_cnt              : UNSIGNED(23 DOWNTO 0)         := (OTHERS => '0');
    SIGNAL hex_disp             : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    -- Debug-display segment source for HEX4 (FSM state)
    SIGNAL state_seg            : STD_LOGIC_VECTOR(6 DOWNTO 0);

    -- ===== W6 reconfig node <-> ReCOP PM write port =====
    SIGNAL pm_wr_en_sig         : STD_LOGIC;
    SIGNAL pm_wr_addr_sig       : STD_LOGIC_VECTOR(14 DOWNTO 0);
    SIGNAL pm_wr_data_sig       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL nios_recop_reset_sig : STD_LOGIC;
    SIGNAL recop_reset_sig      : STD_LOGIC;

    -- ===== ReCOP debug surface =====
    SIGNAL pc_sig               : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_sig               : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_sig           : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_sig               : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL state_sig            : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL z_flag_sig           : STD_LOGIC;

    -- ===== Display mux =====
    SIGNAL display_val          : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- ===== NoC fabric =====
    CONSTANT NOC_PORTS          : POSITIVE := 8;
    SIGNAL sends                : tdma_min_ports(0 TO NOC_PORTS - 1);
    SIGNAL recvs                : tdma_min_ports(0 TO NOC_PORTS - 1);
    SIGNAL nios_send_data       : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL nios_send_addr       : STD_LOGIC_VECTOR(7 DOWNTO 0);

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
            state_out      : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            pm_wr_en       : IN STD_LOGIC;
            pm_wr_addr     : IN STD_LOGIC_VECTOR(14 DOWNTO 0);
            pm_wr_data     : IN STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT reconfig_node IS
        PORT
        (
            clock      : IN STD_LOGIC;
            reset      : IN STD_LOGIC;
            send       : OUT tdma_min_port;
            recv       : IN tdma_min_port;
            pm_wr_en   : OUT STD_LOGIC;
            pm_wr_addr : OUT STD_LOGIC_VECTOR(14 DOWNTO 0);
            pm_wr_data : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
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
            outclk_1 : OUT STD_LOGIC;
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

    COMPONENT nios IS
        PORT
        (
            clk_clk                                    : IN  STD_LOGIC;                     -- 50 MHz (clk_nios)
            clk_1_clk                                  : IN  STD_LOGIC;                     -- 10 MHz (clk_noc)
            reset_reset_n                              : IN  STD_LOGIC;                     -- 50 MHz domain reset
            reset_0_reset_n                            : IN  STD_LOGIC;                     -- 10 MHz domain reset
            noc_noc_coe_send_data                      : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            noc_noc_coe_send_addr                      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            noc_noc_coe_recv_data                      : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            noc_noc_coe_recv_addr                      : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
            recop_reset_pio_external_connection_export : OUT STD_LOGIC
        );
    END COMPONENT nios;

BEGIN

    -- ===== Clock generation =====
    -- CLOCK_50 (50 MHz) -> system_pll_10 -> 10 MHz sys_clk.
    -- PLL rst is active-high; tie to KEY(0) reset so PLL re-locks on reset.
    key0_reset <= NOT KEY(0);

    U_PLL : system_pll_10 PORT MAP
    (
        refclk   => CLOCK_50,
        rst      => key0_reset,
        outclk_0 => sys_clk,  -- 10MHz
        outclk_1 => nios_clk, -- 50MHz
        locked   => pll_locked
    );

    -- Hold design in reset until KEY(0) released AND PLL locked.
    reset           <= key0_reset OR NOT pll_locked;
    nios_reset_n    <= NOT reset;
    recop_reset_sig <= reset OR nios_recop_reset_sig;
    -- Debug freeze/view removed for now: the board only ever runs the app
    -- (no FSM freeze, no display overlay). The debug scaffolding (pc_sig,
    -- state_sig, H_S, step_detect) is kept but disconnected, to be re-enabled
    -- later with a 2-FF synchroniser on the freeze switch -- feeding SW(9)
    -- straight into the clocked FSM caused metastable snapshots when toggled
    -- live.
    debug_mode      <= '0';

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
    reset          => recop_reset_sig,
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
    state_out      => state_sig,
    pm_wr_en       => pm_wr_en_sig,
    pm_wr_addr     => pm_wr_addr_sig,
    pm_wr_data     => pm_wr_data_sig
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

    -- ===== Nios II subsystem (NoC port 5, W7) =====
    -- Two clock domains: clk_clk = nios_clk (50 MHz) for the CPU/JTAG/RAM;
    -- clk_1_clk = sys_clk (10 MHz) for noc_bridge + recop_reset_pio behind the
    -- Avalon clock-crossing bridge. Both resets take NOT reset -- each Qsys
    -- clock_source re-synchronises it into its own domain.
    U_NIOS : nios PORT
    MAP (
    clk_clk                                    => nios_clk,
    clk_1_clk                                  => sys_clk,
    reset_reset_n                              => nios_reset_n,
    reset_0_reset_n                            => nios_reset_n,
    noc_noc_coe_send_data                      => nios_send_data,
    noc_noc_coe_send_addr                      => nios_send_addr,
    noc_noc_coe_recv_data                      => recvs(5).data,
    noc_noc_coe_recv_addr                      => recvs(5).addr,
    recop_reset_pio_external_connection_export => nios_recop_reset_sig
    );

    sends(5).data <= nios_send_data;
    sends(5).addr <= nios_send_addr;

    -- ===== Reconfig node (NoC port 6, W6) =====
    U_RECONFIG : reconfig_node PORT
    MAP (
    clock      => sys_clk,
    reset      => reset,
    send       => sends(6),
    recv       => recvs(6),
    pm_wr_en   => pm_wr_en_sig,
    pm_wr_addr => pm_wr_addr_sig,
    pm_wr_data => pm_wr_data_sig
    );

    -- ===== Port 7 idle (spare) =====
    sends(7).addr <= (OTHERS => '0');
    sends(7).data <= (OTHERS => '0');

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
    -- Application view only: LEDR and HEX3:0 are driven by the ReCOP program
    -- via memory-mapped $FF2 (LED) and $FF3 (HEX). The SW(7) debug-view mux is
    -- removed for now (see debug_mode note above).
    LEDR        <= io_led_sig(9 DOWNTO 0);

    display_val <= hex_disp;

    H_D0 : hex_to_7seg PORT
    MAP (hex_in => display_val(3 DOWNTO 0), seg_out => HEX0);
    H_D1 : hex_to_7seg PORT
    MAP (hex_in => display_val(7 DOWNTO 4), seg_out => HEX1);
    H_D2 : hex_to_7seg PORT
    MAP (hex_in => display_val(11 DOWNTO 8), seg_out => HEX2);
    H_D3 : hex_to_7seg PORT
    MAP (hex_in => display_val(15 DOWNTO 12), seg_out => HEX3);

    -- HEX5:HEX4 unused in the application view (blanked).
    -- H_S is retained scaffolding for the future debug view; its output
    -- (state_seg) is intentionally unused while debug is disconnected.
    H_S : hex_to_7seg PORT
    MAP (hex_in => '0' & state_sig, seg_out => state_seg);
    HEX4 <= (OTHERS => '1');
    HEX5 <= (OTHERS => '1');

END ARCHITECTURE rtl;
