LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

-- ============================================================
-- Control Unit (FSM) for ReCOP GP1  -- fixed timing version
--
-- States:
--   IDLE -> FETCH_1 -> WAIT_1 -> FETCH_2 -> WAIT_2 -> EXECUTE
--        -> FETCH_1 (next)
--        -> FETCH_JUMP -> WAIT_J -> FETCH_1 (jump taken)
--
-- WAIT_1/WAIT_2/WAIT_J exist to absorb the 1-cycle address-register
-- latency of the altsyncram prog_mem / data_mem blocks:
--   * WAIT_1 gives the PM's addr_reg one clock to catch up to pc+1
--     before FETCH_2 latches IR[15:0].
--   * WAIT_2 gives the DM's addr_reg one clock to catch up to the
--     freshly-loaded opr, so LDR $addr in EXECUTE sees dm_out=mem[opr].
--   * WAIT_J primes the PM's addr_reg with the new pc after a jump.
-- ============================================================

ENTITY control_unit IS
    PORT (
        clk           : IN  bit_1;
        reset         : IN  bit_1;

        opcode        : IN  bit_6;
        am            : IN  bit_2;
        z_flag        : IN  bit_1;

        pc_load       : OUT bit_1;
        ir_load       : OUT bit_1;
        op_load       : OUT bit_1;

        alu_operation : OUT bit_3;
        alu_op1_sel   : OUT bit_2;
        alu_op2_sel   : OUT bit_1;
        clr_z_flag    : OUT bit_1;

        rf_input_sel  : OUT bit_3;
        ld_r          : OUT bit_1;

        dm_wren       : OUT bit_1
    );
END ENTITY control_unit;

ARCHITECTURE fsm OF control_unit IS

    TYPE state_type IS (
        ST_IDLE,
        ST_FETCH_1,    -- pm_q=mem[pc], asserts ir_load
        ST_WAIT_1,     -- wait for pm addr_reg -> pc (now pc+1)
        ST_FETCH_2,    -- pm_q=mem[pc+1], asserts op_load
        ST_WAIT_2,     -- wait for dm addr_reg -> new opr
        ST_EXECUTE,    -- decode / ALU / DM access
        ST_FETCH_JUMP, -- pc_load = 1
        ST_WAIT_J      -- wait for pm addr_reg -> new pc
    );
    SIGNAL state : state_type;

BEGIN

    -- ========== State register ==========
    state_reg : PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                state <= ST_IDLE;
            ELSE
                CASE state IS
                    WHEN ST_IDLE =>
                        state <= ST_FETCH_1;

                    WHEN ST_FETCH_1 =>
                        state <= ST_WAIT_1;

                    WHEN ST_WAIT_1 =>
                        state <= ST_FETCH_2;

                    WHEN ST_FETCH_2 =>
                        state <= ST_WAIT_2;

                    WHEN ST_WAIT_2 =>
                        state <= ST_EXECUTE;

                    WHEN ST_EXECUTE =>
                        IF opcode = jmp THEN
                            state <= ST_FETCH_JUMP;
                        ELSIF opcode = sz AND z_flag = '1' THEN
                            state <= ST_FETCH_JUMP;
                        ELSE
                            state <= ST_FETCH_1;
                        END IF;

                    WHEN ST_FETCH_JUMP =>
                        state <= ST_WAIT_J;

                    WHEN ST_WAIT_J =>
                        state <= ST_FETCH_1;
                END CASE;
            END IF;
        END IF;
    END PROCESS state_reg;

    -- ========== Output logic (Moore) ==========
    output_logic : PROCESS(state, opcode, am, z_flag)
    BEGIN
        pc_load       <= '0';
        ir_load       <= '0';
        op_load       <= '0';
        alu_operation <= alu_idle;
        alu_op1_sel   <= "00";
        alu_op2_sel   <= '0';
        clr_z_flag    <= '0';
        rf_input_sel  <= "000";
        ld_r          <= '0';
        dm_wren       <= '0';

        CASE state IS

            WHEN ST_IDLE | ST_WAIT_1 | ST_WAIT_2 | ST_WAIT_J =>
                NULL;

            WHEN ST_FETCH_1 =>
                ir_load <= '1';

            WHEN ST_FETCH_2 =>
                op_load <= '1';

            WHEN ST_FETCH_JUMP =>
                pc_load <= '1';

            WHEN ST_EXECUTE =>
                CASE opcode IS

                    -- ------------------- LDR -------------------
                    WHEN ldr =>
                        CASE am IS
                            WHEN am_immediate =>        -- LDR Rz #Op
                                rf_input_sel <= "000";
                                ld_r         <= '1';
                            WHEN am_direct =>           -- LDR Rz $Op
                                rf_input_sel <= "111";
                                ld_r         <= '1';
                            WHEN am_register =>         -- (kept: treat as direct via Rx)
                                rf_input_sel <= "111";
                                ld_r         <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- ------------------- STR -------------------
                    WHEN str =>
                        CASE am IS
                            WHEN am_direct =>           -- STR Rx $Op
                                dm_wren <= '1';
                            WHEN am_immediate =>
                                dm_wren <= '1';
                            WHEN am_register =>
                                dm_wren <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- ------------------- ADD -------------------
                    WHEN addr =>
                        CASE am IS
                            WHEN am_immediate =>        -- ADD Rz Rx #Op
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_add;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>         -- ADD Rz Rz Rx
                                alu_op1_sel   <= "00";
                                alu_op2_sel   <= '1';
                                alu_operation <= alu_add;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- ------------------- SUBV ------------------
                    WHEN subvr =>
                        CASE am IS
                            WHEN am_immediate =>        -- SUBV Rz Rx #Op
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_sub;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>         -- SUBV Rz Rz Rx  (Rz <- Rz - Rx)
                                alu_op1_sel   <= "00";
                                alu_op2_sel   <= '1';
                                alu_operation <= alu_sub;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- ------------------- SUB -------------------
                    WHEN subr =>                        -- SUB Rz #Op : Z <- (Rz - OPR == 0)
                        alu_op1_sel   <= "01";
                        alu_op2_sel   <= '1';
                        alu_operation <= alu_sub;
                        ld_r          <= '0';

                    -- ------------------- AND -------------------
                    WHEN andr =>
                        CASE am IS
                            WHEN am_immediate =>        -- AND Rz Rx #Op
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_and;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>         -- AND Rz Rz Rx
                                alu_op1_sel   <= "00";
                                alu_op2_sel   <= '1';
                                alu_operation <= alu_and;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- ------------------- OR --------------------
                    WHEN orr =>
                        CASE am IS
                            WHEN am_immediate =>
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_or;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>
                                alu_op1_sel   <= "00";
                                alu_op2_sel   <= '1';
                                alu_operation <= alu_or;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- ------------------- MAX -------------------
                    WHEN max =>
                        rf_input_sel <= "100";
                        ld_r         <= '1';

                    -- ------------------- JMP / SZ --------------
                    WHEN jmp =>
                        NULL;
                    WHEN sz =>
                        NULL;

                    -- ------------------- CLFZ ------------------
                    WHEN clfz =>
                        clr_z_flag <= '1';

                    -- ------------------- NOOP ------------------
                    WHEN noop =>
                        NULL;

                    WHEN OTHERS =>
                        NULL;
                END CASE;

        END CASE;
    END PROCESS output_logic;

END ARCHITECTURE fsm;
