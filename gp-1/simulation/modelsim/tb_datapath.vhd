LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.various_constants.ALL;

ENTITY tb_datapath IS
END ENTITY tb_datapath;

ARCHITECTURE sim OF tb_datapath IS

    CONSTANT CLK_PERIOD : TIME := 20 ns;

    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL reset : STD_LOGIC := '1';
    SIGNAL pm_data : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL pc_load : STD_LOGIC := '0';
    SIGNAL ir_load : STD_LOGIC := '0';
    SIGNAL op_load : STD_LOGIC := '0';
    SIGNAL pc_src_sel : STD_LOGIC := '0';
    SIGNAL alu_operation : STD_LOGIC_VECTOR(2 DOWNTO 0) := "100";
    SIGNAL alu_op1_sel : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    SIGNAL alu_op2_sel : STD_LOGIC := '0';
    SIGNAL clr_z_flag : STD_LOGIC := '0';
    SIGNAL rf_input_sel : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
    SIGNAL ld_r : STD_LOGIC := '0';
    SIGNAL dm_wren : STD_LOGIC := '0';
    SIGNAL dm_addr_sel : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    SIGNAL dm_data_sel : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    SIGNAL sip : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL ssop_load : STD_LOGIC := '0';
    SIGNAL sop : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr_load : STD_LOGIC := '0';
    SIGNAL dpcr_data_sel : STD_LOGIC := '0';
    SIGNAL dpcr : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL opcode : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL z_flag : STD_LOGIC;
    SIGNAL rz_zero : STD_LOGIC;
    SIGNAL rz_out : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rx_out : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL pc_out : STD_LOGIC_VECTOR(15 DOWNTO 0);

    COMPONENT datapath IS
        PORT (
            clk : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            pm_data : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            pc_load : IN STD_LOGIC;
            ir_load : IN STD_LOGIC;
            op_load : IN STD_LOGIC;
            pc_src_sel : IN STD_LOGIC;
            alu_operation : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            alu_op1_sel : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            alu_op2_sel : IN STD_LOGIC;
            clr_z_flag : IN STD_LOGIC;
            rf_input_sel : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            ld_r : IN STD_LOGIC;
            dm_wren : IN STD_LOGIC;
            dm_addr_sel : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            dm_data_sel : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            sip : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            ssop_load : IN STD_LOGIC;
            sop : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dpcr_load : IN STD_LOGIC;
            dpcr_data_sel : IN STD_LOGIC;
            dpcr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            opcode : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
            am : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            z_flag : OUT STD_LOGIC;
            rz_zero : OUT STD_LOGIC;
            rz_out : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rx_out : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            pc_out : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

    PROCEDURE tick IS
    BEGIN
        WAIT UNTIL rising_edge(clk);
        WAIT FOR 1 ns;
    END PROCEDURE;

    -- Drives fetch cycle: ir_load with upper half, op_load with lower half
    PROCEDURE do_fetch (
        upper : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        lower : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        SIGNAL pm_data : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        SIGNAL ir_load : OUT STD_LOGIC;
        SIGNAL op_load : OUT STD_LOGIC
    ) IS
    BEGIN
        pm_data <= upper;
        ir_load <= '1';
        tick;
        ir_load <= '0';
        pm_data <= lower;
        op_load <= '1';
        tick;
        op_load <= '0';
    END PROCEDURE;

BEGIN

    clk <= NOT clk AFTER CLK_PERIOD / 2;

    DUT : datapath PORT MAP(
        clk => clk,
        reset => reset,
        pm_data => pm_data,
        pc_load => pc_load,
        ir_load => ir_load,
        op_load => op_load,
        pc_src_sel => pc_src_sel,
        alu_operation => alu_operation,
        alu_op1_sel => alu_op1_sel,
        alu_op2_sel => alu_op2_sel,
        clr_z_flag => clr_z_flag,
        rf_input_sel => rf_input_sel,
        ld_r => ld_r,
        dm_wren => dm_wren,
        dm_addr_sel => dm_addr_sel,
        dm_data_sel => dm_data_sel,
        sip => sip,
        ssop_load => ssop_load,
        sop => sop,
        dpcr_load => dpcr_load,
        dpcr_data_sel => dpcr_data_sel,
        dpcr => dpcr,
        opcode => opcode,
        am => am,
        z_flag => z_flag,
        rz_zero => rz_zero,
        rz_out => rz_out,
        rx_out => rx_out,
        pc_out => pc_out
    );

    stim : PROCESS
    BEGIN
        -- Reset
        reset <= '1';
        tick;
        tick;
        reset <= '0';

        -- =====================================================
        -- SETUP: LDR R1 #10, LDR R2 #6
        -- Upper: AM=01 op=000000 Rz Rx | Lower: operand
        -- =====================================================
        -- LDR R1 #10 : x"4010" / x"000A"
        do_fetch(x"4010", x"000A", pm_data, ir_load, op_load);
        rf_input_sel <= "000";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"000A"
        REPORT "FAIL setup: LDR R1 #10" SEVERITY ERROR;

        -- LDR R2 #6 : x"4020" / x"0006"
        do_fetch(x"4020", x"0006", pm_data, ir_load, op_load);
        rf_input_sel <= "000";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"0006"
        REPORT "FAIL setup: LDR R2 #6" SEVERITY ERROR;

        -- =====================================================
        -- T1: AND R3 R1 #6 : R3 = 10 AND 6 = 2
        -- =====================================================
        do_fetch(x"4831", x"0006", pm_data, ir_load, op_load);
        alu_operation <= alu_and;
        alu_op1_sel <= "01";
        alu_op2_sel <= '0';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"0002"
        REPORT "FAIL T1: AND R3 R1 #6" SEVERITY ERROR;

        -- T2: AND R3 R3 R1 : R3 = 2 AND 10 = 2
        do_fetch(x"C831", x"0000", pm_data, ir_load, op_load);
        alu_operation <= alu_and;
        alu_op1_sel <= "00";
        alu_op2_sel <= '1';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"0002"
        REPORT "FAIL T2: AND R3 R3 R1" SEVERITY ERROR;

        -- =====================================================
        -- T3: OR R3 R1 #6 : R3 = 10 OR 6 = 14
        -- =====================================================
        do_fetch(x"4C31", x"0006", pm_data, ir_load, op_load);
        alu_operation <= alu_or;
        alu_op1_sel <= "01";
        alu_op2_sel <= '0';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"000E"
        REPORT "FAIL T3: OR R3 R1 #6" SEVERITY ERROR;

        -- T4: OR R3 R3 R2 : R3 = 14 OR 6 = 14
        do_fetch(x"CC32", x"0000", pm_data, ir_load, op_load);
        alu_operation <= alu_or;
        alu_op1_sel <= "00";
        alu_op2_sel <= '1';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"000E"
        REPORT "FAIL T4: OR R3 R3 R2" SEVERITY ERROR;

        -- =====================================================
        -- T5: ADD R3 R1 #6 : R3 = 10 + 6 = 16
        -- =====================================================
        do_fetch(x"7831", x"0006", pm_data, ir_load, op_load);
        alu_operation <= alu_add;
        alu_op1_sel <= "01";
        alu_op2_sel <= '0';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"0010"
        REPORT "FAIL T5: ADD R3 R1 #6" SEVERITY ERROR;

        -- T6: ADD R3 R3 R2 : R3 = 16 + 6 = 22
        do_fetch(x"F832", x"0000", pm_data, ir_load, op_load);
        alu_operation <= alu_add;
        alu_op1_sel <= "00";
        alu_op2_sel <= '1';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"0016"
        REPORT "FAIL T6: ADD R3 R3 R2" SEVERITY ERROR;

        -- =====================================================
        -- T7: SUBV R4 R1 #3 : R4 = R1 - 3 = 10 - 3 = 7
        -- =====================================================
        do_fetch(x"4341", x"0003", pm_data, ir_load, op_load);
        alu_operation <= alu_sub;
        alu_op1_sel <= "01";
        alu_op2_sel <= '0';
        rf_input_sel <= "011";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        alu_operation <= alu_idle;
        ASSERT rz_out = x"0007"
        REPORT "FAIL T7: SUBV R4 R1 #3" SEVERITY ERROR;

        -- =====================================================
        -- T8a: SUB R1 #10 : 10 - 10 = 0, Z = 1
        -- T8b: SUB R1 #5  : 10 - 5 = 5,  Z = 0
        -- =====================================================
        do_fetch(x"4410", x"000A", pm_data, ir_load, op_load);
        alu_operation <= alu_sub;
        alu_op1_sel <= "01";
        alu_op2_sel <= '1';
        ld_r <= '0';
        tick;
        alu_operation <= alu_idle;
        ASSERT z_flag = '1'
        REPORT "FAIL T8a: SUB R1 #10 Z flag" SEVERITY ERROR;

        do_fetch(x"4410", x"0005", pm_data, ir_load, op_load);
        alu_operation <= alu_sub;
        alu_op1_sel <= "01";
        alu_op2_sel <= '1';
        ld_r <= '0';
        tick;
        alu_operation <= alu_idle;
        ASSERT z_flag = '0'
        REPORT "FAIL T8b: SUB R1 #5 Z flag" SEVERITY ERROR;

        -- =====================================================
        -- T9: LDR Rz Rx : Rz <- DM[Rx]
        -- Setup: STR R1 $0x0006 stores 10 at DM[6]
        -- Upper: AM=10 STR=000010 Rz=0000 Rx=0001 = x"8201"
        -- =====================================================
        do_fetch(x"8201", x"0006", pm_data, ir_load, op_load);
        dm_wren <= '1';
        tick;
        dm_wren <= '0';

        -- Then: LDR R6 Rx (Rx=R2=6) reads DM[6] -> R6=10
        -- Upper LDR: AM=11 LDR=000000 Rz=0110 Rx=0010 = x"C062"
        do_fetch(x"C062", x"0000", pm_data, ir_load, op_load);
        dm_addr_sel <= "10";
        rf_input_sel <= "111";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        dm_addr_sel <= "00";
        ASSERT rz_out = x"000A"
        REPORT "FAIL T9: LDR Rz Rx" SEVERITY ERROR;

        -- =====================================================
        -- T10: LDR Rz $address : Rz <- DM[address]
        -- DM[6]=10 already set by T9 setup
        -- LDR R6 $0x0006 -> R6=10
        -- Upper: AM=10 LDR=000000 Rz=0110 Rx=0000 = x"8060"
        -- =====================================================
        do_fetch(x"8060", x"0006", pm_data, ir_load, op_load);
        tick;
        rf_input_sel <= "111";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"000A"
        REPORT "FAIL T10: LDR Rz $0x0006" SEVERITY ERROR;

        -- =====================================================
        -- T11: STR Rz #value : DM[Rz] <- value
        -- Store OPR=x"00AA" to address Rz=R1=10 (x"000A") DM[R1=10]
        -- Upper: AM=01 STR=000010 Rz=0001 Rx=0000 = x"4210"
        -- =====================================================
        do_fetch(x"4210", x"00AA", pm_data, ir_load, op_load);
        dm_addr_sel <= "01";
        dm_data_sel <= "01";
        dm_wren <= '1';
        tick;
        dm_wren <= '0';
        dm_addr_sel <= "00";
        dm_data_sel <= "00";

        -- Read back with LDR R6 $0x000A to verify -> x"8060" / x"000A"
        -- Upper: AM=10 LDR=000000 Rz=0110 Rx=0000 = x"8060"
        do_fetch(x"8060", x"000A", pm_data, ir_load, op_load);
        tick;
        rf_input_sel <= "111";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"00AA"
        REPORT "FAIL T11: STR Rz #value" SEVERITY ERROR;

        -- =====================================================
        -- T12: STR Rz Rx : DM[Rz] <- Rx
        -- Store R2=6 to DM[R1=10]
        -- Upper: AM=11 STR=000010 Rz=0001 Rx=0010 = x"C212"
        -- =====================================================
        do_fetch(x"C212", x"0000", pm_data, ir_load, op_load);
        dm_addr_sel <= "01";
        dm_wren <= '1';
        tick;
        dm_wren <= '0';
        dm_addr_sel <= "00";

        -- Read back with LDR R6 $0x000A to verify -> expect 6
        do_fetch(x"8060", x"000A", pm_data, ir_load, op_load);
        tick;
        rf_input_sel <= "111";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"0006"
        REPORT "FAIL T12: STR Rz Rx" SEVERITY ERROR;

        -- =====================================================
        -- T13: STR Rx $address : DM[address] <- Rx
        -- Store R2=6 to DM[0x0010]
        -- Upper: AM=10 STR=000010 Rz=0000 Rx=0010 = x"8202"
        -- =====================================================
        do_fetch(x"8202", x"0010", pm_data, ir_load, op_load);
        dm_wren <= '1';
        tick;
        dm_wren <= '0';

        -- Read back with LDR R6 $0x0010 to verify -> expect 6
        do_fetch(x"8060", x"0010", pm_data, ir_load, op_load);
        tick;
        rf_input_sel <= "111";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"0006"
        REPORT "FAIL T13: STR Rx $0x0010" SEVERITY ERROR;

        -- =====================================================
        -- T14: CLFZ : set Z=1 first, then clear it
        -- =====================================================
        do_fetch(x"4410", x"000A", pm_data, ir_load, op_load);
        alu_operation <= alu_sub;
        alu_op1_sel <= "01";
        alu_op2_sel <= '1';
        ld_r <= '0';
        tick;
        alu_operation <= alu_idle;
        ASSERT z_flag = '1'
        REPORT "FAIL T14 setup: Z should be 1 before CLFZ" SEVERITY ERROR;

        do_fetch(x"1000", x"0000", pm_data, ir_load, op_load);
        clr_z_flag <= '1';
        tick;
        clr_z_flag <= '0';
        ASSERT z_flag = '0'
        REPORT "FAIL T14: CLFZ did not clear Z" SEVERITY ERROR;

        -- =====================================================
        -- T15: NOOP : no state change
        -- =====================================================
        do_fetch(x"3400", x"0000", pm_data, ir_load, op_load);
        tick;

        -- =====================================================
        -- T16a: JMP #address : PC <- 0x0070
        -- Upper: AM=01 JMP=011000 Rz=0000 Rx=0000 = x"5800"
        -- =====================================================
        do_fetch(x"5800", x"0070", pm_data, ir_load, op_load);
        pc_load <= '1';
        tick;
        pc_load <= '0';
        ASSERT pc_out = x"0070"
        REPORT "FAIL T16a: JMP #address" SEVERITY ERROR;

        -- =====================================================
        -- T16b: JMP Rx : PC <- R2 = 6
        -- Upper: AM=11 JMP=011000 Rz=0000 Rx=0010 = x"D802"
        -- =====================================================
        do_fetch(x"D802", x"0000", pm_data, ir_load, op_load);
        pc_src_sel <= '1';
        pc_load <= '1';
        tick;
        pc_load <= '0';
        pc_src_sel <= '0';
        ASSERT pc_out = x"0006"
        REPORT "FAIL T16b: JMP Rx" SEVERITY ERROR;

        -- =====================================================
        -- T17: LSIP R5 : R5 <- SIP
        -- Upper: AM=11 LSIP=110111 Rz=0101 Rx=0000 = x"F750"
        -- =====================================================
        sip <= x"ABCD";
        do_fetch(x"F750", x"0000", pm_data, ir_load, op_load);
        rf_input_sel <= "101";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"ABCD"
        REPORT "FAIL T17: LSIP R5" SEVERITY ERROR;

        -- =====================================================
        -- T18: SSOP R1 : SOP <- R1 = 10
        -- Upper: AM=11 SSOP=111010 Rz=0000 Rx=0001 = x"FA01"
        -- =====================================================
        do_fetch(x"FA01", x"0000", pm_data, ir_load, op_load);
        ssop_load <= '1';
        tick;
        ssop_load <= '0';
        ASSERT sop = x"000A"
        REPORT "FAIL T18: SSOP R1" SEVERITY ERROR;

        -- =====================================================
        -- T19a: PRESENT R0 #0x0200 : R0=0 so should jump
        -- Upper: AM=01 PRESENT=011100 Rz=0000 Rx=0000 = x"5C00"
        -- =====================================================
        do_fetch(x"5C00", x"0200", pm_data, ir_load, op_load);
        ASSERT rz_zero = '1'
        REPORT "FAIL T19a: rz_zero should be 1 (R0=0)" SEVERITY ERROR;
        pc_load <= '1';
        tick;
        pc_load <= '0';
        ASSERT pc_out = x"0200"
        REPORT "FAIL T19a: PRESENT R0 should jump" SEVERITY ERROR;

        -- T19b: PRESENT R1 #0x0200 : R1=10 so should NOT jump
        -- Upper: AM=01 PRESENT=011100 Rz=0001 Rx=0000 = x"5C10"
        do_fetch(x"5C10", x"0200", pm_data, ir_load, op_load);
        ASSERT rz_zero = '0'
        REPORT "FAIL T19b: rz_zero should be 0 (R1=10)" SEVERITY ERROR;

        -- =====================================================
        -- T20: STRPC $0x0030 : DM[0x0030] <- PC
        -- First JMP to known address so PC is predictable
        -- Upper: AM=01 JMP=011000 Rz=0000 Rx=0000 = x"5800"
        -- =====================================================
        do_fetch(x"5800", x"0100", pm_data, ir_load, op_load);
        pc_load <= '1';
        tick;
        pc_load <= '0';
        -- PC = 0x0100; STRPC fetch will increment to 0x0102

        -- Upper: AM=10 STRPC=011101 Rz=0000 Rx=0000 = x"9D00"
        do_fetch(x"9D00", x"0030", pm_data, ir_load, op_load);
        -- pc_out = 0x0102 here
        dm_data_sel <= "10";
        dm_wren <= '1';
        tick;
        dm_wren <= '0';
        dm_data_sel <= "00";

        -- Verify: LDR R6 $0x0030 -> expect 0x0102
        -- Upper: AM=10 LDR=000000 Rz=0110 Rx=0000 = x"8060"
        tick; -- memory read latency
        do_fetch(x"8060", x"0030", pm_data, ir_load, op_load);
        tick; -- address registration latency
        rf_input_sel <= "111";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"0102"
        REPORT "FAIL T20: STRPC $0x0030" SEVERITY ERROR;

        -- =====================================================
        -- T21a: SZ #address : Z=1 so should jump
        -- First set Z=1 via SUB R1 #10
        -- Upper: AM=01 SUB=000100 Rz=0001 Rx=0000 = x"4410"
        -- =====================================================
        do_fetch(x"4410", x"000A", pm_data, ir_load, op_load);
        alu_operation <= alu_sub;
        alu_op1_sel <= "01";
        alu_op2_sel <= '1';
        ld_r <= '0';
        tick;
        alu_operation <= alu_idle;

        -- SZ #0x0300 : AM=01 SZ=010100 Rz=0000 Rx=0000 = x"5400"
        do_fetch(x"5400", x"0300", pm_data, ir_load, op_load);
        ASSERT z_flag = '1'
        REPORT "FAIL T21a setup: Z should be 1" SEVERITY ERROR;
        pc_load <= '1';
        tick;
        pc_load <= '0';
        ASSERT pc_out = x"0300"
        REPORT "FAIL T21a: SZ did not jump when Z=1" SEVERITY ERROR;

        -- =====================================================
        -- T21b: SZ #address : Z=0 so should NOT jump
        -- Clear Z first with CLFZ
        -- Upper: AM=00 CLFZ=010000 Rz=0000 Rx=0000 = x"1000"
        -- =====================================================
        do_fetch(x"1000", x"0000", pm_data, ir_load, op_load);
        clr_z_flag <= '1';
        tick;
        clr_z_flag <= '0';

        -- Upper: AM=01 SZ=010100 Rz=0000 Rx=0000 = x"5400"
        do_fetch(x"5400", x"0300", pm_data, ir_load, op_load);
        ASSERT z_flag = '0'
        REPORT "FAIL T21b: Z should be 0, SZ should not jump" SEVERITY ERROR;
        -- CU would not assert pc_load here, so no tick needed

        -- =====================================================
        -- T22: MAX R1 #7 : R1 = MAX(10, 7) = 10 (Rz wins)
        -- Upper: AM=01 MAX=011110 Rz=0001 Rx=0000 = x"5E10"
        -- =====================================================
        do_fetch(x"5E10", x"0007", pm_data, ir_load, op_load);
        rf_input_sel <= "100";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"000A"
        REPORT "FAIL T22: MAX R1 #7 (Rz should win)" SEVERITY ERROR;

        -- =====================================================
        -- T23: MAX R2 #10 : R2 = MAX(6, 10) = 10 (operand wins)
        -- Upper: AM=01 MAX=011110 Rz=0010 Rx=0000 = x"5E20"
        -- =====================================================
        do_fetch(x"5E20", x"000A", pm_data, ir_load, op_load);
        rf_input_sel <= "100";
        ld_r <= '1';
        tick;
        ld_r <= '0';
        ASSERT rz_out = x"000A"
        REPORT "FAIL T23: MAX R2 #10 (operand should win)" SEVERITY ERROR;

        -- =====================================================
        -- T24: DATACALL R1 : DPCR <- R1 & R7 = 0x000A_0000
        -- Upper: AM=11 DATACALL=101000 Rz=0000 Rx=0001 = x"E801"
        -- =====================================================
        do_fetch(x"E801", x"0000", pm_data, ir_load, op_load);
        dpcr_load <= '1';
        tick;
        dpcr_load <= '0';
        ASSERT dpcr(31 DOWNTO 16) = x"000A"
        REPORT "FAIL T24: DATACALL Rx upper" SEVERITY ERROR;
        ASSERT dpcr(15 DOWNTO 0) = x"0000"
        REPORT "FAIL T24: DATACALL Rx lower (R7)" SEVERITY ERROR;

        -- =====================================================
        -- T25: DATACALL R1 #0x00BB : DPCR <- R1 & 0x00BB = 0x000A_00BB
        -- Upper: AM=01 DATACALL=101001 Rz=0000 Rx=0001 = x"6901"
        -- =====================================================
        do_fetch(x"6901", x"00BB", pm_data, ir_load, op_load);
        dpcr_load <= '1';
        dpcr_data_sel <= '1';
        tick;
        dpcr_load <= '0';
        dpcr_data_sel <= '0';
        ASSERT dpcr(31 DOWNTO 16) = x"000A"
        REPORT "FAIL T25: DATACALL Rx #value upper" SEVERITY ERROR;
        ASSERT dpcr(15 DOWNTO 0) = x"00BB"
        REPORT "FAIL T25: DATACALL Rx #value lower" SEVERITY ERROR;

        REPORT "INFO: tb_datapath complete" SEVERITY NOTE;
        WAIT;
    END PROCESS stim;

END ARCHITECTURE sim;