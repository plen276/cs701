LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

-- ============================================================
-- 4-bit value -> DE1-SoC 7-segment pattern (active low).
-- 0x0..0x9 : digits 0..9
-- 0xA      : '-' (sign for negative result)
-- 0xB..0xF : blank
-- ============================================================
ENTITY hex_to_7seg IS
    PORT (
        hex_in  : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
        seg_out : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END ENTITY hex_to_7seg;

ARCHITECTURE behaviour OF hex_to_7seg IS
BEGIN
    PROCESS(hex_in)
    BEGIN
        CASE hex_in IS
            WHEN "0000" => seg_out <= "1000000"; -- 0
            WHEN "0001" => seg_out <= "1111001"; -- 1
            WHEN "0010" => seg_out <= "0100100"; -- 2
            WHEN "0011" => seg_out <= "0110000"; -- 3
            WHEN "0100" => seg_out <= "0011001"; -- 4
            WHEN "0101" => seg_out <= "0010010"; -- 5
            WHEN "0110" => seg_out <= "0000010"; -- 6
            WHEN "0111" => seg_out <= "1111000"; -- 7
            WHEN "1000" => seg_out <= "0000000"; -- 8
            WHEN "1001" => seg_out <= "0010000"; -- 9
            WHEN "1010" => seg_out <= "0111111"; -- '-'
            WHEN OTHERS => seg_out <= "1111111"; -- blank
        END CASE;
    END PROCESS;
END ARCHITECTURE behaviour;
