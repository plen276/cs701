LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- ============================================================
-- ReCOP GP1: DE1-SoC Board Top Level
--
-- KEY(0) held = reset (active low)
-- SW(0)       = debug mode (freeze FSM)
-- KEY(3)      = single step (advances FSM one state in debug mode)
-- SW(1)       = display select in debug mode: '0'=PC on HEX3:0, '1'=Rz on HEX3:0
--
-- Debug mode (SW(0)='1'):
--   LEDR(0)     = debug mode indicator
--   LEDR(1)     = z_flag
--   LEDR(9:8)   = AM (2 bits)
--   LEDR(7:2)   = opcode (6 bits)
--   HEX3:HEX0   = PC or Rz (16-bit as 4 hex digits, SW(1) selects)
--   HEX5        = FSM state digit (0-5)
--   HEX4        = blanked
--
-- Run mode (SW(0)='0'):
--   LEDR        = off
--   HEX5,3:0    = rotating segment heartbeat
--   HEX4        = blanked
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

ARCHITECTURE structural OF top_level IS

    SIGNAL clk                          : STD_LOGIC;
    SIGNAL reset                        : STD_LOGIC;
    SIGNAL z_flag                       : STD_LOGIC;

    SIGNAL debug_mode                   : STD_LOGIC;
    SIGNAL debug_step                   : STD_LOGIC;

    SIGNAL pc_val                       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_val                       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_val                   : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_val                       : STD_LOGIC_VECTOR(1 DOWNTO 0);

    SIGNAL state_val                    : STD_LOGIC_VECTOR(2 DOWNTO 0);

    SIGNAL display_val                  : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- KEY edge detection
    SIGNAL key3_prev                    : STD_LOGIC;

    -- Hex digit outputs from decoders
    SIGNAL seg0, seg1, seg2, seg3, seg5 : STD_LOGIC_VECTOR(6 DOWNTO 0);

    -- Run-mode heartbeat
    SIGNAL tick                         : UNSIGNED(23 DOWNTO 0) := (OTHERS => '0');
    SIGNAL hb_index                     : INTEGER RANGE 0 TO 5  := 0;
    SIGNAL hb_seg                       : STD_LOGIC_VECTOR(6 DOWNTO 0);

    COMPONENT recop IS
        PORT
        (
            clk        : IN STD_LOGIC;
            reset      : IN STD_LOGIC;
            z_flag     : OUT STD_LOGIC;
            debug_mode : IN STD_LOGIC;
            debug_step : IN STD_LOGIC;
            pc_out     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rz_out     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            opcode_out : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
            am_out     : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            state_out  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT hex_to_7seg IS
        PORT
        (
            hex_in  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
            seg_out : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    clk        <= CLOCK_50;
    reset      <= NOT KEY(0);
    debug_mode <= SW(0);

    -- Single-cycle pulse on falling edge of KEY(3) for step
    step_detect : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            key3_prev  <= KEY(3);
            debug_step <= '0';
            IF KEY(3) = '0' AND key3_prev = '1' THEN
                debug_step <= '1';
            END IF;
        END IF;
    END PROCESS step_detect;

    PROC : recop PORT MAP
    (
        clk        => clk,
        reset      => reset,
        z_flag     => z_flag,
        debug_mode => debug_mode,
        debug_step => debug_step,
        pc_out     => pc_val,
        rz_out     => rz_val,
        opcode_out => opcode_val,
        am_out     => am_val,
        state_out  => state_val
    );

    -- ============================================================
    -- Heartbeat tick: 50 MHz / 2^23 ≈ 6 Hz segment step
    -- ============================================================
    heartbeat_proc : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            tick <= tick + 1;
            IF tick(22 DOWNTO 0) = 0 THEN
                IF hb_index = 5 THEN
                    hb_index <= 0;
                ELSE
                    hb_index <= hb_index + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS heartbeat_proc;

    -- Heartbeat: light a single outer-ring segment in sequence (active low)
    -- Segments: a=top, b=top-right, c=bottom-right, d=bottom, e=bottom-left, f=top-left
    WITH hb_index SELECT hb_seg <=
        "1111110" WHEN 0,
        "1111101" WHEN 1,
        "1111011" WHEN 2,
        "1110111" WHEN 3,
        "1101111" WHEN 4,
        "1011111" WHEN 5,
        "1111111" WHEN OTHERS;

    -- ============================================================
    -- LED output: debug = processor state, run = off
    -- ============================================================
    LEDR <= (am_val & opcode_val & z_flag & debug_mode) WHEN debug_mode = '1' ELSE
        (OTHERS => '0');

    -- ============================================================
    -- HEX[3:0] value in debug = PC/Rz (ignored in run mode)
    -- ============================================================
    display_val <= rz_val WHEN debug_mode = '1' AND SW(1) = '1' ELSE
        pc_val;

    H0 : hex_to_7seg PORT
    MAP (hex_in => display_val(3 DOWNTO 0), seg_out => seg0);
    H1 : hex_to_7seg PORT
    MAP (hex_in => display_val(7 DOWNTO 4), seg_out => seg1);
    H2 : hex_to_7seg PORT
    MAP (hex_in => display_val(11 DOWNTO 8), seg_out => seg2);
    H3 : hex_to_7seg PORT
    MAP (hex_in => display_val(15 DOWNTO 12), seg_out => seg3);
    -- FSM state on HEX5 (0-5)
    H5 : hex_to_7seg PORT
    MAP (hex_in => '0' & state_val, seg_out => seg5);

    HEX0 <= seg0 WHEN debug_mode = '1' ELSE
        hb_seg;
    HEX1 <= seg1 WHEN debug_mode = '1' ELSE
        hb_seg;
    HEX2 <= seg2 WHEN debug_mode = '1' ELSE
        hb_seg;
    HEX3 <= seg3 WHEN debug_mode = '1' ELSE
        hb_seg;
    HEX4 <= "1111111"; -- always blank
    HEX5 <= seg5 WHEN debug_mode = '1' ELSE
        hb_seg;

END ARCHITECTURE structural;
