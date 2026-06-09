LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- ============================================================
-- noc_avalon_bridge
--
-- Network interface between a Nios II (Avalon-MM master) and a
-- TDMA-MIN NoC port. It is the Avalon-side analogue of recop_ni:
--
--   SEND (Nios -> NoC)
--     Writing a 32-bit word to register 0 (TX) latches it and
--     drives a one-shot packet on the conduit for exactly one
--     clock:
--         coe_send_data <= written word
--         coe_send_addr <= "0000" & word(27..24)   (DEST nibble)
--     This matches the routing convention used by recop_ni and
--     every ASP (the NoC FIFO enqueues on send_data(31), and all
--     valid packets carry 1xxx in bits 31..28, so a valid packet
--     self-triggers the FIFO). On idle cycles send_data is 0, so
--     bit 31 is low and nothing is (re)enqueued.
--
--   RECEIVE (NoC -> Nios)
--     Any incoming word with bit 31 = '1' is latched into the RX
--     register and a free-running 8-bit receive counter is
--     incremented. Software polls STATUS for the counter to change
--     (robust, never-lost indication) and then reads RX.
--
-- Register map (Avalon word addresses; byte offsets in []):
--   0 [0x0] WRITE TX     : 32-bit packet to transmit (write = send)
--   1 [0x4] READ  RX     : last 32-bit packet received (read clears
--                          the rx_valid status bit, not the counter)
--   2 [0x8] READ  STATUS : bit0      = rx_valid
--                          bits 15..8 = rx_count (free-running)
--
-- Reset is active-high (Avalon reset sink). Read latency = 1
-- (readdata is registered).
--
-- Standalone bring-up: the top level loops coe_send_* back into
-- coe_recv_*, so a TX write returns on RX. For HMPSoC integration
-- the conduit instead connects to a TDMA-MIN NoC port.
-- ============================================================

ENTITY noc_avalon_bridge IS
    PORT
    (
        clk           : IN  STD_LOGIC;
        reset         : IN  STD_LOGIC;

        -- Avalon-MM slave (32-bit, word addressed, read latency 1)
        avs_address   : IN  STD_LOGIC_VECTOR(1 DOWNTO 0);
        avs_read      : IN  STD_LOGIC;
        avs_write     : IN  STD_LOGIC;
        avs_writedata : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        avs_readdata  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Conduit to a TDMA-MIN NoC port (tdma_min_port, flattened)
        coe_send_data : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        coe_send_addr : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        coe_recv_data : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        coe_recv_addr : IN  STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ENTITY noc_avalon_bridge;

ARCHITECTURE rtl OF noc_avalon_bridge IS

    CONSTANT REG_TX     : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    CONSTANT REG_RX     : STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";
    CONSTANT REG_STATUS : STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";

    SIGNAL send_data_r  : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL send_addr_r  : STD_LOGIC_VECTOR(7 DOWNTO 0)  := (OTHERS => '0');
    SIGNAL send_valid_r : STD_LOGIC                     := '0';

    SIGNAL rx_data_r    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL rx_valid_r   : STD_LOGIC                     := '0';
    SIGNAL rx_count_r   : UNSIGNED(7 DOWNTO 0)          := (OTHERS => '0');

BEGIN

    -- One-shot send: data/addr valid only on the trigger cycle.
    coe_send_data <= send_data_r WHEN send_valid_r = '1' ELSE (OTHERS => '0');
    coe_send_addr <= send_addr_r WHEN send_valid_r = '1' ELSE (OTHERS => '0');

    PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                send_data_r  <= (OTHERS => '0');
                send_addr_r  <= (OTHERS => '0');
                send_valid_r <= '0';
                rx_data_r    <= (OTHERS => '0');
                rx_valid_r   <= '0';
                rx_count_r   <= (OTHERS => '0');
                avs_readdata <= (OTHERS => '0');
            ELSE
                -- Default: drop the one-shot after a single cycle.
                send_valid_r <= '0';

                -- TX write -> latch packet and fire the one-shot.
                IF avs_write = '1' AND avs_address = REG_TX THEN
                    send_data_r  <= avs_writedata;
                    send_addr_r  <= "0000" & avs_writedata(27 DOWNTO 24);
                    send_valid_r <= '1';
                END IF;

                -- RX latch: capture any valid incoming packet.
                IF coe_recv_data(31) = '1' THEN
                    rx_data_r  <= coe_recv_data;
                    rx_valid_r <= '1';
                    rx_count_r <= rx_count_r + 1;
                END IF;

                -- Avalon read (registered, read latency 1).
                IF avs_read = '1' THEN
                    CASE avs_address IS
                        WHEN REG_RX =>
                            avs_readdata <= rx_data_r;
                            rx_valid_r   <= '0'; -- reading RX clears the flag
                        WHEN REG_STATUS =>
                            avs_readdata <= x"0000" &
                                            STD_LOGIC_VECTOR(rx_count_r) &
                                            "0000000" & rx_valid_r;
                        WHEN OTHERS =>
                            avs_readdata <= (OTHERS => '0');
                    END CASE;
                END IF;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;
