LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY hex_to_7seg IS
    PORT (
        hex_in  : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
        seg_out : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)  -- active low (0 = segment ON)
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
            WHEN "1010" => seg_out <= "0001000"; -- A
            WHEN "1011" => seg_out <= "0000011"; -- B
            WHEN "1100" => seg_out <= "1000110"; -- C
            WHEN "1101" => seg_out <= "0100001"; -- D
            WHEN "1110" => seg_out <= "0000110"; -- E
            WHEN "1111" => seg_out <= "0001110"; -- F
            WHEN OTHERS => seg_out <= "1111111"; -- blank
        END CASE;
    END PROCESS;
END ARCHITECTURE behaviour;
