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
--   * Lab 2 reference NoC packet format (GP2 integration uses this
--     format so every node decodes packets the same way).
--   * Z. Salcic, R. Mikhael, "A new method for instantaneous
--     power system frequency measurement using reference points
--     detection", Elec. Power Sys. Res. 55 (2000) 97-102.
--   * Additional frequency analysis notes (Correlation calc ASM).
--
-- NOTE: COR-ASP only borrows the Lab 2 *packet wire format*; the
-- data it carries are AVG-filtered power-signal samples and
-- correlation results, NOT audio.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

PACKAGE cor_asp_pkg IS

    -- ============================================================
    -- 32-bit NoC packet format (Lab 2 reference format).
    --
    -- The most-significant nibble [31:28] is the packet TYPE.  The
    -- remaining fields depend on the type.  COR-ASP is a DP-style
    -- ASP, so it consumes Conf-DP configuration packets and Data
    -- packets, and emits Data packets.
    --
    --   bit  | Data packet       | Conf-DP packet
    --   -----+-------------------+-----------------------
    --   31:28| TYPE = 1000       | TYPE = 1001
    --   27:24| DEST              | DEST
    --   23:20| RESERVED (=0) ----+ NEXT (output destination)
    --   19:17| RESERVED (=0)     | MODE (command id)  [19:16]
    --      16| CH                |
    --   15:0 | VALUE (sample)    | VALUE (command parameter)
    --
    --   Data    : 1000 | DEST | RESERVED[23:17] | CH[16] | VALUE[15:0]
    --   Conf-DP : 1001 | DEST | NEXT[23:20] | MODE[19:16] | VALUE[15:0]
    --
    -- COR-ASP single-stream behaviour:
    --   * CH is ignored on input and driven to '0' on output.
    --   * RESERVED bits are always driven to '0'.
    --   * NEXT only exists in Conf-DP; it is latched into cfg_dest
    --     and re-used as DEST when COR-ASP emits its Data results.
    --
    -- MODE (command id, only meaningful for Conf-DP):
    --   0x0 SET_WINDOW   - value = correlation window 2n (4..256, even)
    --   0x2 SET_INTERVAL - value = #new samples between calculations (>=1)
    --   0x3 SET_SHIFT    - value[4:0] = output right-shift (0..31)
    --   0x4 SET_ENABLE   - value(0) = '1' enable, '0' disable
    --   0x5 RESET_BUF    - flush sample memory + counters
    --   (0x1 / 0x6 are legacy SET_DEST / SET_SRC, now unused: the
    --    output destination travels in NEXT and there is no SRC
    --    field in the Lab 2 format.)
    -- ============================================================

    -- Packet field positions
    CONSTANT PKT_TYPE_HI : INTEGER := 31;
    CONSTANT PKT_TYPE_LO : INTEGER := 28;
    CONSTANT PKT_DEST_HI : INTEGER := 27;
    CONSTANT PKT_DEST_LO : INTEGER := 24;
    -- Conf-DP only
    CONSTANT PKT_NEXT_HI : INTEGER := 23;
    CONSTANT PKT_NEXT_LO : INTEGER := 20;
    CONSTANT PKT_MODE_HI : INTEGER := 19;
    CONSTANT PKT_MODE_LO : INTEGER := 16;
    -- Data only
    CONSTANT PKT_CH_BIT  : INTEGER := 16;
    -- Shared payload / value
    CONSTANT PKT_VAL_HI  : INTEGER := 15;
    CONSTANT PKT_VAL_LO  : INTEGER := 0;

    -- Packet type codes (Lab 2 reference NoC format)
    CONSTANT PKT_TYPE_DATA     : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1000";
    CONSTANT PKT_TYPE_CONF_DP  : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1001";
    CONSTANT PKT_TYPE_CONF_ADC : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1010";
    CONSTANT PKT_TYPE_CONF_DAC : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1011";

    -- Conf-DP MODE (command) ids
    CONSTANT MODE_SET_WINDOW   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
    CONSTANT MODE_SET_INTERVAL : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0010";
    CONSTANT MODE_SET_SHIFT    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011";
    CONSTANT MODE_SET_ENABLE   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100";
    CONSTANT MODE_RESET_BUF    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0101";

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

    -- ============================================================
    -- Helpers to build packets
    -- ============================================================
    -- Conf-DP configuration packet:
    --   1001 | dest | next_dest | mode | value
    FUNCTION make_conf_dp (
        dest      : STD_LOGIC_VECTOR(3 DOWNTO 0);
        next_dest : STD_LOGIC_VECTOR(3 DOWNTO 0);
        mode      : STD_LOGIC_VECTOR(3 DOWNTO 0);
        value     : STD_LOGIC_VECTOR(15 DOWNTO 0)
    ) RETURN STD_LOGIC_VECTOR;

    -- Data packet:
    --   1000 | dest | reserved(0) | ch | value
    FUNCTION make_data (
        dest  : STD_LOGIC_VECTOR(3 DOWNTO 0);
        ch    : STD_LOGIC;
        value : STD_LOGIC_VECTOR(15 DOWNTO 0)
    ) RETURN STD_LOGIC_VECTOR;

END PACKAGE cor_asp_pkg;

PACKAGE BODY cor_asp_pkg IS

    FUNCTION make_conf_dp (
        dest      : STD_LOGIC_VECTOR(3 DOWNTO 0);
        next_dest : STD_LOGIC_VECTOR(3 DOWNTO 0);
        mode      : STD_LOGIC_VECTOR(3 DOWNTO 0);
        value     : STD_LOGIC_VECTOR(15 DOWNTO 0)
    ) RETURN STD_LOGIC_VECTOR IS
    BEGIN
        RETURN PKT_TYPE_CONF_DP & dest & next_dest & mode & value;
    END FUNCTION;

    FUNCTION make_data (
        dest  : STD_LOGIC_VECTOR(3 DOWNTO 0);
        ch    : STD_LOGIC;
        value : STD_LOGIC_VECTOR(15 DOWNTO 0)
    ) RETURN STD_LOGIC_VECTOR IS
        CONSTANT reserved : STD_LOGIC_VECTOR(6 DOWNTO 0) := (OTHERS => '0');
    BEGIN
        RETURN PKT_TYPE_DATA & dest & reserved & ch & value;
    END FUNCTION;

END PACKAGE BODY cor_asp_pkg;
