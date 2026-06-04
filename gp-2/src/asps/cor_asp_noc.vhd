LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- GP-2 adapter for the teammate COR-ASP.
--
-- COR's core exposes packet/data-valid ports:
--   pkt_in, pkt_in_valid, pkt_out, pkt_out_valid
--
-- GP-2 NoC nodes expose tdma_min_port records:
--   send.addr, send.data, recv.addr, recv.data
--
-- This wrapper performs only that boundary conversion and applies the
-- project-wide NoC node IDs decided in docs/open-decisions.md D2.
ENTITY cor_asp_noc IS
    GENERIC
    (
        MY_NODE_ID   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011"; -- GP-2 COR port 3
        DEFAULT_DEST : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100"  -- GP-2 PD port 4
    );
    PORT
    (
        clock : IN  STD_LOGIC;
        reset : IN  STD_LOGIC;
        send  : OUT tdma_min_port;
        recv  : IN  tdma_min_port;

        dbg_enable    : OUT STD_LOGIC;
        dbg_busy      : OUT STD_LOGIC;
        dbg_window    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dbg_samples   : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dbg_corrs     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dbg_last_corr : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END ENTITY cor_asp_noc;

ARCHITECTURE rtl OF cor_asp_noc IS

    SIGNAL pkt_out       : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL pkt_out_valid : STD_LOGIC;

    COMPONENT cor_asp IS
        GENERIC
        (
            DATA_WIDTH       : INTEGER := 16;
            ADDR_WIDTH       : INTEGER := 8;
            ACC_WIDTH        : INTEGER := 32;
            N_WIDTH          : INTEGER := 8;
            MY_NODE_ID       : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0100";
            DEFAULT_DEST     : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0101";
            DEFAULT_WINDOW   : INTEGER := 64;
            DEFAULT_INTERVAL : INTEGER := 1;
            DEFAULT_SHIFT    : INTEGER := 6
        );
        PORT
        (
            clk           : IN  STD_LOGIC;
            reset         : IN  STD_LOGIC;
            pkt_in        : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            pkt_in_valid  : IN  STD_LOGIC;
            pkt_out       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            pkt_out_valid : OUT STD_LOGIC;
            dbg_enable    : OUT STD_LOGIC;
            dbg_busy      : OUT STD_LOGIC;
            dbg_window    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dbg_samples   : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dbg_corrs     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dbg_last_corr : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    U_COR : cor_asp
        GENERIC MAP (
            MY_NODE_ID   => MY_NODE_ID,
            DEFAULT_DEST => DEFAULT_DEST
        )
        PORT MAP (
            clk           => clock,
            reset         => reset,
            pkt_in        => recv.data,
            pkt_in_valid  => recv.data(31),
            pkt_out       => pkt_out,
            pkt_out_valid => pkt_out_valid,
            dbg_enable    => dbg_enable,
            dbg_busy      => dbg_busy,
            dbg_window    => dbg_window,
            dbg_samples   => dbg_samples,
            dbg_corrs     => dbg_corrs,
            dbg_last_corr => dbg_last_corr
        );

    send.data <= pkt_out                         WHEN pkt_out_valid = '1' ELSE (OTHERS => '0');
    send.addr <= "0000" & pkt_out(27 DOWNTO 24) WHEN pkt_out_valid = '1' ELSE (OTHERS => '0');

END ARCHITECTURE rtl;
