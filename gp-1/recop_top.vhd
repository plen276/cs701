LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;

-- ============================================================
-- ReCOP GP1 — DE1-SoC Board Top Level
--
-- Instantiates the ReCOP processor core (recop.vhd).
-- KEY(0) held down = reset (active low button, active high reset).
-- Processor runs freely from CLOCK_50 when reset is released.
--
-- Board outputs (GP1 debug):
--   LEDR(0)   = z_flag
--   LEDR(9:1) = unused
--   HEX3-HEX0 = blanked until SOP is implemented in GP2
-- ============================================================

ENTITY recop_top IS
    PORT (
        CLOCK_50 : IN  STD_LOGIC;
        KEY      : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
        SW       : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
        LEDR     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
        HEX0     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX1     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX2     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX3     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END ENTITY recop_top;

ARCHITECTURE structural OF recop_top IS

    SIGNAL clk    : bit_1;
    SIGNAL reset  : bit_1;
    SIGNAL z_flag : bit_1;

    COMPONENT recop IS
        PORT (
            clk    : IN  bit_1;
            reset  : IN  bit_1;
            z_flag : OUT bit_1
        );
    END COMPONENT;

BEGIN

    clk   <= CLOCK_50;
    reset <= NOT KEY(0);   -- KEY(0) active low: pressed = reset asserted

    PROC : recop PORT MAP (
        clk    => clk,
        reset  => reset,
        z_flag => z_flag
    );

    -- Debug outputs
    LEDR(0)          <= z_flag;
    LEDR(9 DOWNTO 1) <= (OTHERS => '0');

    -- Blank all 7-segment displays (active low: all 1s = all segments off)
    -- Will be driven by SOP register in GP2
    HEX0 <= "1111111";
    HEX1 <= "1111111";
    HEX2 <= "1111111";
    HEX3 <= "1111111";

END ARCHITECTURE structural;
