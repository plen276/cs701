LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

-- ============================================================
-- Control Unit (FSM) for ReCOP GP1
--
-- Implements a multicycle fetch-execute processor.
-- States: IDLE → FETCH_1 → FETCH_2 → EXECUTE → FETCH_1 ...
-- Jump path: EXECUTE → FETCH_JUMP → FETCH_1
--
-- Two-process Moore FSM:
--   Process 1: clocked state register
--   Process 2: combinatorial output logic
-- ============================================================

ENTITY control_unit IS
    PORT (
        clk           : IN  bit_1;
        reset         : IN  bit_1;
		  debug_assert   : IN  bit_1;
		  debug_step    : IN  bit_1;

        -- From datapath
        opcode        : IN  bit_6;
        am            : IN  bit_2;
        z_flag        : IN  bit_1;

        -- To datapath: fetch control
        pc_load       : OUT bit_1;   -- load OPR into PC (jumps)
        ir_load       : OUT bit_1;   -- FETCH_1: latch PM word into IR[31:16]
        op_load       : OUT bit_1;   -- FETCH_2: latch PM word into IR[15:0] and OPR

        -- To datapath: ALU control
        alu_operation : OUT bit_3;
        alu_op1_sel   : OUT bit_2;
        alu_op2_sel   : OUT bit_1;
        clr_z_flag    : OUT bit_1;   -- CLFZ: clear zero flag

        -- To datapath: register file control
        rf_input_sel  : OUT bit_3;
        ld_r          : OUT bit_1;

        -- To datapath: data memory control
        dm_wren       : OUT bit_1
    );
END ENTITY control_unit;

ARCHITECTURE fsm OF control_unit IS

    TYPE state_type IS (ST_IDLE, ST_FETCH_1, ST_FETCH_2, ST_EXECUTE, ST_FETCH_JUMP);
    SIGNAL state : state_type;
	 SIGNAL debug_step_i : bit_1;

BEGIN
	
	 PROCESS(debug_step)
	 BEGIN
		  IF rising_edge(debug_step) THEN
				debug_step_i <= '1';
		  END IF;
	 END PROCESS;
	
    -- ===== Process 1: State Register =====
    state_reg : PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                state <= ST_IDLE;
            ELSIF debug_assert = '0' OR (debug_assert = '1' AND debug_step_i = '1') THEN
					 debug_step_i <= '0';
					 CASE state IS
						  WHEN ST_IDLE =>
								state <= ST_FETCH_1;

						  WHEN ST_FETCH_1 =>
								state <= ST_FETCH_2;

						  WHEN ST_FETCH_2 =>
								state <= ST_EXECUTE;

						  WHEN ST_EXECUTE =>
								-- Jump instructions redirect to FETCH_JUMP to overwrite PC
								IF opcode = jmp THEN
									 state <= ST_FETCH_JUMP;
								ELSIF opcode = sz AND z_flag = '1' THEN
									 state <= ST_FETCH_JUMP;
								-- TODO: PRESENT (jump if Rz=0) needs rz_zero signal from datapath
								ELSE
									 state <= ST_FETCH_1;
								END IF;

						  WHEN ST_FETCH_JUMP =>
								state <= ST_FETCH_1;

					 END CASE;
				END IF;
        END IF;
    END PROCESS state_reg;

    -- ===== Process 2: Output Logic =====
    output_logic : PROCESS(state, opcode, am, z_flag)
    BEGIN
        -- Safe defaults: no writes, no loads, ALU idle
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

            WHEN ST_IDLE =>
                NULL;  -- hold reset, all defaults

            WHEN ST_FETCH_1 =>
                ir_load <= '1';  -- latch PM output into IR[31:16], PC advances in datapath

            WHEN ST_FETCH_2 =>
                op_load <= '1';  -- latch PM output into IR[15:0] and OPR, PC advances

            WHEN ST_EXECUTE =>
                CASE opcode IS

                    -- --------------------------------------------------
                    -- LDR: load register
                    -- --------------------------------------------------
                    WHEN ldr =>
                        CASE am IS
                            WHEN am_immediate =>        -- LDR Rz #Op : Rz ← OPR
                                rf_input_sel <= "000";
                                ld_r         <= '1';
                            WHEN am_direct =>           -- LDR Rz $Op : Rz ← DM[OPR]
                                rf_input_sel <= "111";
                                ld_r         <= '1';
                            WHEN am_register =>         -- LDR Rz Rx  : Rz ← DM[Rx]
                                -- TODO: DM address must come from Rx, not OPR.
                                -- Requires dm_addr_sel mux in datapath.
                                rf_input_sel <= "111";
                                ld_r         <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- --------------------------------------------------
                    -- STR: store register
                    -- --------------------------------------------------
                    WHEN str =>
                        CASE am IS
                            WHEN am_direct =>           -- STR Rx $Op : DM[OPR] ← Rx
                                dm_wren <= '1';
                            WHEN am_immediate =>        -- STR Rz #Op : DM[Rz] ← Op
                                -- TODO: DM address must come from Rz, data from OPR.
                                -- Requires additional muxes in datapath.
                                dm_wren <= '1';
                            WHEN am_register =>         -- STR Rz Rx  : DM[Rz] ← Rx
                                -- TODO: DM address must come from Rz, not OPR.
                                dm_wren <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- --------------------------------------------------
                    -- ADD: addition
                    -- --------------------------------------------------
                    WHEN addr =>
                        CASE am IS
                            WHEN am_immediate =>        -- ADD Rz Rx #Op : Rz ← Rx + OPR
                                alu_op1_sel   <= "01";  -- operand_1 = OPR
                                alu_op2_sel   <= '0';   -- operand_2 = Rx
                                alu_operation <= alu_add;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>         -- ADD Rz Rz Rx : Rz ← Rz + Rx
                                alu_op1_sel   <= "00";  -- operand_1 = Rx
                                alu_op2_sel   <= '1';   -- operand_2 = Rz
                                alu_operation <= alu_add;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- --------------------------------------------------
                    -- SUBV: subtraction, stores result
                    -- --------------------------------------------------
                    WHEN subvr =>
                        CASE am IS
                            WHEN am_immediate =>        -- SUBV Rz Rx #Op : Rz ← Rx - OPR
                                alu_op1_sel   <= "01";  -- operand_1 = OPR
                                alu_op2_sel   <= '0';   -- operand_2 = Rx
                                alu_operation <= alu_sub;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- --------------------------------------------------
                    -- SUB: subtraction, Z flag only (no register write)
                    -- --------------------------------------------------
                    WHEN subr =>                        -- SUB Rz #Op : Z ← (Rz - OPR = 0)
                        alu_op1_sel   <= "01";          -- operand_1 = OPR
                        alu_op2_sel   <= '1';           -- operand_2 = Rz
                        alu_operation <= alu_sub;
                        ld_r          <= '0';           -- result discarded, Z flag updates

                    -- --------------------------------------------------
                    -- AND: bitwise AND
                    -- --------------------------------------------------
                    WHEN andr =>
                        CASE am IS
                            WHEN am_immediate =>        -- AND Rz Rx #Op : Rz ← Rx AND OPR
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_and;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>         -- AND Rz Rz Rx : Rz ← Rz AND Rx
                                alu_op1_sel   <= "00";
                                alu_op2_sel   <= '1';
                                alu_operation <= alu_and;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- --------------------------------------------------
                    -- OR: bitwise OR
                    -- --------------------------------------------------
                    WHEN orr =>
                        CASE am IS
                            WHEN am_immediate =>        -- OR Rz Rx #Op : Rz ← Rx OR OPR
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_or;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>         -- OR Rz Rz Rx : Rz ← Rz OR Rx
                                alu_op1_sel   <= "00";
                                alu_op2_sel   <= '1';
                                alu_operation <= alu_or;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                    -- --------------------------------------------------
                    -- MAX: maximum of Rz and OPR
                    -- --------------------------------------------------
                    WHEN max =>                         -- MAX Rz #Op : Rz ← MAX(Rz, OPR)
                        rf_input_sel <= "100";          -- rz_max output from regfile
                        ld_r         <= '1';
                        -- Note: MAX unit in regfile compares Rz against ir_operand (OPR)

                    -- --------------------------------------------------
                    -- JMP: unconditional jump
                    -- --------------------------------------------------
                    WHEN jmp =>
                        -- am_immediate (#Op): PC ← OPR  (handled in FETCH_JUMP)
                        -- am_register  (Rx) : PC ← Rx   TODO: needs pc_src mux in datapath
                        NULL;   -- state machine transitions to ST_FETCH_JUMP

                    -- --------------------------------------------------
                    -- SZ: skip (jump) if zero
                    -- --------------------------------------------------
                    WHEN sz =>
                        NULL;   -- state machine handles branch; PC ← OPR in FETCH_JUMP

                    -- --------------------------------------------------
                    -- CLFZ: clear zero flag
                    -- --------------------------------------------------
                    WHEN clfz =>
                        clr_z_flag <= '1';

                    -- --------------------------------------------------
                    -- NOOP: no operation
                    -- --------------------------------------------------
                    WHEN noop =>
                        NULL;

                    -- --------------------------------------------------
                    -- TODO: instructions requiring datapath extensions
                    -- --------------------------------------------------
                    -- PRESENT Rz Op  : if Rz=0 then PC←Op  — needs rz_zero from datapath
                    -- LER Rz         : Rz ← ER             — ER register not yet wired
                    -- LSIP Rz        : Rz ← SIP            — SIP port not yet wired
                    -- SSOP Rx        : SOP ← Rx            — SOP port not yet wired
                    -- SSVOP Rx       : SVOP ← Rx           — SVOP port not yet wired
                    -- SEOT           : EOT ← '1'           — EOT register not yet in datapath
                    -- CEOT           : EOT ← '0'           — EOT register not yet in datapath
                    -- CER            : ER ← '0'            — ER register not yet in datapath
                    -- STRPC $Op      : DM[Op] ← PC         — PC not accessible for DM write
                    -- DATACALL Rx    : DPCR ← Rx & R7      — DPCR not yet in datapath
                    -- DATACALL Rx #Op: DPCR ← Rx & Op      — DPCR not yet in datapath

                    WHEN OTHERS =>
                        NULL;  -- unimplemented: safe no-op

                END CASE;

            WHEN ST_FETCH_JUMP =>
                pc_load <= '1';  -- load OPR into PC (jump target)

        END CASE;
    END PROCESS output_logic;

END ARCHITECTURE fsm;
