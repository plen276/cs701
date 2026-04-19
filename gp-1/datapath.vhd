LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

ENTITY datapath IS
    PORT (
        clk           : IN  bit_1;
        reset         : IN  bit_1;

        -- From Control Unit: fetch control
        pc_load       : IN  bit_1;   -- load OPR into PC (jumps)
        ir_load       : IN  bit_1;   -- latch PM output into IR[31:16]
        op_load       : IN  bit_1;   -- latch PM output into IR[15:0] and OPR

        -- From Control Unit: ALU control
        alu_operation : IN  bit_3;
        alu_op1_sel   : IN  bit_2;
        alu_op2_sel   : IN  bit_1;

        -- From Control Unit: register file control
        rf_input_sel  : IN  bit_3;
        ld_r          : IN  bit_1;

        -- From Control Unit: data memory control
        dm_wren       : IN  bit_1;

        -- From Control Unit: flag control
        clr_z_flag    : IN  bit_1;   -- CLFZ: clear zero flag

        -- To Control Unit: status and decode
        opcode        : OUT bit_6;   -- IR[29:24]
        am            : OUT bit_2;   -- IR[31:30]
        z_flag        : OUT bit_1;
		  
		  -- To Debugger
		  debug_pc      : OUT bit_16;
		  debug_ir      : OUT bit_16
    );
END ENTITY datapath;

ARCHITECTURE structural OF datapath IS

    -- ===== Fetch registers =====
    SIGNAL pc  : bit_16 := (OTHERS => '0');
    SIGNAL ir  : bit_32 := (OTHERS => '0');
    SIGNAL opr : bit_16 := (OTHERS => '0');

    -- Program memory output (std_logic_vector to match prog_mem port)
    SIGNAL pm_q : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- Register selects decoded from IR fields
    SIGNAL sel_z_i : INTEGER RANGE 0 TO 15;
    SIGNAL sel_x_i : INTEGER RANGE 0 TO 15;

    -- ===== Datapath signals =====
    SIGNAL rx_sig      : bit_16;
    SIGNAL rz_sig      : bit_16;
    SIGNAL alu_out_sig : bit_16;
    SIGNAL dm_out_sig  : bit_16;

    -- Unused regfile inputs tied to safe defaults
    SIGNAL rz_max_sig   : bit_16 := X"0000";
    SIGNAL sip_hold_sig : bit_16 := X"0000";
    SIGNAL er_temp_sig  : bit_1  := '0';

    -- ===== Component declarations =====

    COMPONENT prog_mem IS
        PORT (
            address : IN  STD_LOGIC_VECTOR(14 DOWNTO 0);
            clock   : IN  STD_LOGIC;
            q       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT regfile IS
        PORT (
            clk          : IN  bit_1;
            init         : IN  bit_1;
            ld_r         : IN  bit_1;
            sel_z        : IN  INTEGER RANGE 0 TO 15;
            sel_x        : IN  INTEGER RANGE 0 TO 15;
            rx           : OUT bit_16;
            rz           : OUT bit_16;
            rf_input_sel : IN  bit_3;
            ir_operand   : IN  bit_16;
            dm_out       : IN  bit_16;
            aluout       : IN  bit_16;
            rz_max       : IN  bit_16;
            sip_hold     : IN  bit_16;
            er_temp      : IN  bit_1;
            r7           : OUT bit_16;
            dprr_res     : IN  bit_1;
            dprr_res_reg : IN  bit_1;
            dprr_wren    : IN  bit_1
        );
    END COMPONENT;

    COMPONENT alu IS
        PORT (
            clk           : IN  bit_1;
            z_flag        : OUT bit_1;
            alu_operation : IN  bit_3;
            alu_op1_sel   : IN  bit_2;
            alu_op2_sel   : IN  bit_1;
            alu_carry     : IN  bit_1;
            alu_result    : OUT bit_16;
            rx            : IN  bit_16;
            rz            : IN  bit_16;
            ir_operand    : IN  bit_16;
            clr_z_flag    : IN  bit_1;
            reset         : IN  bit_1
        );
    END COMPONENT;

    COMPONENT data_mem IS
        PORT (
            address : IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
            clock   : IN  STD_LOGIC;
            data    : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
            wren    : IN  STD_LOGIC;
            q       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    -- ===== Combinatorial decode of IR fields =====
    opcode  <= ir(29 DOWNTO 24);
    am      <= ir(31 DOWNTO 30);
    sel_z_i <= to_integer(unsigned(ir(23 DOWNTO 20)));
    sel_x_i <= to_integer(unsigned(ir(19 DOWNTO 16)));

    -- ===== PC / IR / OPR register process =====
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                pc  <= (OTHERS => '0');
                ir  <= (OTHERS => '0');
                opr <= (OTHERS => '0');
            ELSIF pc_load = '1' THEN
                -- Jump: overwrite PC with operand
                pc <= opr;
            ELSIF ir_load = '1' THEN
                -- FETCH_1: load upper half of IR, advance PC
                ir(31 DOWNTO 16) <= pm_q;
                pc <= STD_LOGIC_VECTOR(unsigned(pc) + 1);
            ELSIF op_load = '1' THEN
                -- FETCH_2: load lower half of IR and OPR, advance PC
                ir(15 DOWNTO 0) <= pm_q;
                opr              <= pm_q;
                pc <= STD_LOGIC_VECTOR(unsigned(pc) + 1);
            END IF;
				debug_pc <= pc;
				debug_ir <= ir(31 DOWNTO 0);
        END IF;
    END PROCESS;

    -- ===== Component instantiations =====

    -- Program Memory
    PM : prog_mem PORT MAP (
        address => pc(14 DOWNTO 0),
        clock   => clk,
        q       => pm_q
    );

    -- Register File
    -- ir_operand fed from OPR (replaces Lab 0 external ir_operand port)
    -- sel_z / sel_x decoded from IR fields (replaces Lab 0 external sel_z / sel_x ports)
    RF : regfile PORT MAP (
        clk          => clk,
        init         => reset,
        ld_r         => ld_r,
        sel_z        => sel_z_i,
        sel_x        => sel_x_i,
        rx           => rx_sig,
        rz           => rz_sig,
        rf_input_sel => rf_input_sel,
        ir_operand   => opr,
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

    -- ALU
    -- ir_operand fed from OPR
    ALU_INST : alu PORT MAP (
        clk           => clk,
        z_flag        => z_flag,
        alu_operation => alu_operation,
        alu_op1_sel   => alu_op1_sel,
        alu_op2_sel   => alu_op2_sel,
        alu_carry     => '0',
        alu_result    => alu_out_sig,
        rx            => rx_sig,
        rz            => rz_sig,
        ir_operand    => opr,
        clr_z_flag    => clr_z_flag,
        reset         => reset
    );

    -- Data Memory
    -- address from OPR (replaces Lab 0 external dm_address port)
    -- write data is always Rx (STR instruction)
    DM : data_mem PORT MAP (
        address => opr(11 DOWNTO 0),
        clock   => clk,
        data    => rx_sig,
        wren    => dm_wren,
        q       => dm_out_sig
    );

END ARCHITECTURE structural;
