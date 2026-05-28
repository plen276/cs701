-- ============================================================
-- cor_asp_pkg.vhd
--
-- Common types, constants and helpers for the Autocorrelation
-- ASP (COR-ASP). This package is independent from work.opcodes
-- and work.recop_types so that the ASP stays a true black box
-- with respect to the ReCOP/GP1 RTL.
--
-- Reference:
--   * COMPSYS 701 2026 IRP - 32-bit single-cycle TDMA-MIN, up to
--     8 nodes.
--   * Z. Salcic, R. Mikhael, "A new method for instantaneous
--     power system frequency measurement using reference points
--     detection", Elec. Power Sys. Res. 55 (2000) 97-102.
--   * Additional frequency analysis notes (Correlation calc ASM).
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

PACKAGE cor_asp_pkg IS

    -- ============================================================
    -- 32-bit NoC packet format (compatible with TDMA-MIN single-cycle
    -- transfer specified in the IRP brief, and with the 32-bit DPCR
    -- that ReCOP forms via the DATACALL instruction).
    --
    --    bit  | field           | width | description
    --    -----+-----------------+-------+----------------------------
    --   31:28 | DEST_ID         |   4   | destination node id (0..7)
    --   27:24 | SRC_ID          |   4   | source node id (0..7)
    --   23:20 | PKT_TYPE        |   4   | packet kind
    --   19:16 | CMD_ID          |   4   | command id (only for CMD)
    --   15:0  | PAYLOAD         |  16   | 16-bit unsigned data/value
    --
    -- PKT_TYPE values:
    --   0x0 CMD    - configuration command for the ASP
    --   0x1 DATA   - streaming data sample (input or output)
    --   0x2 STATUS - status / acknowledgement (optional)
    --   0x3 CTRL   - reset / enable broadcast
    --
    -- CMD CMD_ID values (PKT_TYPE = CMD):
    --   0x0 SET_WINDOW   - payload = correlation window 2n (4..256, even)
    --   0x1 SET_DEST     - payload[3:0] = output destination node id
    --   0x2 SET_INTERVAL - payload = #new samples between calculations (>=1)
    --   0x3 SET_SHIFT    - payload[4:0] = output right-shift (0..31)
    --   0x4 SET_ENABLE   - payload(0) = '1' enable, '0' disable
    --   0x5 RESET_BUF    - flush sample memory + counters
    --   0x6 SET_SRC      - payload[3:0] = expected source node id filter
    --                                     (set to 0xF to accept any source)
    -- ============================================================

    -- Packet field positions
    CONSTANT PKT_DEST_HI : INTEGER := 31;
    CONSTANT PKT_DEST_LO : INTEGER := 28;
    CONSTANT PKT_SRC_HI  : INTEGER := 27;
    CONSTANT PKT_SRC_LO  : INTEGER := 24;
    CONSTANT PKT_TYPE_HI : INTEGER := 23;
    CONSTANT PKT_TYPE_LO : INTEGER := 20;
    CONSTANT PKT_CMD_HI  : INTEGER := 19;
    CONSTANT PKT_CMD_LO  : INTEGER := 16;
    CONSTANT PKT_PAY_HI  : INTEGER := 15;
    CONSTANT PKT_PAY_LO  : INTEGER := 0;

    -- Packet type codes
    CONSTANT PKT_TYPE_CMD    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
    CONSTANT PKT_TYPE_DATA   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";
    CONSTANT PKT_TYPE_STATUS : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0010";
    CONSTANT PKT_TYPE_CTRL   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011";

    -- Command IDs
    CONSTANT CMD_SET_WINDOW   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
    CONSTANT CMD_SET_DEST     : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";
    CONSTANT CMD_SET_INTERVAL : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0010";
    CONSTANT CMD_SET_SHIFT    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011";
    CONSTANT CMD_SET_ENABLE   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100";
    CONSTANT CMD_RESET_BUF    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0101";
    CONSTANT CMD_SET_SRC      : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0110";

    -- Suggested default node assignments for the 8-port NoC
    --   (any team may reassign, but defaults are agreed for the
    --    reference frequency-relay pipeline).
    --
    --   id 0 - ReCOP
    --   id 1 - Nios II
    --   id 2 - ADC-ASP
    --   id 3 - AVG-ASP
    --   id 4 - COR-ASP   (this design)
    --   id 5 - PD-ASP
    --   id 6 - reserved
    --   id 7 - reserved
    CONSTANT NODE_ID_RECOP : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
    CONSTANT NODE_ID_NIOS  : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";
    CONSTANT NODE_ID_ADC   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0010";
    CONSTANT NODE_ID_AVG   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011";
    CONSTANT NODE_ID_COR   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100";
    CONSTANT NODE_ID_PD    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0101";
    CONSTANT NODE_ID_ANY   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";

    -- ============================================================
    -- Helpers to build / decode packets
    -- ============================================================
    FUNCTION pkt_pack (
        dest    : STD_LOGIC_VECTOR(3 DOWNTO 0);
        src     : STD_LOGIC_VECTOR(3 DOWNTO 0);
        ptype   : STD_LOGIC_VECTOR(3 DOWNTO 0);
        cmd     : STD_LOGIC_VECTOR(3 DOWNTO 0);
        payload : STD_LOGIC_VECTOR(15 DOWNTO 0)
    ) RETURN STD_LOGIC_VECTOR;

END PACKAGE cor_asp_pkg;

PACKAGE BODY cor_asp_pkg IS

    FUNCTION pkt_pack (
        dest    : STD_LOGIC_VECTOR(3 DOWNTO 0);
        src     : STD_LOGIC_VECTOR(3 DOWNTO 0);
        ptype   : STD_LOGIC_VECTOR(3 DOWNTO 0);
        cmd     : STD_LOGIC_VECTOR(3 DOWNTO 0);
        payload : STD_LOGIC_VECTOR(15 DOWNTO 0)
    ) RETURN STD_LOGIC_VECTOR IS
    BEGIN
        RETURN dest & src & ptype & cmd & payload;
    END FUNCTION;

END PACKAGE BODY cor_asp_pkg;
