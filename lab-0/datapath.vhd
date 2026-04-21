LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

ENTITY datapath IS
    PORT
    (
        clk           : IN bit_1;
        reset         : IN bit_1;

        -- External operand input (e.g. from switches or testbench)
        ir_operand    : IN bit_16;

        -- Register select
        sel_z         : IN INTEGER RANGE 0 TO 15;
        sel_x         : IN INTEGER RANGE 0 TO 15;

        -- ALU control
        alu_operation : IN bit_3;
        alu_op1_sel   : IN bit_2;
        alu_op2_sel   : IN bit_1;

        -- Register file control
        rf_input_sel  : IN bit_3;
        ld_r          : IN bit_1;

        -- Data memory control
        dm_address    : IN bit_16;
        dm_wren       : IN bit_1;

        -- Outputs
        z_flag        : OUT bit_1;
        alu_result    : OUT bit_16
    );
END ENTITY datapath;

ARCHITECTURE structural OF datapath IS

    -- internal signals connecting components together
    SIGNAL rx_sig       : bit_16;
    SIGNAL rz_sig       : bit_16;
    SIGNAL alu_out_sig  : bit_16;
    SIGNAL dm_out_sig   : bit_16;

    -- unused regfile inputs (tied to safe defaults)
    SIGNAL rz_max_sig   : bit_16 := X"0000";
    SIGNAL sip_hold_sig : bit_16 := X"0000";
    SIGNAL er_temp_sig  : bit_1  := '0';

    -- component declarations
    COMPONENT regfile IS
        PORT
        (
            clk          : IN bit_1;
            init         : IN bit_1;
            ld_r         : IN bit_1;
            sel_z        : IN INTEGER RANGE 0 TO 15;
            sel_x        : IN INTEGER RANGE 0 TO 15;
            rx           : OUT bit_16;
            rz           : OUT bit_16;
            rf_input_sel : IN bit_3;
            ir_operand   : IN bit_16;
            dm_out       : IN bit_16;
            aluout       : IN bit_16;
            rz_max       : IN bit_16;
            sip_hold     : IN bit_16;
            er_temp      : IN bit_1;
            r7           : OUT bit_16;
            dprr_res     : IN bit_1;
            dprr_res_reg : IN bit_1;
            dprr_wren    : IN bit_1
        );
    END COMPONENT;

    COMPONENT alu IS
        PORT
        (
            clk           : IN bit_1;
            z_flag        : OUT bit_1;
            alu_operation : IN bit_3;
            alu_op1_sel   : IN bit_2;
            alu_op2_sel   : IN bit_1;
            alu_carry     : IN bit_1;
            alu_result    : OUT bit_16;
            rx            : IN bit_16;
            rz            : IN bit_16;
            ir_operand    : IN bit_16;
            clr_z_flag    : IN bit_1;
            reset         : IN bit_1
        );
    END COMPONENT;

    COMPONENT data_mem IS
        PORT
        (
            address : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
            clock   : IN STD_LOGIC;
            data    : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            wren    : IN STD_LOGIC;
            q       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    -- Register File instance
    RF : regfile PORT MAP
    (
        clk          => clk,
        init         => reset,
        ld_r         => ld_r,
        sel_z        => sel_z,
        sel_x        => sel_x,
        rx           => rx_sig,
        rz           => rz_sig,
        rf_input_sel => rf_input_sel,
        ir_operand   => ir_operand,
        dm_out       => dm_out_sig,
        aluout       => alu_out_sig,
        rz_max       => rz_max_sig,
        sip_hold     => sip_hold_sig,
        er_temp      => er_temp_sig,
        r7           => OPEN,
        dprr_res     => '0',
        dprr_res_reg => '0',
        dprr_wren    => '0'
    );

    -- ALU instance
    ALU_INST : alu PORT
    MAP(
    clk           => clk,
    z_flag        => z_flag,
    alu_operation => alu_operation,
    alu_op1_sel   => alu_op1_sel,
    alu_op2_sel   => alu_op2_sel,
    alu_carry     => '0',
    alu_result    => alu_out_sig,
    rx            => rx_sig,
    rz            => rz_sig,
    ir_operand    => ir_operand,
    clr_z_flag    => '0',
    reset         => reset
    );

    -- Data Memory instance
    -- note: data_mem uses std_logic not bit_1/bit_16
    -- so we cast using the conversion
    DM : data_mem PORT
    MAP(
    address => dm_address(11 DOWNTO 0),
    clock   => clk,
    data    => rx_sig,
    wren    => dm_wren,
    q       => dm_out_sig
    );

    alu_result <= alu_out_sig;

END ARCHITECTURE structural;
