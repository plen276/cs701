LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

LIBRARY altera_mf;
USE altera_mf.ALL;

-- ============================================================
-- prog_mem_dp  -- dual-port program memory for GP-2 W6
--
-- Replaces the ROM-mode prog_mem used in GP-1/earlier GP-2.
-- Port A: read-only (ReCOP instruction fetch, same interface
--         as the original prog_mem).
-- Port B: write-only (reconfiguration node writes new program
--         words without resynthesis).
--
-- A single clock (clock0) drives both ports.
-- Both ports address the same underlying 32 768 x 16-bit memory,
-- initialised from the assembled .mif on power-up.
--
-- read_during_write_mode_mixed_ports => "DONT_CARE": the result
-- is unspecified if port A reads an address that port B is
-- simultaneously writing.  In practice reconfig only happens
-- while ReCOP is held in reset, so this never occurs.
-- ============================================================

ENTITY prog_mem_dp IS
    PORT
    (
        clock     : IN  STD_LOGIC := '1';
        -- Port A: read (ReCOP fetch)
        address_a : IN  STD_LOGIC_VECTOR(14 DOWNTO 0);
        q_a       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        -- Port B: write (reconfig node)
        address_b : IN  STD_LOGIC_VECTOR(14 DOWNTO 0);
        data_b    : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
        wren_b    : IN  STD_LOGIC
    );
END ENTITY prog_mem_dp;

ARCHITECTURE syn OF prog_mem_dp IS

    SIGNAL sub_wire_qa : STD_LOGIC_VECTOR(15 DOWNTO 0);

    COMPONENT altsyncram
        GENERIC
        (
            address_reg_b                      : STRING;
            clock_enable_input_a               : STRING;
            clock_enable_input_b               : STRING;
            clock_enable_output_a              : STRING;
            clock_enable_output_b              : STRING;
            indata_reg_b                       : STRING;
            init_file                          : STRING;
            intended_device_family             : STRING;
            lpm_hint                           : STRING;
            lpm_type                           : STRING;
            numwords_a                         : NATURAL;
            numwords_b                         : NATURAL;
            operation_mode                     : STRING;
            outdata_aclr_a                     : STRING;
            outdata_reg_a                      : STRING;
            outdata_reg_b                      : STRING;
            ram_block_type                     : STRING;
            read_during_write_mode_mixed_ports : STRING;
            widthad_a                          : NATURAL;
            widthad_b                          : NATURAL;
            width_a                            : NATURAL;
            width_b                            : NATURAL;
            width_byteena_a                    : NATURAL;
            width_byteena_b                    : NATURAL;
            wrcontrol_wraddress_reg_b          : STRING
        );
        PORT
        (
            clock0    : IN  STD_LOGIC;
            address_a : IN  STD_LOGIC_VECTOR(14 DOWNTO 0);
            data_a    : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
            wren_a    : IN  STD_LOGIC;
            q_a       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            address_b : IN  STD_LOGIC_VECTOR(14 DOWNTO 0);
            data_b    : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
            wren_b    : IN  STD_LOGIC;
            q_b       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

BEGIN

    q_a <= sub_wire_qa;

    altsyncram_component : altsyncram
    GENERIC MAP
    (
        address_reg_b                      => "CLOCK0",
        clock_enable_input_a               => "BYPASS",
        clock_enable_input_b               => "BYPASS",
        clock_enable_output_a              => "BYPASS",
        clock_enable_output_b              => "BYPASS",
        indata_reg_b                       => "CLOCK0",
        init_file                          => "./assembler/test.mif",
        intended_device_family             => "Cyclone V",
        lpm_hint                           => "ENABLE_RUNTIME_MOD=NO",
        lpm_type                           => "altsyncram",
        numwords_a                         => 32768,
        numwords_b                         => 32768,
        operation_mode                     => "BIDIR_DUAL_PORT",
        outdata_aclr_a                     => "NONE",
        outdata_reg_a                      => "UNREGISTERED",
        outdata_reg_b                      => "UNREGISTERED",
        ram_block_type                     => "M10K",
        read_during_write_mode_mixed_ports => "DONT_CARE",
        widthad_a                          => 15,
        widthad_b                          => 15,
        width_a                            => 16,
        width_b                            => 16,
        width_byteena_a                    => 1,
        width_byteena_b                    => 1,
        wrcontrol_wraddress_reg_b          => "CLOCK0"
    )
    PORT MAP
    (
        clock0    => clock,
        address_a => address_a,
        data_a    => (OTHERS => '0'),
        wren_a    => '0',
        q_a       => sub_wire_qa,
        address_b => address_b,
        data_b    => data_b,
        wren_b    => wren_b,
        q_b       => OPEN
    );

END ARCHITECTURE syn;
