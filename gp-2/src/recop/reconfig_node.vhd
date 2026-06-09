LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- reconfig_node  -- NoC-attached ReCOP program-memory reloader
--
-- Sits on NoC port 6. Receives Conf-Prog packets (type 1111)
-- and uses them to write 16-bit instruction words into the
-- dual-port program memory (prog_mem_dp port B).
--
-- Packet format (type 1111):
--   31:28  type    1111
--   27:24  dest    0110  (port 6)
--   23:20  sub-cmd
--   19:16  unused  0000
--   15:0   payload
--
-- Sub-commands:
--   0001  SET_ADDR   : latch payload[14:0] as the next write address
--   0010  WRITE_WORD : write payload[15:0] to the current address,
--                      then auto-increment the address
--
-- Typical reload sequence:
--   1. Assert system reset so ReCOP stops fetching.
--   2. Send SET_ADDR to position the write pointer.
--   3. Stream WRITE_WORD packets (one per 16-bit PM word).
--      Each consecutive WRITE_WORD advances the pointer by one.
--   4. Release reset; ReCOP boots from the new program.
--
-- The send port is permanently idle (bit 31 always low, so the
-- TDMA-MIN FIFO never enqueues from this node).
--
-- pm_wr_* outputs are registered: pm_wr_en is asserted on the
-- same clock edge that samples the WRITE_WORD packet and stays
-- high until the next rising edge (one clock cycle).  The
-- altsyncram port-B write therefore completes on that next edge.
-- ============================================================

ENTITY reconfig_node IS
    PORT
    (
        clock      : IN  STD_LOGIC;
        reset      : IN  STD_LOGIC;
        -- NoC ports
        send       : OUT tdma_min_port;
        recv       : IN  tdma_min_port;
        -- Program-memory write port (connects to prog_mem_dp port B)
        pm_wr_en   : OUT STD_LOGIC;
        pm_wr_addr : OUT STD_LOGIC_VECTOR(14 DOWNTO 0);
        pm_wr_data : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END ENTITY reconfig_node;

ARCHITECTURE rtl OF reconfig_node IS

    -- Next address to write; auto-increments after each WRITE_WORD.
    SIGNAL addr_reg     : UNSIGNED(14 DOWNTO 0)         := (OTHERS => '0');
    -- Registered write-port outputs (one cycle after packet decode).
    SIGNAL wr_en_reg    : STD_LOGIC                     := '0';
    SIGNAL wr_addr_reg  : STD_LOGIC_VECTOR(14 DOWNTO 0) := (OTHERS => '0');
    SIGNAL wr_data_reg  : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- Packet type / sub-command constants
    CONSTANT TYPE_CONF_PROG  : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    CONSTANT SUB_SET_ADDR    : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";
    CONSTANT SUB_WRITE_WORD  : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0010";

BEGIN

    -- The reconfig node never originates packets.
    send.data <= (OTHERS => '0');
    send.addr <= (OTHERS => '0');

    recv_proc : PROCESS (clock)
    BEGIN
        IF rising_edge(clock) THEN
            IF reset = '1' THEN
                addr_reg    <= (OTHERS => '0');
                wr_en_reg   <= '0';
                wr_addr_reg <= (OTHERS => '0');
                wr_data_reg <= (OTHERS => '0');
            ELSE
                wr_en_reg <= '0';   -- default: no write this cycle

                IF recv.data(31 DOWNTO 28) = TYPE_CONF_PROG THEN
                    CASE recv.data(23 DOWNTO 20) IS
                        WHEN SUB_SET_ADDR =>
                            addr_reg <= UNSIGNED(recv.data(14 DOWNTO 0));

                        WHEN SUB_WRITE_WORD =>
                            wr_en_reg   <= '1';
                            wr_addr_reg <= STD_LOGIC_VECTOR(addr_reg);
                            wr_data_reg <= recv.data(15 DOWNTO 0);
                            addr_reg    <= addr_reg + 1;

                        WHEN OTHERS => NULL;
                    END CASE;
                END IF;
            END IF;
        END IF;
    END PROCESS recv_proc;

    pm_wr_en   <= wr_en_reg;
    pm_wr_addr <= wr_addr_reg;
    pm_wr_data <= wr_data_reg;

END ARCHITECTURE rtl;
