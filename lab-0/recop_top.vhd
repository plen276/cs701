LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.various_constants.ALL;

-- Top-level board entity for Lab 0 DE1-SoC testbed.
-- Sequences through the same 7 operations as the testbench using an FSM.
-- KEY3 (active low) steps to the next operation.
-- KEY0 (active low) resets back to idle.
-- LEDR(7:0) shows lower byte of alu_result.
-- LEDR(8) shows z_flag.
-- HEX3-HEX0 shows full 16-bit alu_result as 4 hex digits.

ENTITY recop_top IS
    PORT (
        CLOCK_50 : IN  STD_LOGIC;
        KEY      : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);  -- active low push buttons
        SW       : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);  -- slide switches (spare)
        LEDR     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
        HEX0     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX1     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX2     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
        HEX3     : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END ENTITY recop_top;

ARCHITECTURE structural OF recop_top IS

    -- FSM state type
    TYPE fsm_state IS (
        ST_IDLE,    -- hold reset
        ST_LOAD_R1, -- LDR R1 #0x0005
        ST_LOAD_R2, -- LDR R2 #0x0003
        ST_ADD,     -- ADD R1 R1 R2  => R1 = 0x0008
        ST_AND,     -- AND R1 R2 #0x0006 => R1 = 0x0002
        ST_SUB,     -- SUB R2 #0x0003 => z_flag = 1
        ST_STR,     -- STR R2 $0x0010
        ST_LDR,     -- LDR R3 $0x0010 => R3 = 0x0003
        ST_DONE     -- finished, hold outputs
    );

    SIGNAL state : fsm_state := ST_IDLE;

    -- Registered previous KEY values for edge detection
    SIGNAL key0_prev : STD_LOGIC := '1';
    SIGNAL key3_prev : STD_LOGIC := '1';

    -- Datapath control signals driven by FSM
    SIGNAL dp_reset        : bit_1  := '1';
    SIGNAL dp_ir_operand   : bit_16 := X"0000";
    SIGNAL dp_sel_z        : INTEGER RANGE 0 TO 15 := 0;
    SIGNAL dp_sel_x        : INTEGER RANGE 0 TO 15 := 0;
    SIGNAL dp_alu_operation: bit_3  := "000";
    SIGNAL dp_alu_op1_sel  : bit_2  := "00";
    SIGNAL dp_alu_op2_sel  : bit_1  := '0';
    SIGNAL dp_rf_input_sel : bit_3  := "000";
    SIGNAL dp_ld_r         : bit_1  := '0';
    SIGNAL dp_dm_address   : bit_16 := X"0000";
    SIGNAL dp_dm_wren      : bit_1  := '0';

    -- Datapath outputs
    SIGNAL dp_z_flag    : bit_1;
    SIGNAL dp_alu_result: bit_16;

    -- Latched display — holds the last written ALU result so LEDs/HEX
    -- don't update again when the register file is read on the next cycle
    SIGNAL display_result : bit_16 := X"0000";

    -- Component declarations
    COMPONENT datapath IS
        PORT (
            clk           : IN  bit_1;
            reset         : IN  bit_1;
            ir_operand    : IN  bit_16;
            sel_z         : IN  INTEGER RANGE 0 TO 15;
            sel_x         : IN  INTEGER RANGE 0 TO 15;
            alu_operation : IN  bit_3;
            alu_op1_sel   : IN  bit_2;
            alu_op2_sel   : IN  bit_1;
            rf_input_sel  : IN  bit_3;
            ld_r          : IN  bit_1;
            dm_address    : IN  bit_16;
            dm_wren       : IN  bit_1;
            z_flag        : OUT bit_1;
            alu_result    : OUT bit_16
        );
    END COMPONENT;

    COMPONENT hex_to_7seg IS
        PORT (
            hex_in  : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
            seg_out : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    -- Datapath instance
    DUT : datapath PORT MAP (
        clk           => CLOCK_50,
        reset         => dp_reset,
        ir_operand    => dp_ir_operand,
        sel_z         => dp_sel_z,
        sel_x         => dp_sel_x,
        alu_operation => dp_alu_operation,
        alu_op1_sel   => dp_alu_op1_sel,
        alu_op2_sel   => dp_alu_op2_sel,
        rf_input_sel  => dp_rf_input_sel,
        ld_r          => dp_ld_r,
        dm_address    => dp_dm_address,
        dm_wren       => dp_dm_wren,
        z_flag        => dp_z_flag,
        alu_result    => dp_alu_result
    );

    -- 7-segment display instances (latched result shown as 4 hex digits)
    SEG0 : hex_to_7seg PORT MAP (hex_in => display_result(3  DOWNTO 0),  seg_out => HEX0);
    SEG1 : hex_to_7seg PORT MAP (hex_in => display_result(7  DOWNTO 4),  seg_out => HEX1);
    SEG2 : hex_to_7seg PORT MAP (hex_in => display_result(11 DOWNTO 8),  seg_out => HEX2);
    SEG3 : hex_to_7seg PORT MAP (hex_in => display_result(15 DOWNTO 12), seg_out => HEX3);

    -- LED outputs
    LEDR(7 DOWNTO 0) <= display_result(7 DOWNTO 0);  -- lower byte of latched result
    LEDR(8)          <= dp_z_flag;                   -- zero flag
    LEDR(9)          <= '0';                          -- unused

    -- FSM: advances on KEY3 falling edge (active low button press)
    -- Resets on KEY0 falling edge
    fsm_proc : PROCESS(CLOCK_50)
    BEGIN
        IF rising_edge(CLOCK_50) THEN

            -- Register previous key states for edge detection
            key0_prev <= KEY(0);
            key3_prev <= KEY(3);

            -- Latch display result when a register write is in progress.
            -- Captured here (one cycle after the KEY press) while the register
            -- file still holds the OLD values, so ALU output = correct result.
            IF dp_ld_r = '1' THEN
                display_result <= dp_alu_result;
            END IF;

            -- Default: keep all write-enables low each cycle
            -- (only pulse ld_r/dm_wren for one clock when stepping)
            dp_ld_r    <= '0';
            dp_dm_wren <= '0';
            dp_reset   <= '0';

            -- KEY0 falling edge = reset (return to idle)
            IF KEY(0) = '0' AND key0_prev = '1' THEN
                state       <= ST_IDLE;
                dp_reset    <= '1';
                dp_ir_operand    <= X"0000";
                dp_sel_z         <= 0;
                dp_sel_x         <= 0;
                dp_alu_operation <= "000";
                dp_alu_op1_sel   <= "00";
                dp_alu_op2_sel   <= '0';
                dp_rf_input_sel  <= "000";
                dp_dm_address    <= X"0000";

            -- KEY3 falling edge = step to next operation
            ELSIF KEY(3) = '0' AND key3_prev = '1' THEN
                CASE state IS

                    WHEN ST_IDLE =>
                        -- Release reset, do nothing yet — next press begins LOAD_R1
                        dp_reset <= '0';
                        state <= ST_LOAD_R1;

                    WHEN ST_LOAD_R1 =>
                        -- LDR R1 #0x0005 : write ir_operand into R1
                        dp_ir_operand    <= X"0005";
                        dp_sel_z         <= 1;
                        dp_rf_input_sel  <= "000";
                        dp_ld_r          <= '1';
                        state <= ST_LOAD_R2;

                    WHEN ST_LOAD_R2 =>
                        -- LDR R2 #0x0003 : write ir_operand into R2
                        dp_ir_operand    <= X"0003";
                        dp_sel_z         <= 2;
                        dp_rf_input_sel  <= "000";
                        dp_ld_r          <= '1';
                        state <= ST_ADD;

                    WHEN ST_ADD =>
                        -- ADD R1 R1 R2 : R1 <- R1 + R2 = 0x0008
                        dp_sel_z         <= 1;
                        dp_sel_x         <= 2;
                        dp_alu_operation <= alu_add;
                        dp_alu_op1_sel   <= "00";   -- op1 = Rx (R2)
                        dp_alu_op2_sel   <= '1';    -- op2 = Rz (R1)
                        dp_rf_input_sel  <= "011";
                        dp_ld_r          <= '1';
                        state <= ST_AND;

                    WHEN ST_AND =>
                        -- AND R1 R2 #0x0006 : R1 <- R2 AND 0x0006 = 0x0002
                        dp_ir_operand    <= X"0006";
                        dp_sel_z         <= 1;
                        dp_sel_x         <= 2;
                        dp_alu_operation <= alu_and;
                        dp_alu_op1_sel   <= "01";   -- op1 = ir_operand
                        dp_alu_op2_sel   <= '0';    -- op2 = Rx (R2)
                        dp_rf_input_sel  <= "011";
                        dp_ld_r          <= '1';
                        state <= ST_SUB;

                    WHEN ST_SUB =>
                        -- SUB R2 #0x0003 : z_flag <- (R2 - 0x0003 = 0)
                        dp_ir_operand    <= X"0003";
                        dp_sel_z         <= 2;
                        dp_alu_operation <= alu_sub;
                        dp_alu_op1_sel   <= "01";   -- op1 = ir_operand
                        dp_alu_op2_sel   <= '1';    -- op2 = Rz (R2)
                        dp_ld_r          <= '0';    -- SUB does not write back
                        state <= ST_STR;

                    WHEN ST_STR =>
                        -- STR R2 $0x0010 : DM[0x0010] <- R2
                        dp_sel_x      <= 2;
                        dp_dm_address <= X"0010";
                        dp_dm_wren    <= '1';
                        state <= ST_LDR;

                    WHEN ST_LDR =>
                        -- LDR R3 $0x0010 : R3 <- DM[0x0010]
                        dp_sel_z        <= 3;
                        dp_dm_address   <= X"0010";
                        dp_dm_wren      <= '0';
                        dp_rf_input_sel <= "111";
                        dp_ld_r         <= '1';
                        state <= ST_DONE;

                    WHEN ST_DONE =>
                        -- Hold — press KEY0 to reset
                        NULL;

                END CASE;
            END IF;

            -- Hold reset asserted while in IDLE
            IF state = ST_IDLE THEN
                dp_reset <= '1';
            END IF;

        END IF;
    END PROCESS fsm_proc;

END ARCHITECTURE structural;
