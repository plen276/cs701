LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.recop_types.ALL;

-- ============================================================
-- ReCOP GP1 Processor Core
--
-- Structural entity connecting:
--   control_unit  - multicycle FSM
--   datapath      - registers, ALU, data memory
--   prog_mem      - ROM loaded from rawOutput.mif (PC => instruction words)
--
-- SIP tied to 0x0000 for GP1. SOP/DPCR outputs unused until GP2.
-- Board peripherals are connected in recop_top.vhd.
-- ============================================================

ENTITY recop IS
    PORT
    (
        clk        : IN STD_LOGIC;
        reset      : IN STD_LOGIC;
        z_flag     : OUT STD_LOGIC;

        debug_mode : IN STD_LOGIC;
        debug_step : IN STD_LOGIC;

        pc_out     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        rz_out     : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        opcode_out : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
        am_out     : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        state_out  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
    );
END ENTITY recop;

ARCHITECTURE structural OF recop IS

    -- ===== CU => Datapath =====
    SIGNAL pc_load       : STD_LOGIC;
    SIGNAL pc_src_sel    : STD_LOGIC;
    SIGNAL ir_load       : STD_LOGIC;
    SIGNAL op_load       : STD_LOGIC;
    SIGNAL alu_operation : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL alu_op1_sel   : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL alu_op2_sel   : STD_LOGIC;
    SIGNAL clr_z_flag    : STD_LOGIC;
    SIGNAL rf_input_sel  : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL ld_r          : STD_LOGIC;
    SIGNAL dm_wren       : STD_LOGIC;
    SIGNAL dm_addr_sel   : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL dm_data_sel   : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL ssop_load     : STD_LOGIC;
    SIGNAL dpcr_load     : STD_LOGIC;
    SIGNAL dpcr_data_sel : STD_LOGIC;

    -- ===== Datapath => CU =====
    SIGNAL opcode        : STD_LOGIC_VECTOR(5 DOWNTO 0);
    SIGNAL am            : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL z_flag_i      : STD_LOGIC;
    SIGNAL rz_zero       : STD_LOGIC;

    -- ===== Program memory =====
    SIGNAL pc_sig        : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL pm_data       : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_sig        : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL state_sig     : STD_LOGIC_VECTOR(2 DOWNTO 0);

    -- SIP not used in GP1
    CONSTANT SIP_ZERO    : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- ===== Component declarations =====

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
            dpcr_data_sel : OUT STD_LOGIC;
            debug_mode    : IN STD_LOGIC;
            debug_step    : IN STD_LOGIC;
            state_out     : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT datapath IS
        PORT
        (
            clk           : IN STD_LOGIC;
            reset         : IN STD_LOGIC;
            pm_data       : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            pc_load       : IN STD_LOGIC;
            ir_load       : IN STD_LOGIC;
            op_load       : IN STD_LOGIC;
            pc_src_sel    : IN STD_LOGIC;
            alu_operation : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            alu_op1_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            alu_op2_sel   : IN STD_LOGIC;
            clr_z_flag    : IN STD_LOGIC;
            rf_input_sel  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            ld_r          : IN STD_LOGIC;
            dm_wren       : IN STD_LOGIC;
            dm_addr_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            dm_data_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            sip           : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            ssop_load     : IN STD_LOGIC;
            sop           : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dpcr_load     : IN STD_LOGIC;
            dpcr_data_sel : IN STD_LOGIC;
            dpcr          : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            am            : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            opcode        : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
            z_flag        : OUT STD_LOGIC;
            rz_zero       : OUT STD_LOGIC;
            rz_out        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rx_out        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            pc_out        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT prog_mem IS
        PORT
        (
            address : IN STD_LOGIC_VECTOR(14 DOWNTO 0);
            clock   : IN STD_LOGIC;
            q       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    z_flag     <= z_flag_i;
    pc_out     <= pc_sig;
    rz_out     <= rz_sig;
    opcode_out <= opcode;
    am_out     <= am;
    state_out  <= state_sig;

    CU : control_unit PORT MAP
    (
        clk           => clk,
        reset         => reset,
        am            => am,
        opcode        => opcode,
        z_flag        => z_flag_i,
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
        dpcr_data_sel => dpcr_data_sel,
        debug_mode    => debug_mode,
        debug_step    => debug_step,
        state_out     => state_sig
    );

    DP : datapath PORT
    MAP (
    clk           => clk,
    reset         => reset,
    pm_data       => pm_data,
    pc_load       => pc_load,
    ir_load       => ir_load,
    op_load       => op_load,
    pc_src_sel    => pc_src_sel,
    alu_operation => alu_operation,
    alu_op1_sel   => alu_op1_sel,
    alu_op2_sel   => alu_op2_sel,
    clr_z_flag    => clr_z_flag,
    rf_input_sel  => rf_input_sel,
    ld_r          => ld_r,
    dm_wren       => dm_wren,
    dm_addr_sel   => dm_addr_sel,
    dm_data_sel   => dm_data_sel,
    sip           => SIP_ZERO,
    ssop_load     => ssop_load,
    sop           => OPEN,
    dpcr_load     => dpcr_load,
    dpcr_data_sel => dpcr_data_sel,
    dpcr          => OPEN,
    am            => am,
    opcode        => opcode,
    z_flag        => z_flag_i,
    rz_zero       => rz_zero,
    rz_out        => rz_sig,
    rx_out        => OPEN,
    pc_out        => pc_sig
    );

    PM : prog_mem PORT
    MAP(
    address => pc_sig(14 DOWNTO 0),
    clock   => clk,
    q       => pm_data
    );

END ARCHITECTURE structural;
