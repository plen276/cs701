LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- ============================================================
-- ReCOP <-> TDMA-MIN Network Interface
--
-- Adapter between the ReCOP processor and a TdmaMinInterface.
-- Per gp-2/docs/interface-spec.md (Option A baseline, post-D10):
--
--   SEND (ReCOP -> NoC)
--     - One-shot pulse driven by `dpcr_load`.
--     - We register `dpcr_load` for one cycle so we sample the
--       freshly-written DPCR (the datapath registers DPCR on the
--       same rising edge that asserts dpcr_load — the new value
--       only appears on the NEXT cycle).
--     - During the send cycle:
--         send.data <= dpcr                   -- full packet
--         send.addr <= "0000" & dpcr(27..24)  -- dest from packet
--       The TdmaMinInterface FIFO uses send.data(31) as its
--       enqueue request; our packet types all encode 1xxx in
--       bits 31:28, so a valid packet self-triggers the FIFO.
--     - On non-send cycles, send.data is driven to zero so bit 31
--       is low and the FIFO does not re-enqueue.
--
--   RECEIVE (NoC -> ReCOP)
--     - TdmaMinInterface drives recv.data every cycle (free-running
--       sync register on `pull`). Valid packets have bit 31 = 1.
--     - We latch recv.data(15:0) into `sip_out` whenever
--       recv.data(31) = '1' and hold it. ReCOP polls SIP via LSIP
--       and detects a new packet by value change.
--     - No ER / receive-ready flag is implemented in this baseline
--       (per D10: deferred). Spike-level only — revisit if/when
--       polling becomes inadequate.
-- ============================================================

ENTITY recop_ni IS
    PORT
    (
        clock     : IN  STD_LOGIC;
        reset     : IN  STD_LOGIC;

        -- ReCOP-facing
        dpcr_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        dpcr_load : IN  STD_LOGIC;
        sip_out   : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);

        -- NoC-facing (connects to TdmaMinInterface)
        send      : OUT tdma_min_port;
        recv      : IN  tdma_min_port
    );
END ENTITY recop_ni;

ARCHITECTURE rtl OF recop_ni IS

    SIGNAL dpcr_load_prev : STD_LOGIC := '0';
    SIGNAL sip_reg     : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

BEGIN

    -- One-cycle delay on dpcr_load so we sample DPCR after it's
    -- been updated by the datapath.
    send_pulse : PROCESS (clock)
    BEGIN
        IF rising_edge(clock) THEN
            IF reset = '1' THEN
                dpcr_load_prev <= '0';
            ELSE
                dpcr_load_prev <= dpcr_load;
            END IF;
        END IF;
    END PROCESS send_pulse;

    -- Send path: assert for exactly one cycle after dpcr_load
    send.data <= dpcr_in                            WHEN dpcr_load_prev = '1' ELSE (OTHERS => '0');
    send.addr <= "0000" & dpcr_in(27 DOWNTO 24)    WHEN dpcr_load_prev = '1' ELSE (OTHERS => '0');

    -- Receive path: latch the lower 16 bits of any incoming valid packet.
    recv_latch : PROCESS (clock)
    BEGIN
        IF rising_edge(clock) THEN
            IF reset = '1' THEN
                sip_reg <= (OTHERS => '0');
            ELSIF recv.data(31) = '1' THEN
                sip_reg <= recv.data(15 DOWNTO 0);
            END IF;
        END IF;
    END PROCESS recv_latch;

    sip_out <= sip_reg;

END ARCHITECTURE rtl;
