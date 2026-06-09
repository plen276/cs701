LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY confprog_build IS
    PORT
    (
        dataa  : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        datab  : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        result : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY confprog_build;

ARCHITECTURE rtl OF confprog_build IS
BEGIN
    -- Conf-Prog packet:
    -- [31:28] type = F
    -- [27:24] dest = 6, reconfig node
    -- [23:20] subcommand = dataa[3:0]
    -- [19:16] reserved = 0
    -- [15:0]  payload = datab[15:0]
    result <= x"F6" & dataa(3 DOWNTO 0) & x"0" & datab(15 DOWNTO 0);
END ARCHITECTURE rtl;
