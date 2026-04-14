LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

ENTITY tb_datapath IS
    -- testbench has no ports
END ENTITY tb_datapath;

ARCHITECTURE sim OF tb_datapath IS

    -- component declaration of your datapath
    COMPONENT datapath IS
        PORT (
            clk : IN bit_1;
            reset : IN bit_1;
            ir_operand : IN bit_16;
            sel_z : IN INTEGER RANGE 0 TO 15;
            sel_x : IN INTEGER RANGE 0 TO 15;
            alu_operation : IN bit_3;
            alu_op1_sel : IN bit_2;
            alu_op2_sel : IN bit_1;
            rf_input_sel : IN bit_3;
            ld_r : IN bit_1;
            dm_address : IN bit_16;
            dm_wren : IN bit_1;
            z_flag : OUT bit_1;
            alu_result : OUT bit_16
        );
    END COMPONENT;

    -- signals to drive the datapath
    SIGNAL clk : bit_1 := '0';
    SIGNAL reset : bit_1 := '0';
    SIGNAL ir_operand : bit_16 := X"0000";
    SIGNAL sel_z : INTEGER RANGE 0 TO 15 := 0;
    SIGNAL sel_x : INTEGER RANGE 0 TO 15 := 0;
    SIGNAL alu_operation : bit_3 := "000";
    SIGNAL alu_op1_sel : bit_2 := "00";
    SIGNAL alu_op2_sel : bit_1 := '0';
    SIGNAL rf_input_sel : bit_3 := "000";
    SIGNAL ld_r : bit_1 := '0';
    SIGNAL dm_address : bit_16 := X"0000";
    SIGNAL dm_wren : bit_1 := '0';
    SIGNAL z_flag : bit_1;
    SIGNAL alu_result : bit_16;

    -- clock period
    CONSTANT CLK_PERIOD : TIME := 20 ns;

BEGIN

    -- instantiate the datapath
    DUT : datapath PORT MAP(
        clk => clk,
        reset => reset,
        ir_operand => ir_operand,
        sel_z => sel_z,
        sel_x => sel_x,
        alu_operation => alu_operation,
        alu_op1_sel => alu_op1_sel,
        alu_op2_sel => alu_op2_sel,
        rf_input_sel => rf_input_sel,
        ld_r => ld_r,
        dm_address => dm_address,
        dm_wren => dm_wren,
        z_flag => z_flag,
        alu_result => alu_result
    );

    -- clock generation - toggles every half period forever
    clk <= NOT clk AFTER CLK_PERIOD / 2;

    -- stimulus process - this is where we test each instruction
    stimulus : PROCESS
    BEGIN

        -- =====================
        -- RESET
        -- =====================
        reset <= '1';
        WAIT FOR CLK_PERIOD * 2;
        reset <= '0';
        WAIT FOR CLK_PERIOD;

        -- =====================
        -- TEST 1: LDR R1 #0x0005
        -- Load immediate value 0x0005 into R1
        -- rf_input_sel = "000" means write ir_operand into Rz
        -- =====================
        ir_operand <= X"0005";
        sel_z <= 1; -- destination is R1
        rf_input_sel <= "000"; -- write ir_operand to Rz
        ld_r <= '1'; -- enable write
        WAIT FOR CLK_PERIOD;
        ld_r <= '0';
        WAIT FOR CLK_PERIOD;
        -- R1 should now contain 0x0005

        -- =====================
        -- TEST 2: LDR R2 #0x0003
        -- Load immediate value 0x0003 into R2
        -- =====================
        ir_operand <= X"0003";
        sel_z <= 2;
        rf_input_sel <= "000";
        ld_r <= '1';
        WAIT FOR CLK_PERIOD;
        ld_r <= '0';
        WAIT FOR CLK_PERIOD;
        -- R2 should now contain 0x0003

        -- =====================
        -- TEST 3: ADD R1 R1 R2
        -- R1 <- R1 + R2 (0x0005 + 0x0003 = 0x0008)
        -- alu_op1_sel = "00" means op1 = Rx (R2)
        -- alu_op2_sel = '1'  means op2 = Rz (R1)
        -- rf_input_sel = "011" means write aluout to Rz
        -- =====================
        sel_z <= 1; -- Rz = R1
        sel_x <= 2; -- Rx = R2
        alu_operation <= alu_add; -- ADD operation
        alu_op1_sel <= "00"; -- op1 = Rx
        alu_op2_sel <= '1'; -- op2 = Rz
        rf_input_sel <= "011"; -- write ALU result to Rz
        ld_r <= '1';
        WAIT FOR CLK_PERIOD;
        ld_r <= '0';
        WAIT FOR CLK_PERIOD;
        -- R1 should now contain 0x0008

        -- =====================
        -- TEST 4: AND R1 R2 #0x0006
        -- R1 <- R2 AND 0x0006 (0x0003 AND 0x0006 = 0x0002)
        -- alu_op1_sel = "01" means op1 = ir_operand
        -- alu_op2_sel = '0'  means op2 = Rx (R2)
        -- =====================
        ir_operand <= X"0006";
        sel_z <= 1; -- destination R1
        sel_x <= 2; -- Rx = R2 (0x0003)
        alu_operation <= alu_and;
        alu_op1_sel <= "01"; -- op1 = ir_operand
        alu_op2_sel <= '0'; -- op2 = Rx
        rf_input_sel <= "011";
        ld_r <= '1';
        WAIT FOR CLK_PERIOD;
        ld_r <= '0';
        WAIT FOR CLK_PERIOD;
        -- R1 should now contain 0x0002

        -- =====================
        -- TEST 5: SUB R2 #0x0003
        -- Z <- 1 if R2 - 0x0003 = 0
        -- R2 = 0x0003, operand = 0x0003, result = 0 so Z should go to 1
        -- alu_op1_sel = "01" means op1 = ir_operand
        -- alu_op2_sel = '1'  means op2 = Rz (R2)
        -- ld_r = '0' because SUB does NOT write result back
        -- =====================
        ir_operand <= X"0003";
        sel_z <= 2; -- Rz = R2 (0x0003)
        alu_operation <= alu_sub;
        alu_op1_sel <= "01"; -- op1 = ir_operand
        alu_op2_sel <= '1'; -- op2 = Rz
        ld_r <= '0'; -- do NOT write back for SUB
        WAIT FOR CLK_PERIOD;
        -- z_flag should now be 1

        -- =====================
        -- TEST 6: STR R2 $0x0010
        -- DM[0x0010] <- R2 (store R2 into data memory)
        -- =====================
        sel_x <= 2; -- Rx = R2 (value to store)
        dm_address <= X"0010";
        dm_wren <= '1'; -- enable memory write
        WAIT FOR CLK_PERIOD;
        dm_wren <= '0';
        WAIT FOR CLK_PERIOD;

        -- =====================
        -- TEST 7: LDR R3 $0x0010
        -- R3 <- DM[0x0010] (load from data memory into R3)
        -- rf_input_sel = "111" means write dm_out to Rz
        -- =====================
        sel_z <= 3; -- destination R3
        dm_address <= X"0010";
        dm_wren <= '0';
        rf_input_sel <= "111"; -- write dm_out to Rz
        ld_r <= '1';
        WAIT FOR CLK_PERIOD;
        ld_r <= '0';
        WAIT FOR CLK_PERIOD;
        -- R3 should now contain same value as R2 (0x0003)

        WAIT; -- stop simulation
    END PROCESS;

END ARCHITECTURE sim;