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
-- Clock: CLOCK_50 feeds a PLL (system_pll, 50 -> 25 MHz) and
-- everything downstream runs on the 25 MHz `sys_clk` domain.
-- The 50 MHz target failed setup timing (-7 ns slack on the
-- IR -> regfile-write path; see ReCOP datapath/CU notes); the
-- PLL drop to 25 MHz gives ~13 ns of margin and is functionally
-- sufficient. ADC sample-rate divisors are calculated against this
-- clock via the adc_asp clock_hz generic override below.
--
-- Topology:
--   NoC port 0  ReCOP + recop_ni
--   NoC port 1  adc_asp  (IP, DDS sine source)
--   NoC port 2  avg_asp  (IP, moving-average filter)
--   NoC port 3  cor_asp via cor_asp_noc adapter (teammate IP, packet
--               format aligned 2026-06-01)
--   NoC port 4  RESERVED for pd_asp   (PD team alignment pending, D5)
--   NoC port 5  RESERVED for Nios II bridge (W7, deferred)
--   NoC port 6  RESERVED for reconfig node  (W6)
--   NoC port 7  spare
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
    SIGNAL sys_clk       : STD_LOGIC; -- 25 MHz PLL output, drives everything
    SIGNAL pll_locked    : STD_LOGIC; -- PLL lock indicator
    SIGNAL key0_reset    : STD_LOGIC; -- raw active-high reset from KEY(0)
    SIGNAL reset         : STD_LOGIC; -- gated reset (asserted until PLL locked)

    -- ===== Board controls =====
    SIGNAL debug_mode    : STD_LOGIC;
    SIGNAL key3_reg      : STD_LOGIC := '1';
    SIGNAL debug_step    : STD_LOGIC := '0';

    -- ===== ReCOP <-> NI =====
    SIGNAL sip_sig       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL sop_sig       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr_sig      : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL dpcr_load_sig : STD_LOGIC;

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
            clk        : IN STD_LOGIC;
            reset      : IN STD_LOGIC;
            z_flag     : OUT STD_LOGIC;
            debug_mode : IN STD_LOGIC;
            debug_step : IN STD_LOGIC;
            sip        : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            sop        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dpcr       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            dpcr_load  : OUT STD_LOGIC;
            pc_out     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rz_out     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            opcode_out : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
            am_out     : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            state_out  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT recop_ni IS
        PORT
        (
            clock     : IN STD_LOGIC;
            reset     : IN STD_LOGIC;
            dpcr_in   : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
            dpcr_load : IN STD_LOGIC;
            sip_out   : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            send      : OUT tdma_min_port;
            recv      : IN tdma_min_port
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

    COMPONENT system_pll IS
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

BEGIN

    -- ===== Clock generation =====
    -- 50 MHz CLOCK_50 -> 25 MHz sys_clk via PLL.
    -- PLL's rst is active-high; tie to raw KEY(0)-derived reset so the
    -- PLL re-locks if the user presses the reset button.
    key0_reset <= NOT KEY(0);

    U_PLL : system_pll PORT MAP
    (
        refclk   => CLOCK_50,
        rst      => key0_reset,
        outclk_0 => sys_clk,
        locked   => pll_locked
    );

    -- Hold the design in reset until both KEY(0) is released AND the PLL
    -- has locked. Prevents downstream FFs from starting on garbage cycles.
    reset      <= key0_reset OR NOT pll_locked;
    debug_mode <= SW(0);

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

    -- ===== ReCOP core =====
    U_RECOP : recop PORT
    MAP (
    clk        => sys_clk,
    reset      => reset,
    z_flag     => z_flag_sig,
    debug_mode => debug_mode,
    debug_step => debug_step,
    sip        => sip_sig,
    sop        => sop_sig,
    dpcr       => dpcr_sig,
    dpcr_load  => dpcr_load_sig,
    pc_out     => pc_sig,
    rz_out     => rz_sig,
    opcode_out => opcode_sig,
    am_out     => am_sig,
    state_out  => state_sig
    );

    -- ===== Network interface (ReCOP <-> NoC port 0) =====
    U_NI : recop_ni PORT
    MAP (
    clock     => sys_clk,
    reset     => reset,
    dpcr_in   => dpcr_sig,
    dpcr_load => dpcr_load_sig,
    sip_out   => sip_sig,
    send      => sends(0),
    recv      => recvs(0)
    );

    -- ===== ASPs (verified in sim through W2.3) =====
    -- Override clock_hz so the DDS SR_DIV table matches the actual 25 MHz
    -- sys_clk. Without this, the ADC would assume 50 MHz and emit at half
    -- the configured sample rate (SR=11 -> 24 kHz instead of 48 kHz, etc).
    U_ADC : adc_asp
    GENERIC MAP(clock_hz => 25_000_000)
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

    -- ===== Ports 4..7 idle (reserved per topology comment in header) =====
    gen_unused : FOR i IN 4 TO NOC_PORTS - 1 GENERATE
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
    LEDR(9)          <= debug_mode;
    LEDR(8)          <= z_flag_sig;
    LEDR(7 DOWNTO 2) <= opcode_sig;
    LEDR(1 DOWNTO 0) <= am_sig;

    -- HEX3..HEX0: PC by default, SOP when SW(1) = '1' (lets ReCOP programs
    -- write visible output via SSOP without rebuilding the bitstream).
    display_val      <= sop_sig WHEN SW(1) = '1' ELSE
        pc_sig;

    H_D0 : hex_to_7seg PORT
    MAP (hex_in => display_val(3 DOWNTO 0), seg_out => HEX0);
    H_D1 : hex_to_7seg PORT
    MAP (hex_in => display_val(7 DOWNTO 4), seg_out => HEX1);
    H_D2 : hex_to_7seg PORT
    MAP (hex_in => display_val(11 DOWNTO 8), seg_out => HEX2);
    H_D3 : hex_to_7seg PORT
    MAP (hex_in => display_val(15 DOWNTO 12), seg_out => HEX3);

    -- HEX4 shows FSM state (3 bits, padded to a nibble). HEX5 blanked.
    H_S : hex_to_7seg PORT
    MAP (hex_in => '0' & state_sig, seg_out => HEX4);
    HEX5 <= (OTHERS => '1');

END ARCHITECTURE rtl;
