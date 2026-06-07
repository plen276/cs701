LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- top_level_nios
--
-- Full HMPSoC top: the critical part (ReCOP + TDMA-MIN NoC + ASPs,
-- identical to top_level.vhd) PLUS the Nios II monitor subsystem on
-- NoC port 5. Kept as a SEPARATE top so top_level.vhd still builds
-- the critical part on its own (the Nios part stays modular and does
-- not affect the rest of the system).
--
-- Clocking: the Nios subsystem is a clock SINK -- it runs on the very
-- same 25 MHz sys_clk as ReCOP/NoC (single clock domain, NO CDC).
-- This requires the Qsys system (Nios_System_2A) to be reconfigured
-- to take an EXTERNAL clock and use ON-CHIP memory (no SDRAM PLL).
-- See the integration notes for the exact Platform Designer steps.
--
-- Nios role: passive monitor + output. It only touches the NoC (via
-- noc_avalon_bridge on port 5) and the JTAG-UART (printf). It owns no
-- board pins, so it cannot disturb the rest of the design. Whatever
-- the pipeline routes to port 5 (e.g. COR or PD results) is read and
-- printed by the Nios software; if the rest of the system misbehaves,
-- the Nios simply reports whatever it does (or does not) receive.
--
-- Canonical id<->port map (unchanged):
--   0 ReCOP | 1 ADC | 2 AVG | 3 COR | 4 PD | 5 Nios | 6,7 spare
--
-- IMPORTANT - generated Qsys port names: this instantiation assumes
-- the reconfigured Nios_System_2A exports
--     clk_clk         (in)   <- 25 MHz system clock
--     reset_reset_n   (in)   <- active-low reset
--     noc_send_data/addr (out), noc_recv_data/addr (in)  (conduit "noc")
-- If your Platform Designer export names differ, rename the four
-- conduit ports / clk / reset below to match Nios_System_2A.
-- ============================================================

ENTITY top_level_nios IS
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
END ENTITY top_level_nios;

ARCHITECTURE rtl OF top_level_nios IS

    -- ===== Clock + reset =====
    SIGNAL sys_clk       : STD_LOGIC;
    SIGNAL pll_locked    : STD_LOGIC;
    SIGNAL key0_reset    : STD_LOGIC;
    SIGNAL reset         : STD_LOGIC;

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

    -- ===== Nios subsystem conduit (flattened tdma_min_port) =====
    SIGNAL nios_send_data : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL nios_send_addr : STD_LOGIC_VECTOR(7 DOWNTO 0);

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
            MY_NODE_ID   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011";
            DEFAULT_DEST : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100"
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

    COMPONENT PeakDetector IS
        PORT
        (
            clock : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            send  : OUT tdma_min_port;
            recv  : IN tdma_min_port
        );
    END COMPONENT;

    -- Reconfigured Lab-1 Part-2 Qsys system: Nios II + on-chip RAM +
    -- JTAG-UART + noc_avalon_bridge, clocked externally at 25 MHz.
    COMPONENT Nios_System_2A IS
        PORT
        (
            clk_clk       : IN  STD_LOGIC;
            reset_reset_n : IN  STD_LOGIC;
            noc_send_data : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            noc_send_addr : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            noc_recv_data : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            noc_recv_addr : IN  STD_LOGIC_VECTOR(7 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    -- ===== Clock generation (50 -> 25 MHz) =====
    key0_reset <= NOT KEY(0);

    U_PLL : system_pll PORT MAP
    (
        refclk   => CLOCK_50,
        rst      => key0_reset,
        outclk_0 => sys_clk,
        locked   => pll_locked
    );

    reset      <= key0_reset OR NOT pll_locked;
    debug_mode <= SW(0);

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

    -- ===== ReCOP core (port 0) =====
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

    -- ===== ASPs =====
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

    U_PD : PeakDetector PORT
    MAP (
    clock => sys_clk,
    reset => reset,
    send  => sends(4),
    recv  => recvs(4)
    );

    -- ===== Nios II monitor subsystem (NoC port 5) =====
    -- Same sys_clk domain as everything else (no CDC). Active-low
    -- reset. The bridge conduit is wrapped into the port-5 record.
    U_NIOS : Nios_System_2A PORT
    MAP (
    clk_clk       => sys_clk,
    reset_reset_n => NOT reset,
    noc_send_data => nios_send_data,
    noc_send_addr => nios_send_addr,
    noc_recv_data => recvs(5).data,
    noc_recv_addr => recvs(5).addr
    );

    sends(5).data <= nios_send_data;
    sends(5).addr <= nios_send_addr;

    -- ===== Ports 6..7 idle =====
    gen_unused : FOR i IN 6 TO NOC_PORTS - 1 GENERATE
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

    -- ===== Board observables (unchanged from top_level.vhd) =====
    LEDR(9)          <= debug_mode;
    LEDR(8)          <= z_flag_sig;
    LEDR(7 DOWNTO 2) <= opcode_sig;
    LEDR(1 DOWNTO 0) <= am_sig;

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

    H_S : hex_to_7seg PORT
    MAP (hex_in => '0' & state_sig, seg_out => HEX4);
    HEX5 <= (OTHERS => '1');

END ARCHITECTURE rtl;
