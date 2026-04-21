LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

-- ============================================================
-- Control Unit (FSM) for ReCOP GP1
--
-- Multicycle fetch-execute processor
-- States: IDLE => FETCH_1 => FETCH_2 => [WAIT_MEM =>] EXECUTE => FETCH_1 ...
-- Jump path: EXECUTE => FETCH_JUMP => FETCH_1
-- WAIT_MEM inserted for all LDR (direct/register) and all STR:
--  altsyncram address input is registered, so one extra cycle is required before
--  valid data appears on q
--
-- Two-process Moore FSM:
--   Process 1: clocked state register
--   Process 2: combinatorial output logic
-- ============================================================

ENTITY control_unit IS
    PORT
    (
        clk           : IN STD_LOGIC;
        reset         : IN STD_LOGIC;

        -- ==================================================
        -- From Datapath
        -- ==================================================
        am            : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
        opcode        : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
        z_flag        : IN STD_LOGIC;
        rz_zero       : IN STD_LOGIC;  -- '1' when Rz = x"0000" (PRESENT)

        -- ==================================================
        -- To Datapath
        -- ==================================================
        -- Fetch control
        pc_load       : OUT STD_LOGIC; -- load OPR into PC (jumps)
        ir_load       : OUT STD_LOGIC; -- FETCH_1: latch PM word into IR[31:16]
        op_load       : OUT STD_LOGIC; -- FETCH_2: latch PM word into IR[15:0] and OPR

        -- ALU control
        alu_operation : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        alu_op1_sel   : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        alu_op2_sel   : OUT STD_LOGIC;
        clr_z_flag    : OUT STD_LOGIC; -- CLFZ: clear zero flag

        -- Register file control
        rf_input_sel  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        ld_r          : OUT STD_LOGIC;

        -- Data memory control
        dm_wren       : OUT STD_LOGIC;

        -- Addressing mux selects
        pc_src_sel    : OUT STD_LOGIC;                    -- '0'=OPR (JMP #), '1'=Rx (JMP Rx)
        dm_addr_sel   : OUT STD_LOGIC_VECTOR(1 DOWNTO 0); -- "00"=OPR, "01"=Rz, "10"=Rx
        dm_data_sel   : OUT STD_LOGIC_VECTOR(1 DOWNTO 0); -- "00"=Rx, "01"=OPR, "10"=PC

        -- SOP / DPCR control
        ssop_load     : OUT STD_LOGIC;                    -- SSOP: latch Rx into SOP register
        dpcr_load     : OUT STD_LOGIC;                    -- DATACALL: latch into DPCR
        dpcr_data_sel : OUT STD_LOGIC                     -- '0'=R7 lower, '1'=OPR lower
    );
END ENTITY control_unit;

ARCHITECTURE fsm OF control_unit IS

    TYPE state_type IS (ST_IDLE, ST_FETCH_1, ST_FETCH_2, ST_WAIT_MEM, ST_EXECUTE, ST_FETCH_JUMP);
    SIGNAL state : state_type;

BEGIN

    -- ==================================================
    -- Process 1: State Register
    -- ==================================================
    state_reg : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                state <= ST_IDLE;
            ELSE
                CASE state IS
                    WHEN ST_IDLE =>
                        state <= ST_FETCH_1;

                    WHEN ST_FETCH_1 =>
                        state <= ST_FETCH_2;

                    WHEN ST_FETCH_2 =>
                        IF (opcode = ldr AND am /= am_immediate) OR opcode = str OR opcode = strpc THEN
                            state <= ST_WAIT_MEM;
                        ELSE
                            state <= ST_EXECUTE;
                        END IF;

                    WHEN ST_WAIT_MEM =>
                        state <= ST_EXECUTE;

                    WHEN ST_EXECUTE =>
                        -- Jump instructions redirect to FETCH_JUMP to overwrite PC
                        IF opcode = jmp OR (opcode = sz AND z_flag = '1') OR (opcode = present AND rz_zero = '1') THEN
                            state <= ST_FETCH_JUMP;
                        ELSE
                            state <= ST_FETCH_1;
                        END IF;

                    WHEN ST_FETCH_JUMP =>
                        state <= ST_FETCH_1;

                END CASE;
            END IF;
        END IF;
    END PROCESS state_reg;

    -- ==================================================
    -- Process 2: Output Logic
    -- ==================================================
    output_logic : PROCESS (state, am, opcode, z_flag, rz_zero)
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
        pc_src_sel    <= '0';
        dm_addr_sel   <= "00";
        dm_data_sel   <= "00";
        ssop_load     <= '0';
        dpcr_load     <= '0';
        dpcr_data_sel <= '0';

        CASE state IS

            WHEN ST_IDLE =>
                NULL; -- hold reset, all defaults

            WHEN ST_FETCH_1 =>
                ir_load <= '1'; -- latch PM output into IR[31:16], PC advances in datapath

            WHEN ST_FETCH_2 =>
                op_load <= '1'; -- latch PM output into IR[15:0] and operand, PC advances

            WHEN ST_WAIT_MEM =>
                IF opcode = ldr AND am = am_register THEN
                    dm_addr_sel <= "10"; -- register Rx address for read in EXECUTE
                END IF;

            WHEN ST_EXECUTE =>
                CASE opcode IS

                        -- --------------------------------------------------
                        -- LDR: load register
                        -- --------------------------------------------------
                    WHEN ldr =>
                        CASE am IS
                            WHEN am_immediate => -- LDR Rz #Op : Rz ← operand
                                rf_input_sel <= "000";
                                ld_r         <= '1';
                            WHEN am_direct => -- LDR Rz $Op : Rz ← DM[operand]
                                rf_input_sel <= "111";
                                ld_r         <= '1';
                            WHEN am_register => -- LDR Rz Rx  : Rz ← DM[Rx]
                                dm_addr_sel  <= "10";
                                rf_input_sel <= "111";
                                ld_r         <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                        -- --------------------------------------------------
                        -- STR: store register
                        -- --------------------------------------------------
                    WHEN str =>
                        CASE am IS
                            WHEN am_direct => -- STR Rx $Op : DM[OPR] ← Rx
                                dm_wren <= '1';
                            WHEN am_immediate => -- STR Rz #Op : DM[Rz] ← Op
                                dm_addr_sel <= "01";
                                dm_data_sel <= "01";
                                dm_wren     <= '1';
                            WHEN am_register => -- STR Rz Rx  : DM[Rz] ← Rx
                                dm_addr_sel <= "01";
                                dm_wren     <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                        -- --------------------------------------------------
                        -- ADD: addition
                        -- --------------------------------------------------
                    WHEN addr =>
                        CASE am IS
                            WHEN am_immediate =>   -- ADD Rz Rx #Op : Rz ← Rx + OPR
                                alu_op1_sel   <= "01"; -- operand_1 = OPR
                                alu_op2_sel   <= '0';  -- operand_2 = Rx
                                alu_operation <= alu_add;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register =>    -- ADD Rz Rz Rx : Rz ← Rz + Rx
                                alu_op1_sel   <= "00"; -- operand_1 = Rx
                                alu_op2_sel   <= '1';  -- operand_2 = Rz
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
                            WHEN am_immediate =>   -- SUBV Rz Rx #Op : Rz ← Rx - OPR
                                alu_op1_sel   <= "01"; -- operand_1 = OPR
                                alu_op2_sel   <= '0';  -- operand_2 = Rx
                                alu_operation <= alu_sub;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN OTHERS => NULL;
                        END CASE;

                        -- --------------------------------------------------
                        -- SUB: subtraction, Z flag only (no register write)
                        -- --------------------------------------------------
                    WHEN subr =>           -- SUB Rz #Op : Z ← (Rz - OPR = 0)
                        alu_op1_sel   <= "01"; -- operand_1 = OPR
                        alu_op2_sel   <= '1';  -- operand_2 = Rz
                        alu_operation <= alu_sub;
                        ld_r          <= '0'; -- result discarded, Z flag updates

                        -- --------------------------------------------------
                        -- AND: bitwise AND
                        -- --------------------------------------------------
                    WHEN andr =>
                        CASE am IS
                            WHEN am_immediate => -- AND Rz Rx #Op : Rz ← Rx AND OPR
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_and;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register => -- AND Rz Rz Rx : Rz ← Rz AND Rx
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
                            WHEN am_immediate => -- OR Rz Rx #Op : Rz ← Rx OR OPR
                                alu_op1_sel   <= "01";
                                alu_op2_sel   <= '0';
                                alu_operation <= alu_or;
                                rf_input_sel  <= "011";
                                ld_r          <= '1';
                            WHEN am_register => -- OR Rz Rz Rx : Rz ← Rz OR Rx
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
                    WHEN max =>            -- MAX Rz #Op : Rz ← MAX(Rz, OPR)
                        rf_input_sel <= "100"; -- rz_max output from regfile
                        ld_r         <= '1';
                        -- Note: MAX unit in regfile compares Rz against ir_operand (OPR)

                        -- --------------------------------------------------
                        -- JMP: unconditional jump
                        -- --------------------------------------------------
                    WHEN jmp =>
                        NULL; -- pc_src_sel driven in ST_FETCH_JUMP based on am

                        -- --------------------------------------------------
                        -- SZ: skip (jump) if zero
                        -- --------------------------------------------------
                    WHEN sz =>
                        NULL; -- state machine handles branch; PC ← OPR in FETCH_JUMP

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
                        -- PRESENT: conditional jump if Rz = 0
                        -- --------------------------------------------------
                    WHEN present => -- PRESENT Rz #Op : if Rz=0 then PC←Op
                        NULL;           -- state machine handles branch; pc_load in ST_FETCH_JUMP

                        -- --------------------------------------------------
                        -- LSIP: load from SIP port
                        -- --------------------------------------------------
                    WHEN lsip =>    -- LSIP Rz : Rz ← SIP
                        rf_input_sel <= "101";
                        ld_r         <= '1';

                        -- --------------------------------------------------
                        -- SSOP: store to SOP port
                        -- --------------------------------------------------
                    WHEN ssop => -- SSOP Rx : SOP ← Rx
                        ssop_load <= '1';

                        -- --------------------------------------------------
                        -- STRPC: store PC to memory
                        -- --------------------------------------------------
                    WHEN strpc => -- STRPC $Op : DM[OPR] ← PC
                        dm_data_sel <= "10";
                        dm_wren     <= '1';

                        -- --------------------------------------------------
                        -- DATACALL: load DPCR register
                        -- --------------------------------------------------
                    WHEN datacall => -- DATACALL Rx : DPCR ← Rx & R7
                        dpcr_load     <= '1';
                        dpcr_data_sel <= '0';

                    WHEN datacall2 => -- DATACALL Rx #Op : DPCR ← Rx & Op
                        dpcr_load     <= '1';
                        dpcr_data_sel <= '1';

                    WHEN OTHERS =>
                        NULL; -- unimplemented: safe no-op

                END CASE;

            WHEN ST_FETCH_JUMP =>
                pc_load <= '1';
                IF am = am_register THEN
                    pc_src_sel <= '1'; -- JMP Rx: PC <= Rx
                END IF;

        END CASE;
    END PROCESS output_logic;

END ARCHITECTURE fsm;
