-- ============================================================
-- sample_mem.vhd
--
-- Internal sample memory of the COR-ASP. Inferred dual-read /
-- single-write block RAM. Two synchronous read ports allow the
-- correlation datapath to fetch both members of a pair in a
-- single cycle.
--
-- Default size 256 x 16 bits (8-bit address) supports correlation
-- windows up to 2n = 256, which is much larger than the typical
-- (32 or 64) windows used in the frequency-measurement pipeline.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY sample_mem IS
    GENERIC
    (
        DATA_WIDTH : INTEGER := 16;
        ADDR_WIDTH : INTEGER := 8
    );
    PORT
    (
        clk    : IN STD_LOGIC;

        -- Write port (from NI: one new sample per arriving DATA pkt)
        wr_en  : IN  STD_LOGIC;
        wr_addr: IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        wr_data: IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

        -- Two synchronous read ports (datapath: read both members of
        -- a correlation pair simultaneously).
        rd_addr_a : IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        rd_data_a : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

        rd_addr_b : IN  STD_LOGIC_VECTOR(ADDR_WIDTH - 1 DOWNTO 0);
        rd_data_b : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0)
    );
END ENTITY sample_mem;

ARCHITECTURE rtl OF sample_mem IS
    TYPE mem_t IS ARRAY (0 TO (2 ** ADDR_WIDTH) - 1)
                  OF STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL mem : mem_t := (OTHERS => (OTHERS => '0'));
BEGIN

    -- Quartus infers M10K / M9K dual-read RAM from this style.
    -- Two reads share the same memory array; write-then-read on
    -- the same cycle is unspecified (we never do it: writes only
    -- happen on DATA-packet arrival, reads only during compute).
    PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF wr_en = '1' THEN
                mem(TO_INTEGER(unsigned(wr_addr))) <= wr_data;
            END IF;
            rd_data_a <= mem(TO_INTEGER(unsigned(rd_addr_a)));
            rd_data_b <= mem(TO_INTEGER(unsigned(rd_addr_b)));
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;
