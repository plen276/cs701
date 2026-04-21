LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- DE1-SoC Board I/O Test
-- Tests: KEY[3..0], SW[9..0], HEX0-HEX5[6..0], LEDR[9..0]
--
-- Behaviour:
--   SW[9..0]  -> LEDR[9..0]  (switches mirror directly to LEDs)
--
--   KEY[0] pressed -> HEX0 shows "0"
--   KEY[1] pressed -> HEX1 shows "1"
--   KEY[2] pressed -> HEX2 shows "2"
--   KEY[3] pressed -> HEX3 shows "3"
--   No key pressed -> all HEX show dashes "------"
--
--   HEX4 and HEX5 cycle through 0-9 using CLOCK_50
--   (HEX4 = seconds units, HEX5 = seconds tens, slow counter)
--
-- NOTE: HEX segments are active-low on DE1-SoC.
--       7-seg encoding: segment order is gfedcba (bit 6 downto 0)
-- ============================================================
ENTITY board_io_test IS
    PORT
    (
        CLOCK_50 : IN STD_LOGIC;
        KEY      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);  -- active-low push buttons
        SW       : IN STD_LOGIC_VECTOR(9 DOWNTO 0);  -- slide switches
        LEDR     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0); -- red LEDs
        HEX0     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX1     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX2     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX3     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX4     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX5     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END ENTITY board_io_test;

ARCHITECTURE rtl OF board_io_test IS

    -- --------------------------------------------------------
    -- 7-segment active-low digit encoding (gfedcba)
    -- --------------------------------------------------------
    --                               gfedcba
    CONSTANT SEG_0        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "1000000"; -- 0
    CONSTANT SEG_1        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "1111001"; -- 1
    CONSTANT SEG_2        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0100100"; -- 2
    CONSTANT SEG_3        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0110000"; -- 3
    CONSTANT SEG_4        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0011001"; -- 4
    CONSTANT SEG_5        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0010010"; -- 5
    CONSTANT SEG_6        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0000010"; -- 6
    CONSTANT SEG_7        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "1111000"; -- 7
    CONSTANT SEG_8        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0000000"; -- 8
    CONSTANT SEG_9        : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0010000"; -- 9
    CONSTANT SEG_DASH     : STD_LOGIC_VECTOR(6 DOWNTO 0)  := "0111111"; -- -

    -- --------------------------------------------------------
    -- Clock divider: 50 MHz -> 1 Hz
    -- --------------------------------------------------------
    CONSTANT CLK_DIV      : INTEGER                       := 49_999_999;
    SIGNAL clk_count      : INTEGER RANGE 0 TO 49_999_999 := 0;

    -- --------------------------------------------------------
    -- BCD counters for HEX4 (units) and HEX5 (tens)
    -- --------------------------------------------------------
    SIGNAL count_units    : INTEGER RANGE 0 TO 9          := 0;
    SIGNAL count_tens     : INTEGER RANGE 0 TO 9          := 0;

    -- --------------------------------------------------------
    -- BCD to 7-segment decoder
    -- --------------------------------------------------------
    FUNCTION bcd_to_seg(n : INTEGER) RETURN STD_LOGIC_VECTOR IS
    BEGIN
        CASE n IS
            WHEN 0      => RETURN SEG_0;
            WHEN 1      => RETURN SEG_1;
            WHEN 2      => RETURN SEG_2;
            WHEN 3      => RETURN SEG_3;
            WHEN 4      => RETURN SEG_4;
            WHEN 5      => RETURN SEG_5;
            WHEN 6      => RETURN SEG_6;
            WHEN 7      => RETURN SEG_7;
            WHEN 8      => RETURN SEG_8;
            WHEN 9      => RETURN SEG_9;
            WHEN OTHERS => RETURN SEG_DASH;
        END CASE;
    END FUNCTION;

BEGIN

    -- --------------------------------------------------------
    -- Test 1: SW[8..0] mirrors to LEDR[8..0]
    -- --------------------------------------------------------
    LEDR <= SW;

    -- --------------------------------------------------------
    -- Test 2: press KEY[x] to show its number on HEX[x]
    --         dash displayed when key is released
    -- --------------------------------------------------------
    HEX0 <= SEG_0 WHEN KEY(0) = '0' ELSE
        SEG_DASH;
    HEX1 <= SEG_1 WHEN KEY(1) = '0' ELSE
        SEG_DASH;
    HEX2 <= SEG_2 WHEN KEY(2) = '0' ELSE
        SEG_DASH;
    HEX3 <= SEG_3 WHEN KEY(3) = '0' ELSE
        SEG_DASH;

    -- --------------------------------------------------------
    -- Test 3: HEX4/HEX5 count seconds 00->99 using 50 MHz clock
    -- --------------------------------------------------------
    counter_proc : PROCESS (CLOCK_50)
    BEGIN
        IF rising_edge(CLOCK_50) THEN
            IF clk_count = CLK_DIV THEN
                clk_count <= 0;
                IF count_units = 9 THEN
                    count_units <= 0;
                    IF count_tens = 9 THEN
                        count_tens <= 0;
                    ELSE
                        count_tens <= count_tens + 1;
                    END IF;
                ELSE
                    count_units <= count_units + 1;
                END IF;
            ELSE
                clk_count <= clk_count + 1;
            END IF;
        END IF;
    END PROCESS counter_proc;

    HEX4 <= bcd_to_seg(count_units);
    HEX5 <= bcd_to_seg(count_tens);

END ARCHITECTURE rtl;
