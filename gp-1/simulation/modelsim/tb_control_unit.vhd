LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

-- ============================================================
-- Testbench: control_unit
--
-- Unit test for the ReCOP GP1 control unit FSM.
-- Drives opcode, am, z_flag, rz_zero directly (simulating IR decode
-- from the datapath) and verifies state transitions and output signals.
--
-- Tests (T1-T26):
--   T1-T2   : Fetch cycle: ir_load, op_load
--   T3-T5   : LDR immediate/direct/register (WAIT_MEM for direct/reg)
--   T6-T8   : STR direct/immediate/register (all via WAIT_MEM)
--   T9-T13  : ALU instructions: ADD, SUB, AND, OR
--   T14-T15 : MAX, CLFZ
--   T16-T17 : JMP # and JMP Rx (pc_src_sel)
--   T18-T19 : SZ not taken / taken
--   T20-T21 : PRESENT not taken / taken (rz_zero)
--   T22-T23 : LSIP, SSOP
--   T24     : STRPC (WAIT_MEM, dm_data_sel=PC)
--   T25-T26 : DATACALL register / immediate (dpcr_load, dpcr_data_sel)
-- ============================================================

ENTITY tb_control_unit IS
END ENTITY tb_control_unit;

ARCHITECTURE sim OF tb_control_unit IS

    CONSTANT CLK_PERIOD  : TIME                         := 20 ns;

    -- DUT inputs
    SIGNAL clk           : STD_LOGIC                    := '0';
    SIGNAL reset         : STD_LOGIC                    := '1';
    SIGNAL opcode        : STD_LOGIC_VECTOR(5 DOWNTO 0) := (OTHERS => '0');
    SIGNAL am            : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    SIGNAL z_flag        : STD_LOGIC                    := '0';
    SIGNAL rz_zero       : STD_LOGIC                    := '0';

    -- DUT outputs
    SIGNAL pc_load       : STD_LOGIC;
    SIGNAL ir_load       : STD_LOGIC;
    SIGNAL op_load       : STD_LOGIC;
    SIGNAL alu_operation : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL alu_op1_sel   : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL alu_op2_sel   : STD_LOGIC;
    SIGNAL clr_z_flag    : STD_LOGIC;
    SIGNAL rf_input_sel  : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL ld_r          : STD_LOGIC;
    SIGNAL dm_wren       : STD_LOGIC;
    SIGNAL pc_src_sel    : STD_LOGIC;
    SIGNAL dm_addr_sel   : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL dm_data_sel   : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL ssop_load     : STD_LOGIC;
    SIGNAL dpcr_load     : STD_LOGIC;
    SIGNAL dpcr_data_sel : STD_LOGIC;

    COMPONENT control_unit IS
        PORT
        (
            clk           : IN STD_LOGIC;
            reset         : IN STD_LOGIC;
            am            : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            opcode        : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
            z_flag        : IN STD_LOGIC;
            rz_zero       : IN STD_LOGIC;
            pc_load       : OUT STD_LOGIC;
            ir_load       : OUT STD_LOGIC;
            op_load       : OUT STD_LOGIC;
            alu_operation : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            alu_op1_sel   : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            alu_op2_sel   : OUT STD_LOGIC;
            clr_z_flag    : OUT STD_LOGIC;
            rf_input_sel  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            ld_r          : OUT STD_LOGIC;
            dm_wren       : OUT STD_LOGIC;
            pc_src_sel    : OUT STD_LOGIC;
            dm_addr_sel   : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            dm_data_sel   : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            ssop_load     : OUT STD_LOGIC;
            dpcr_load     : OUT STD_LOGIC;
            dpcr_data_sel : OUT STD_LOGIC
        );
    END COMPONENT;

    PROCEDURE tick IS
    BEGIN
        WAIT UNTIL rising_edge(clk);
        WAIT FOR 1 ns;
    END PROCEDURE;

BEGIN

    clk <= NOT clk AFTER CLK_PERIOD / 2;

    DUT : control_unit PORT MAP
    (
        clk           => clk,
        reset         => reset,
        am            => am,
        opcode        => opcode,
        z_flag        => z_flag,
        rz_zero       => rz_zero,
        pc_load       => pc_load,
        ir_load       => ir_load,
        op_load       => op_load,
        alu_operation => alu_operation,
        alu_op1_sel   => alu_op1_sel,
        alu_op2_sel   => alu_op2_sel,
        clr_z_flag    => clr_z_flag,
        rf_input_sel  => rf_input_sel,
        ld_r          => ld_r,
        dm_wren       => dm_wren,
        pc_src_sel    => pc_src_sel,
        dm_addr_sel   => dm_addr_sel,
        dm_data_sel   => dm_data_sel,
        ssop_load     => ssop_load,
        dpcr_load     => dpcr_load,
        dpcr_data_sel => dpcr_data_sel
    );

    stim : PROCESS
    BEGIN

        -- ------------------------------------------------
        -- Reset
        -- ------------------------------------------------
        reset <= '1';
        tick;
        tick;
        reset <= '0';

        -- ================================================
        -- T1: IDLE -> FETCH_1
        -- Expect: ir_load='1', all others '0'
        -- ================================================
        tick;
        ASSERT ir_load = '1' REPORT "FAIL T1: ir_load should be 1 in FETCH_1" SEVERITY ERROR;
        ASSERT op_load = '0' REPORT "FAIL T1: op_load should be 0 in FETCH_1" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T1: ld_r should be 0 in FETCH_1" SEVERITY ERROR;

        -- ================================================
        -- T2: FETCH_1 -> FETCH_2
        -- Expect: op_load='1', ir_load='0'
        -- ================================================
        tick;
        ASSERT op_load = '1' REPORT "FAIL T2: op_load should be 1 in FETCH_2" SEVERITY ERROR;
        ASSERT ir_load = '0' REPORT "FAIL T2: ir_load should be 0 in FETCH_2" SEVERITY ERROR;

        -- ================================================
        -- T3: LDR Rz #value (immediate) - FETCH_2 -> EXECUTE
        -- No WAIT_MEM for immediate addressing.
        -- Expect: rf_input_sel="000", ld_r='1', dm_wren='0'
        -- ================================================
        opcode <= ldr;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT ld_r = '1' REPORT "FAIL T3: ld_r should be 1 for LDR #" SEVERITY ERROR;
        ASSERT rf_input_sel = "000" REPORT "FAIL T3: rf_input_sel should be 000 for LDR #" SEVERITY ERROR;
        ASSERT dm_wren = '0' REPORT "FAIL T3: dm_wren should be 0 for LDR #" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T4: LDR Rz $address (direct) - FETCH_2 -> WAIT_MEM -> EXECUTE
        -- WAIT_MEM: address (OPR) registered by altsyncram.
        -- EXECUTE: rf_input_sel="111", ld_r='1'
        -- ================================================
        opcode <= ldr;
        am     <= am_direct;
        tick; -- WAIT_MEM
        ASSERT ld_r = '0' REPORT "FAIL T4: ld_r should be 0 in WAIT_MEM for LDR $" SEVERITY ERROR;
        ASSERT dm_wren = '0' REPORT "FAIL T4: dm_wren should be 0 in WAIT_MEM for LDR $" SEVERITY ERROR;
        tick; -- EXECUTE
        ASSERT ld_r = '1' REPORT "FAIL T4: ld_r should be 1 for LDR $" SEVERITY ERROR;
        ASSERT rf_input_sel = "111" REPORT "FAIL T4: rf_input_sel should be 111 for LDR $" SEVERITY ERROR;
        ASSERT dm_addr_sel = "00" REPORT "FAIL T4: dm_addr_sel should be 00 (OPR) for LDR $" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T5: LDR Rz Rx (register) - FETCH_2 -> WAIT_MEM -> EXECUTE
        -- WAIT_MEM: dm_addr_sel="10" so Rx address gets registered.
        -- EXECUTE: rf_input_sel="111", ld_r='1'
        -- ================================================
        opcode <= ldr;
        am     <= am_register;
        tick; -- WAIT_MEM
        ASSERT dm_addr_sel = "10" REPORT "FAIL T5: dm_addr_sel should be 10 in WAIT_MEM for LDR Rx" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T5: ld_r should be 0 in WAIT_MEM" SEVERITY ERROR;
        tick; -- EXECUTE
        ASSERT ld_r = '1' REPORT "FAIL T5: ld_r should be 1 for LDR Rx" SEVERITY ERROR;
        ASSERT rf_input_sel = "111" REPORT "FAIL T5: rf_input_sel should be 111 for LDR Rx" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T6: STR Rx $address (direct) - FETCH_2 -> WAIT_MEM -> EXECUTE
        -- EXECUTE: dm_wren='1', dm_addr_sel="00" (OPR, default)
        -- ================================================
        opcode <= str;
        am     <= am_direct;
        tick; -- WAIT_MEM
        ASSERT dm_wren = '0' REPORT "FAIL T6: dm_wren should be 0 in WAIT_MEM for STR $" SEVERITY ERROR;
        tick; -- EXECUTE
        ASSERT dm_wren = '1' REPORT "FAIL T6: dm_wren should be 1 for STR $" SEVERITY ERROR;
        ASSERT dm_addr_sel = "00" REPORT "FAIL T6: dm_addr_sel should be 00 (OPR) for STR $" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T6: ld_r should be 0 for STR $" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T7: STR Rz #value (immediate) - FETCH_2 -> WAIT_MEM -> EXECUTE
        -- EXECUTE: dm_wren='1', dm_addr_sel="01" (Rz), dm_data_sel="01" (OPR)
        -- ================================================
        opcode <= str;
        am     <= am_immediate;
        tick; -- WAIT_MEM
        tick; -- EXECUTE
        ASSERT dm_wren = '1' REPORT "FAIL T7: dm_wren should be 1 for STR #" SEVERITY ERROR;
        ASSERT dm_addr_sel = "01" REPORT "FAIL T7: dm_addr_sel should be 01 (Rz) for STR #" SEVERITY ERROR;
        ASSERT dm_data_sel = "01" REPORT "FAIL T7: dm_data_sel should be 01 (OPR) for STR #" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T8: STR Rz Rx (register) - FETCH_2 -> WAIT_MEM -> EXECUTE
        -- EXECUTE: dm_wren='1', dm_addr_sel="01" (Rz), data from Rx (default "00")
        -- ================================================
        opcode <= str;
        am     <= am_register;
        tick; -- WAIT_MEM
        tick; -- EXECUTE
        ASSERT dm_wren = '1' REPORT "FAIL T8: dm_wren should be 1 for STR Rx" SEVERITY ERROR;
        ASSERT dm_addr_sel = "01" REPORT "FAIL T8: dm_addr_sel should be 01 (Rz) for STR Rx" SEVERITY ERROR;
        ASSERT dm_data_sel = "00" REPORT "FAIL T8: dm_data_sel should be 00 (Rx) for STR Rx" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T8: ld_r should be 0 for STR Rx" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T9: ADD Rz Rx #value (immediate)
        -- Expect: alu_add, op1=OPR, op2=Rx, ld_r='1'
        -- ================================================
        opcode <= addr;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT alu_operation = alu_add REPORT "FAIL T9: alu_operation should be alu_add for ADD #" SEVERITY ERROR;
        ASSERT alu_op1_sel = "01" REPORT "FAIL T9: alu_op1_sel should be 01 (OPR) for ADD #" SEVERITY ERROR;
        ASSERT alu_op2_sel = '0' REPORT "FAIL T9: alu_op2_sel should be 0 (Rx) for ADD #" SEVERITY ERROR;
        ASSERT rf_input_sel = "011" REPORT "FAIL T9: rf_input_sel should be 011 for ADD #" SEVERITY ERROR;
        ASSERT ld_r = '1' REPORT "FAIL T9: ld_r should be 1 for ADD #" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T10: ADD Rz Rz Rx (register)
        -- Expect: alu_add, op1=Rx, op2=Rz
        -- ================================================
        opcode <= addr;
        am     <= am_register;
        tick; -- EXECUTE
        ASSERT alu_operation = alu_add REPORT "FAIL T10: alu_operation should be alu_add for ADD Rx" SEVERITY ERROR;
        ASSERT alu_op1_sel = "00" REPORT "FAIL T10: alu_op1_sel should be 00 (Rx) for ADD Rx" SEVERITY ERROR;
        ASSERT alu_op2_sel = '1' REPORT "FAIL T10: alu_op2_sel should be 1 (Rz) for ADD Rx" SEVERITY ERROR;
        ASSERT ld_r = '1' REPORT "FAIL T10: ld_r should be 1 for ADD Rx" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T11: SUB Rz #value - Z flag only, result discarded
        -- Expect: alu_sub, alu_op2_sel='1' (Rz), ld_r='0'
        -- ================================================
        opcode <= subr;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT alu_operation = alu_sub REPORT "FAIL T11: alu_operation should be alu_sub for SUB" SEVERITY ERROR;
        ASSERT alu_op1_sel = "01" REPORT "FAIL T11: alu_op1_sel should be 01 (OPR) for SUB" SEVERITY ERROR;
        ASSERT alu_op2_sel = '1' REPORT "FAIL T11: alu_op2_sel should be 1 (Rz) for SUB" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T11: ld_r should be 0 for SUB (Z flag only)" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T12: AND Rz Rx #value (immediate)
        -- ================================================
        opcode <= andr;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT alu_operation = alu_and REPORT "FAIL T12: alu_operation should be alu_and for AND #" SEVERITY ERROR;
        ASSERT alu_op1_sel = "01" REPORT "FAIL T12: alu_op1_sel should be 01 for AND #" SEVERITY ERROR;
        ASSERT alu_op2_sel = '0' REPORT "FAIL T12: alu_op2_sel should be 0 for AND #" SEVERITY ERROR;
        ASSERT ld_r = '1' REPORT "FAIL T12: ld_r should be 1 for AND #" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T13: OR Rz Rz Rx (register)
        -- ================================================
        opcode <= orr;
        am     <= am_register;
        tick; -- EXECUTE
        ASSERT alu_operation = alu_or REPORT "FAIL T13: alu_operation should be alu_or for OR Rx" SEVERITY ERROR;
        ASSERT alu_op1_sel = "00" REPORT "FAIL T13: alu_op1_sel should be 00 (Rx) for OR Rx" SEVERITY ERROR;
        ASSERT alu_op2_sel = '1' REPORT "FAIL T13: alu_op2_sel should be 1 (Rz) for OR Rx" SEVERITY ERROR;
        ASSERT ld_r = '1' REPORT "FAIL T13: ld_r should be 1 for OR Rx" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T14: MAX Rz #value
        -- Expect: rf_input_sel="100" (rz_max), ld_r='1'
        -- ================================================
        opcode <= max;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT rf_input_sel = "100" REPORT "FAIL T14: rf_input_sel should be 100 for MAX" SEVERITY ERROR;
        ASSERT ld_r = '1' REPORT "FAIL T14: ld_r should be 1 for MAX" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T15: CLFZ
        -- Expect: clr_z_flag='1', all writes off
        -- ================================================
        opcode <= clfz;
        am     <= am_inherent;
        tick; -- EXECUTE
        ASSERT clr_z_flag = '1' REPORT "FAIL T15: clr_z_flag should be 1 for CLFZ" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T15: ld_r should be 0 for CLFZ" SEVERITY ERROR;
        ASSERT dm_wren = '0' REPORT "FAIL T15: dm_wren should be 0 for CLFZ" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T16: JMP #value (immediate)
        -- EXECUTE: no pc_load (fires in FETCH_JUMP)
        -- FETCH_JUMP: pc_load='1', pc_src_sel='0' (OPR)
        -- ================================================
        opcode <= jmp;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT pc_load = '0' REPORT "FAIL T16: pc_load should be 0 in EXECUTE for JMP" SEVERITY ERROR;
        tick; -- FETCH_JUMP
        ASSERT pc_load = '1' REPORT "FAIL T16: pc_load should be 1 in FETCH_JUMP" SEVERITY ERROR;
        ASSERT pc_src_sel = '0' REPORT "FAIL T16: pc_src_sel should be 0 for JMP # (OPR)" SEVERITY ERROR;
        tick; -- FETCH_1
        ASSERT ir_load = '1' REPORT "FAIL T16: ir_load should be 1 after FETCH_JUMP" SEVERITY ERROR;
        tick; -- FETCH_2

        -- ================================================
        -- T17: JMP Rx (register)
        -- FETCH_JUMP: pc_load='1', pc_src_sel='1' (Rx)
        -- ================================================
        opcode <= jmp;
        am     <= am_register;
        tick; -- EXECUTE
        tick; -- FETCH_JUMP
        ASSERT pc_load = '1' REPORT "FAIL T17: pc_load should be 1 in FETCH_JUMP for JMP Rx" SEVERITY ERROR;
        ASSERT pc_src_sel = '1' REPORT "FAIL T17: pc_src_sel should be 1 for JMP Rx" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T18: SZ - not taken (z_flag='0')
        -- EXECUTE -> FETCH_1 (not FETCH_JUMP)
        -- ================================================
        opcode <= sz;
        am     <= am_immediate;
        z_flag <= '0';
        tick; -- EXECUTE
        tick; -- should be FETCH_1
        ASSERT ir_load = '1' REPORT "FAIL T18: SZ not taken - should go to FETCH_1" SEVERITY ERROR;
        ASSERT pc_load = '0' REPORT "FAIL T18: SZ not taken - pc_load should be 0" SEVERITY ERROR;
        tick; -- FETCH_2

        -- ================================================
        -- T19: SZ - taken (z_flag='1')
        -- EXECUTE -> FETCH_JUMP -> FETCH_1
        -- ================================================
        opcode <= sz;
        z_flag <= '1';
        tick; -- EXECUTE
        tick; -- FETCH_JUMP
        ASSERT pc_load = '1' REPORT "FAIL T19: SZ taken - pc_load should be 1 in FETCH_JUMP" SEVERITY ERROR;
        tick; -- FETCH_1
        ASSERT ir_load = '1' REPORT "FAIL T19: SZ taken - should return to FETCH_1" SEVERITY ERROR;
        z_flag <= '0';
        tick; -- FETCH_2

        -- ================================================
        -- T20: PRESENT - not taken (rz_zero='0')
        -- EXECUTE -> FETCH_1
        -- ================================================
        opcode  <= present;
        am      <= am_immediate;
        rz_zero <= '0';
        tick; -- EXECUTE
        tick; -- should be FETCH_1
        ASSERT ir_load = '1' REPORT "FAIL T20: PRESENT not taken - should go to FETCH_1" SEVERITY ERROR;
        ASSERT pc_load = '0' REPORT "FAIL T20: PRESENT not taken - pc_load should be 0" SEVERITY ERROR;
        tick; -- FETCH_2

        -- ================================================
        -- T21: PRESENT - taken (rz_zero='1')
        -- EXECUTE -> FETCH_JUMP -> FETCH_1
        -- ================================================
        opcode  <= present;
        rz_zero <= '1';
        tick; -- EXECUTE
        tick; -- FETCH_JUMP
        ASSERT pc_load = '1' REPORT "FAIL T21: PRESENT taken - pc_load should be 1" SEVERITY ERROR;
        tick; -- FETCH_1
        ASSERT ir_load = '1' REPORT "FAIL T21: PRESENT taken - should return to FETCH_1" SEVERITY ERROR;
        rz_zero <= '0';
        tick; -- FETCH_2

        -- ================================================
        -- T22: LSIP Rz
        -- Expect: rf_input_sel="101" (SIP), ld_r='1'
        -- ================================================
        opcode <= lsip;
        am     <= am_register;
        tick; -- EXECUTE
        ASSERT rf_input_sel = "101" REPORT "FAIL T22: rf_input_sel should be 101 for LSIP" SEVERITY ERROR;
        ASSERT ld_r = '1' REPORT "FAIL T22: ld_r should be 1 for LSIP" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T23: SSOP Rx
        -- Expect: ssop_load='1', ld_r='0'
        -- ================================================
        opcode <= ssop;
        am     <= am_register;
        tick; -- EXECUTE
        ASSERT ssop_load = '1' REPORT "FAIL T23: ssop_load should be 1 for SSOP" SEVERITY ERROR;
        ASSERT ld_r = '0' REPORT "FAIL T23: ld_r should be 0 for SSOP" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T24: STRPC $address - FETCH_2 -> WAIT_MEM -> EXECUTE
        -- EXECUTE: dm_data_sel="10" (PC), dm_wren='1', dm_addr_sel="00" (OPR)
        -- ================================================
        opcode <= strpc;
        am     <= am_direct;
        tick; -- WAIT_MEM
        ASSERT dm_wren = '0' REPORT "FAIL T24: dm_wren should be 0 in WAIT_MEM for STRPC" SEVERITY ERROR;
        tick; -- EXECUTE
        ASSERT dm_data_sel = "10" REPORT "FAIL T24: dm_data_sel should be 10 (PC) for STRPC" SEVERITY ERROR;
        ASSERT dm_wren = '1' REPORT "FAIL T24: dm_wren should be 1 for STRPC" SEVERITY ERROR;
        ASSERT dm_addr_sel = "00" REPORT "FAIL T24: dm_addr_sel should be 00 (OPR) for STRPC" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T25: DATACALL Rx (register) - DPCR <- Rx & R7
        -- Expect: dpcr_load='1', dpcr_data_sel='0'
        -- ================================================
        opcode <= datacall;
        am     <= am_register;
        tick; -- EXECUTE
        ASSERT dpcr_load = '1' REPORT "FAIL T25: dpcr_load should be 1 for DATACALL Rx" SEVERITY ERROR;
        ASSERT dpcr_data_sel = '0' REPORT "FAIL T25: dpcr_data_sel should be 0 for DATACALL Rx" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- T26: DATACALL Rx #value (immediate) - DPCR <- Rx & Op
        -- Expect: dpcr_load='1', dpcr_data_sel='1'
        -- ================================================
        opcode <= datacall2;
        am     <= am_immediate;
        tick; -- EXECUTE
        ASSERT dpcr_load = '1' REPORT "FAIL T26: dpcr_load should be 1 for DATACALL #" SEVERITY ERROR;
        ASSERT dpcr_data_sel = '1' REPORT "FAIL T26: dpcr_data_sel should be 1 for DATACALL #" SEVERITY ERROR;
        tick;
        tick; -- FETCH_1, FETCH_2

        -- ================================================
        -- Done
        -- ================================================
        REPORT "INFO: tb_control_unit complete - check waveforms for any FAIL messages"
            SEVERITY NOTE;
        WAIT;

    END PROCESS stim;

END ARCHITECTURE sim;
