LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

-- ============================================================
-- Datapath (GP1, fixed) with memory-mapped I/O.
--
-- Changes vs. original:
--   * Instruction field extraction aligned with MrASM encoding:
--       opcode = IR[31:26], am = IR[25:24].
--   * MMIO attached to the LDR/STR direct path.  When
--     OPR[11:8] = "1111", the dm_out mux returns the MMIO read
--     register and the write enable is routed to MMIO registers
--     instead of data_mem.
--
--   MMIO map (12-bit physical, decoded from opr[11:0]):
--     0xF00 .. 0xF05  HEX0..HEX5 (W)   low 4 bits
--     0xF10           LEDR       (W)   low 10 bits
--     0xF20           SW         (R)   low 10 bits
--     0xF21           KEY        (R)   low 4 bits (active-high:
--                                      bit i = NOT KEY(i))
-- ============================================================

ENTITY datapath IS
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
        z_flag        : OUT bit_1;

        -- MMIO external interfaces
        sw_in         : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
        key_in        : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);  -- active-high (already inverted in recop_top)
        hex0_o        : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        hex1_o        : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        hex2_o        : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        hex3_o        : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        hex4_o        : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        hex5_o        : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        ledr_o        : OUT STD_LOGIC_VECTOR(9 DOWNTO 0)
    );
END ENTITY datapath;

ARCHITECTURE structural OF datapath IS

    SIGNAL pc  : bit_16 := (OTHERS => '0');
    SIGNAL ir  : bit_32 := (OTHERS => '0');
    SIGNAL opr : bit_16 := (OTHERS => '0');

    SIGNAL pm_q : STD_LOGIC_VECTOR(15 DOWNTO 0);

    SIGNAL sel_z_i : INTEGER RANGE 0 TO 15;
    SIGNAL sel_x_i : INTEGER RANGE 0 TO 15;

    SIGNAL rx_sig      : bit_16;
    SIGNAL rz_sig      : bit_16;
    SIGNAL alu_out_sig : bit_16;
    SIGNAL dm_out_sig  : bit_16;
    SIGNAL dm_native_q : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- MMIO registers and glue
    SIGNAL is_mmio        : STD_LOGIC;
    SIGNAL dm_wren_native : STD_LOGIC;
    SIGNAL mmio_wren      : STD_LOGIC;
    SIGNAL mmio_rdata     : STD_LOGIC_VECTOR(15 DOWNTO 0);

    SIGNAL hex0_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    SIGNAL hex1_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    SIGNAL hex2_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    SIGNAL hex3_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    SIGNAL hex4_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    SIGNAL hex5_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";
    SIGNAL ledr_reg : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');

    SIGNAL rz_max_sig   : bit_16 := X"0000";
    SIGNAL sip_hold_sig : bit_16 := X"0000";
    SIGNAL er_temp_sig  : bit_1  := '0';

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

    -- ========== IR field decode (aligned with MrASM base layout) ==========
    opcode  <= ir(31 DOWNTO 26);
    am      <= ir(25 DOWNTO 24);
    sel_z_i <= to_integer(unsigned(ir(23 DOWNTO 20)));
    sel_x_i <= to_integer(unsigned(ir(19 DOWNTO 16)));

    -- ========== PC / IR / OPR register process ==========
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                pc  <= (OTHERS => '0');
                ir  <= (OTHERS => '0');
                opr <= (OTHERS => '0');
            ELSIF pc_load = '1' THEN
                pc <= opr;
            ELSIF ir_load = '1' THEN
                ir(31 DOWNTO 16) <= pm_q;
                pc <= STD_LOGIC_VECTOR(unsigned(pc) + 1);
            ELSIF op_load = '1' THEN
                ir(15 DOWNTO 0) <= pm_q;
                opr              <= pm_q;
                pc <= STD_LOGIC_VECTOR(unsigned(pc) + 1);
            END IF;
        END IF;
    END PROCESS;

    -- ========== MMIO decode ==========
    -- High nibble of the physical DM address selects MMIO vs. data memory.
    is_mmio        <= '1' WHEN opr(11 DOWNTO 8) = "1111" ELSE '0';
    dm_wren_native <= dm_wren AND NOT is_mmio;
    mmio_wren      <= dm_wren AND is_mmio;

    -- ========== MMIO write registers ==========
    mmio_wr : PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF reset = '1' THEN
                hex0_reg <= "1111";
                hex1_reg <= "1111";
                hex2_reg <= "1111";
                hex3_reg <= "1111";
                hex4_reg <= "1111";
                hex5_reg <= "1111";
                ledr_reg <= (OTHERS => '0');
            ELSIF mmio_wren = '1' THEN
                CASE opr(7 DOWNTO 0) IS
                    WHEN X"00" => hex0_reg <= rx_sig(3 DOWNTO 0);
                    WHEN X"01" => hex1_reg <= rx_sig(3 DOWNTO 0);
                    WHEN X"02" => hex2_reg <= rx_sig(3 DOWNTO 0);
                    WHEN X"03" => hex3_reg <= rx_sig(3 DOWNTO 0);
                    WHEN X"04" => hex4_reg <= rx_sig(3 DOWNTO 0);
                    WHEN X"05" => hex5_reg <= rx_sig(3 DOWNTO 0);
                    WHEN X"10" => ledr_reg <= rx_sig(9 DOWNTO 0);
                    WHEN OTHERS => NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS mmio_wr;

    hex0_o <= hex0_reg;
    hex1_o <= hex1_reg;
    hex2_o <= hex2_reg;
    hex3_o <= hex3_reg;
    hex4_o <= hex4_reg;
    hex5_o <= hex5_reg;
    ledr_o <= ledr_reg;

    -- ========== MMIO read mux ==========
    WITH opr(7 DOWNTO 0) SELECT
        mmio_rdata <= "000000" & sw_in              WHEN X"20",
                      X"000" & key_in               WHEN X"21",
                      X"000" & hex0_reg             WHEN X"00",
                      X"000" & hex1_reg             WHEN X"01",
                      X"000" & hex2_reg             WHEN X"02",
                      X"000" & hex3_reg             WHEN X"03",
                      X"000" & hex4_reg             WHEN X"04",
                      X"000" & hex5_reg             WHEN X"05",
                      "000000" & ledr_reg           WHEN X"10",
                      X"0000"                       WHEN OTHERS;

    dm_out_sig <= mmio_rdata WHEN is_mmio = '1' ELSE dm_native_q;

    -- ========== Components ==========

    PM : prog_mem PORT MAP (
        address => pc(14 DOWNTO 0),
        clock   => clk,
        q       => pm_q
    );

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

    DM : data_mem PORT MAP (
        address => opr(11 DOWNTO 0),
        clock   => clk,
        data    => rx_sig,
        wren    => dm_wren_native,
        q       => dm_native_q
    );

END ARCHITECTURE structural;
