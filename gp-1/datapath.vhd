LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY datapath IS
    PORT
    (
        clk           : IN STD_LOGIC;
        reset         : IN STD_LOGIC;

        pm_data       : IN STD_LOGIC_VECTOR(15 DOWNTO 0);

        -- ==============================
        -- From Control Unit
        -- ==============================
        -- Fetch control
        pc_load       : IN STD_LOGIC; -- load OPR into PC (jumps)
        ir_load       : IN STD_LOGIC; -- latch PM output into IR[31:16]
        op_load       : IN STD_LOGIC; -- latch PM output into IR[15:0] and OPR
        pc_src_sel    : IN STD_LOGIC; -- '0'=operand (JMP #), '1'=Rx (JMP Rx)

        -- ALU control
        alu_operation : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        alu_op1_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
        alu_op2_sel   : IN STD_LOGIC;
        clr_z_flag    : IN STD_LOGIC; -- CLFZ: clear zero flag

        -- Register file control
        rf_input_sel  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        ld_r          : IN STD_LOGIC;

        -- Data memory control
        dm_wren       : IN STD_LOGIC;
        dm_addr_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- "00"=operand, "01"=Rz, "10"=Rx
        dm_data_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- "00"=Rx, "01"=operand, "10"=PC

        -- Board I/O
        sip           : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        ssop_load     : IN STD_LOGIC;
        sop           : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        dpcr_load     : IN STD_LOGIC;
        dpcr_data_sel : IN STD_LOGIC; -- '0'=R7, '1'=operand
        dpcr          : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- ==============================
        -- To Control Unit
        -- ==============================
        -- Status ouputs
        am            : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        opcode        : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
        z_flag        : OUT STD_LOGIC;
        rz_zero       : OUT STD_LOGIC;

        -- ==============================
        -- DEBUG PORTS
        -- TODO: Delete
        -- ==============================
        rz_out        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        rx_out        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        pc_out        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END ENTITY datapath;

ARCHITECTURE structural OF datapath IS
    -- Fetch registers
    SIGNAL pc          : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL ir          : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL operand     : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- IR field decode
    SIGNAL sel_z_i     : INTEGER RANGE 0 TO 15;
    SIGNAL sel_x_i     : INTEGER RANGE 0 TO 15;

    -- Interconnect signals
    SIGNAL rx_sig      : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL rz_sig      : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL alu_out_sig : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dm_out_sig  : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dm_addr_sig : STD_LOGIC_VECTOR(11 DOWNTO 0);
    SIGNAL dm_data_sig : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL max_sig     : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL sop_reg     : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL r7_sig      : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL dpcr_reg    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');

    -- ==============================
    -- Component declarations
    -- ==============================
    COMPONENT regfile IS
        PORT
        (
            clk          : IN STD_LOGIC;
            init         : IN STD_LOGIC;
            ld_r         : IN STD_LOGIC;
            sel_z        : IN INTEGER RANGE 0 TO 15;
            sel_x        : IN INTEGER RANGE 0 TO 15;
            rx           : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rz           : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rf_input_sel : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            ir_operand   : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            dm_out       : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            aluout       : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            rz_max       : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            sip_hold     : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            er_temp      : IN STD_LOGIC;
            r7           : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            dprr_res     : IN STD_LOGIC;
            dprr_res_reg : IN STD_LOGIC;
            dprr_wren    : IN STD_LOGIC
        );
    END COMPONENT;

    COMPONENT alu IS
        PORT
        (
            clk           : IN STD_LOGIC;
            z_flag        : OUT STD_LOGIC;
            alu_operation : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            alu_op1_sel   : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
            alu_op2_sel   : IN STD_LOGIC;
            alu_carry     : IN STD_LOGIC;
            alu_result    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            rx            : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            rz            : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            ir_operand    : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            clr_z_flag    : IN STD_LOGIC;
            reset         : IN STD_LOGIC
        );
    END COMPONENT;

    COMPONENT data_mem IS
        PORT
        (
            address : IN STD_LOGIC_VECTOR (11 DOWNTO 0);
            clock   : IN STD_LOGIC;
            data    : IN STD_LOGIC_VECTOR (15 DOWNTO 0);
            wren    : IN STD_LOGIC;
            q       : OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN
    -- Decode IR fields into signals
    am          <= ir(31 DOWNTO 30);
    opcode      <= ir(29 DOWNTO 24);
    sel_z_i     <= TO_INTEGER(unsigned(ir(23 DOWNTO 20)));
    sel_x_i     <= TO_INTEGER(unsigned(ir(19 DOWNTO 16)));
    dm_addr_sig <= rz_sig(11 DOWNTO 0) WHEN dm_addr_sel = "01" ELSE
        rx_sig(11 DOWNTO 0) WHEN dm_addr_sel = "10" ELSE
        operand(11 DOWNTO 0);
    dm_data_sig <= operand WHEN dm_data_sel = "01" ELSE
        pc WHEN dm_data_sel = "10" ELSE
        rx_sig;
    max_sig <= rz_sig WHEN unsigned(rz_sig) >= unsigned(operand) ELSE
        operand;
    sop     <= sop_reg;
    dpcr    <= dpcr_reg;
    rz_zero <= '1' WHEN rz_sig = x"0000" ELSE
        '0';

    -- ==============================
    -- DEBUG PORT ASSIGNMENTS
    -- TODO: Delete
    -- ==============================
    rz_out <= rz_sig;
    rx_out <= rx_sig;
    pc_out <= pc;

    PROCESS (clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset = '1' THEN
                pc      <= (OTHERS => '0');
                ir      <= (OTHERS => '0');
                operand <= (OTHERS => '0');
            ELSIF pc_load = '1' THEN
                -- jump: overwrite PC with operand
                IF pc_src_sel = '1' THEN
                    pc <= rx_sig;
                ELSE
                    pc <= operand;
                END IF;
            ELSIF ir_load = '1' THEN
                -- FETCH_1: load upper half of IR, advance PC
                ir(31 DOWNTO 16) <= pm_data;
                pc               <= STD_LOGIC_VECTOR(unsigned(pc) + 1);
            ELSIF op_load = '1' THEN
                -- FETCH_2: load lower half of IR and OPR, advance PC
                ir(15 DOWNTO 0) <= pm_data;
                operand         <= pm_data;
                pc              <= STD_LOGIC_VECTOR(unsigned(pc) + 1);
            END IF;

            IF ssop_load = '1' THEN
                sop_reg <= rx_sig;
            END IF;

            IF dpcr_load = '1' THEN
                dpcr_reg(31 DOWNTO 16) <= rx_sig;
                IF dpcr_data_sel = '1' THEN
                    dpcr_reg(15 DOWNTO 0) <= operand;
                ELSE
                    dpcr_reg(15 DOWNTO 0) <= r7_sig;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- ==============================
    -- Component instantiations
    -- ==============================
    -- Register File
    -- ir_operand fed from operand
    -- sel_z / sel_x decoded from IR fields
    RF : regfile PORT MAP
    (
        clk          => clk,
        init         => reset,
        ld_r         => ld_r,
        sel_z        => sel_z_i,
        sel_x        => sel_x_i,
        rx           => rx_sig,
        rz           => rz_sig,
        rf_input_sel => rf_input_sel,
        ir_operand   => operand,
        dm_out       => dm_out_sig,
        aluout       => alu_out_sig,
        rz_max       => max_sig,
        sip_hold     => sip,
        er_temp      => '0',
        r7           => r7_sig,
        dprr_res     => '0',
        dprr_res_reg => '0',
        dprr_wren    => '0'
    );

    -- ALU
    -- ir_operand fed from operand
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
    ir_operand    => operand,
    clr_z_flag    => clr_z_flag,
    reset         => reset
    );

    -- Data Memory
    -- Address source : dm_addr_sel="00" uses operand   (direct: LDR $, STR $)
    --                  dm_addr_sel="01" uses Rz        (STR Rz Rx, STR Rz #)
    --                  dm_addr_sel="10" uses Rx        (LDR Rz Rx)
    -- Write data src : dm_data_sel="00" uses Rx        (STR Rx $, STR Rz Rx)
    --                  dm_data_sel="01" uses operand   (STR Rz #value)
    --                  dm_data_sel="10" uses PC        (STRC $address)
    DM : data_mem PORT
    MAP(
    address => dm_addr_sig,
    clock   => clk,
    data    => dm_data_sig,
    wren    => dm_wren,
    q       => dm_out_sig
    );

END ARCHITECTURE structural;
