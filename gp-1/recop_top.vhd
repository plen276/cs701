LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;

-- ============================================================
-- ReCOP GP1 - DE1-SoC Top Level  (MMIO enabled)
-- KEY(0) active-low  -> reset.
-- KEY(3:1) are made available to the processor as active-high
-- bits 3:1 in the KEY MMIO register (bit 0 = 0 because it is
-- the reset key).
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
        HEX3     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX4     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX5     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END ENTITY recop_top;

ARCHITECTURE structural OF recop_top IS

    SIGNAL clk       : bit_1;
    SIGNAL reset     : bit_1;
    SIGNAL z_flag    : bit_1;

    SIGNAL key_act_h : STD_LOGIC_VECTOR(3 DOWNTO 0);

    SIGNAL hex0_v : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL hex1_v : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL hex2_v : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL hex3_v : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL hex4_v : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL hex5_v : STD_LOGIC_VECTOR(3 DOWNTO 0);

    COMPONENT recop IS
        PORT (
            clk    : IN  bit_1;
            reset  : IN  bit_1;
            z_flag : OUT bit_1;
            sw_in  : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
            key_in : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
            hex0_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            hex1_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            hex2_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            hex3_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            hex4_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            hex5_o : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
            ledr_o : OUT STD_LOGIC_VECTOR(9 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT hex_to_7seg IS
        PORT (
            hex_in  : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
            seg_out : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    clk   <= CLOCK_50;
    reset <= NOT KEY(0);

    -- Active-high key bus for the processor. Bit 0 is tied low
    -- because KEY(0) is the reset button, never visible to code.
    key_act_h(0) <= '0';
    key_act_h(1) <= NOT KEY(1);
    key_act_h(2) <= NOT KEY(2);
    key_act_h(3) <= NOT KEY(3);

    PROC : recop PORT MAP (
        clk    => clk,
        reset  => reset,
        z_flag => z_flag,
        sw_in  => SW,
        key_in => key_act_h,
        hex0_o => hex0_v,
        hex1_o => hex1_v,
        hex2_o => hex2_v,
        hex3_o => hex3_v,
        hex4_o => hex4_v,
        hex5_o => hex5_v,
        ledr_o => LEDR
    );

    SEG0 : hex_to_7seg PORT MAP (hex_in => hex0_v, seg_out => HEX0);
    SEG1 : hex_to_7seg PORT MAP (hex_in => hex1_v, seg_out => HEX1);
    SEG2 : hex_to_7seg PORT MAP (hex_in => hex2_v, seg_out => HEX2);
    SEG3 : hex_to_7seg PORT MAP (hex_in => hex3_v, seg_out => HEX3);
    SEG4 : hex_to_7seg PORT MAP (hex_in => hex4_v, seg_out => HEX4);
    SEG5 : hex_to_7seg PORT MAP (hex_in => hex5_v, seg_out => HEX5);

END ARCHITECTURE structural;
