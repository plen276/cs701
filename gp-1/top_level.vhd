LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

-- ============================================================
-- ReCOP GP1: DE1-SoC Board Top Level
--
-- KEY(0) held = reset (active low)
-- SW(0)       = debug mode (freeze FSM)
-- KEY(3)      = single step (advances FSM one state in debug mode)
-- SW(1)       = display select: '0'=PC on HEX3:0, '1'=Rz on HEX3:0
--
-- LEDR(0)     = debug mode indicator
-- LEDR(1)     = z_flag
-- LEDR(9:8)   = AM (2 bits)
-- LEDR(7:2)   = opcode (6 bits)
--
-- HEX3:HEX0  = PC or Rz (16-bit as 4 hex digits, SW(1) selects)
-- HEX5:HEX4  = FSM state (single digit on HEX5, HEX4 blanked)
--   0=IDLE 1=FETCH_1 2=FETCH_2 3=WAIT_MEM 4=EXECUTE 5=FETCH_JUMP
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

    SIGNAL clk         : STD_LOGIC;
    SIGNAL reset       : STD_LOGIC;
    SIGNAL z_flag      : STD_LOGIC;

    SIGNAL debug_mode  : STD_LOGIC;
    SIGNAL debug_step  : STD_LOGIC;

    SIGNAL pc_val      : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_val      : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL opcode_val  : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am_val      : STD_LOGIC_VECTOR(1 DOWNTO 0);

    SIGNAL state_val   : STD_LOGIC_VECTOR(2 DOWNTO 0);

    SIGNAL display_val : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- KEY edge detection
    SIGNAL key3_prev   : STD_LOGIC;

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

    -- LED assignments
    LEDR(0)          <= debug_mode;
    LEDR(1)          <= z_flag;
    LEDR(9 DOWNTO 8) <= am_val;
    LEDR(7 DOWNTO 2) <= opcode_val;

    -- 7-segment display value: PC or Rz selected by SW(8)
    display_val      <= rz_val WHEN SW(1) = '1' ELSE
        pc_val;

    H0 : hex_to_7seg PORT
    MAP (hex_in => display_val(3 DOWNTO 0), seg_out => HEX0);
    H1 : hex_to_7seg PORT
    MAP (hex_in => display_val(7 DOWNTO 4), seg_out => HEX1);
    H2 : hex_to_7seg PORT
    MAP (hex_in => display_val(11 DOWNTO 8), seg_out => HEX2);
    H3 : hex_to_7seg PORT
    MAP (hex_in => display_val(15 DOWNTO 12), seg_out => HEX3);

    -- FSM state on HEX5 (0-5), HEX4 blanked
    H5 : hex_to_7seg PORT
    MAP (hex_in => '0' & state_val, seg_out => HEX5);
    HEX4 <= "1111111";

END ARCHITECTURE structural;
