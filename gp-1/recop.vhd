LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;

-- ============================================================
-- ReCOP Processor Core
--
-- Structural entity wiring the Control Unit and Datapath.
-- This is the reusable processor IP — no board I/O here.
-- Board peripherals are connected in recop_top.vhd.
-- In GP2 this entity becomes a node in the HMPSoC.
-- ============================================================

ENTITY recop IS
    PORT (
        clk    : IN  bit_1;
        reset  : IN  bit_1;
        z_flag : OUT bit_1   -- exposed for board debug; SOP/SIP added in GP2
    );
END ENTITY recop;

ARCHITECTURE structural OF recop IS

    -- ===== Control signals: CU → Datapath =====
    SIGNAL pc_load       : bit_1;
    SIGNAL ir_load       : bit_1;
    SIGNAL op_load       : bit_1;
    SIGNAL alu_operation : bit_3;
    SIGNAL alu_op1_sel   : bit_2;
    SIGNAL alu_op2_sel   : bit_1;
    SIGNAL clr_z_flag    : bit_1;
    SIGNAL rf_input_sel  : bit_3;
    SIGNAL ld_r          : bit_1;
    SIGNAL dm_wren       : bit_1;

    -- ===== Status signals: Datapath → CU =====
    SIGNAL opcode        : bit_6;
    SIGNAL am            : bit_2;
    SIGNAL z_flag_i      : bit_1;   -- internal; drives port z_flag

    -- ===== Component declarations =====

    COMPONENT control_unit IS
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
    END COMPONENT;

    COMPONENT datapath IS
        PORT (
            clk           : IN  bit_1;
            reset         : IN  bit_1;
            pc_load       : IN  bit_1;
            ir_load       : IN  bit_1;
            op_load       : IN  bit_1;
            alu_operation : IN  bit_3;
            alu_op1_sel   : IN  bit_2;
            alu_op2_sel   : IN  bit_1;
            rf_input_sel  : IN  bit_3;
            ld_r          : IN  bit_1;
            dm_wren       : IN  bit_1;
            clr_z_flag    : IN  bit_1;
            opcode        : OUT bit_6;
            am            : OUT bit_2;
            z_flag        : OUT bit_1
        );
    END COMPONENT;

BEGIN

    z_flag <= z_flag_i;

    CU : control_unit PORT MAP (
        clk           => clk,
        reset         => reset,
        opcode        => opcode,
        am            => am,
        z_flag        => z_flag_i,
        pc_load       => pc_load,
        ir_load       => ir_load,
        op_load       => op_load,
        alu_operation => alu_operation,
        alu_op1_sel   => alu_op1_sel,
        alu_op2_sel   => alu_op2_sel,
        clr_z_flag    => clr_z_flag,
        rf_input_sel  => rf_input_sel,
        ld_r          => ld_r,
        dm_wren       => dm_wren
    );

    DP : datapath PORT MAP (
        clk           => clk,
        reset         => reset,
        pc_load       => pc_load,
        ir_load       => ir_load,
        op_load       => op_load,
        alu_operation => alu_operation,
        alu_op1_sel   => alu_op1_sel,
        alu_op2_sel   => alu_op2_sel,
        rf_input_sel  => rf_input_sel,
        ld_r          => ld_r,
        dm_wren       => dm_wren,
        clr_z_flag    => clr_z_flag,
        opcode        => opcode,
        am            => am,
        z_flag        => z_flag_i
    );

END ARCHITECTURE structural;
