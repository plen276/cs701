-- Zoran Salcic

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

USE IEEE.numeric_std.ALL;

USE work.recop_types.ALL;
USE work.various_constants.ALL;

ENTITY regfile IS
	PORT
	(
		clk          : IN bit_1;
		init         : IN bit_1;
		-- control signal to allow data to write into Rz
		ld_r         : IN bit_1;
		-- Rz and Rx select signals
		sel_z        : IN INTEGER RANGE 0 TO 15;
		sel_x        : IN INTEGER RANGE 0 TO 15;
		-- register data outputs
		rx           : OUT bit_16;
		rz           : OUT bit_16;
		-- select signal for input data to be written into Rz
		rf_input_sel : IN bit_3;
		-- input data
		ir_operand   : IN bit_16;
		dm_out       : IN bit_16;
		aluout       : IN bit_16;
		rz_max       : IN bit_16;
		sip_hold     : IN bit_16;
		er_temp      : IN bit_1;
		-- R7 for writing to lower byte of dpcr
		r7           : OUT bit_16;
		dprr_res     : IN bit_1;
		dprr_res_reg : IN bit_1;
		dprr_wren    : IN bit_1

	);
END regfile;

ARCHITECTURE beh OF regfile IS
	TYPE reg_array IS ARRAY (15 DOWNTO 0) OF bit_16;
	SIGNAL regs         : reg_array;
	SIGNAL data_input_z : bit_16;
BEGIN
	r7 <= regs(7);

	-- mux selecting input data to be written to Rz
	input_select : PROCESS (rf_input_sel, ir_operand, dm_out, aluout, rz_max, sip_hold, er_temp, dprr_res_reg)
	BEGIN
		CASE rf_input_sel IS
			WHEN "000" =>
				data_input_z <= ir_operand;
			WHEN "001" =>
				data_input_z <= X"000" & "000" & dprr_res_reg;
			WHEN "011" =>
				data_input_z <= aluout;
			WHEN "100" =>
				data_input_z <= rz_max;
			WHEN "101" =>
				data_input_z <= sip_hold;
			WHEN "110" =>
				data_input_z <= X"000" & "000" & er_temp;
			WHEN "111" =>
				data_input_z <= dm_out;
			WHEN OTHERS =>
				data_input_z <= X"0000";
		END CASE;
	END PROCESS input_select;

	PROCESS (clk, init)
	BEGIN
		IF init = '1' THEN
			regs <= ((OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'), (OTHERS => '0'));
		ELSIF rising_edge(clk) THEN
			-- write data into Rz if ld signal is asserted
			IF ld_r = '1' THEN
				regs(sel_z) <= data_input_z;
			ELSIF dprr_wren = '1' THEN
				regs(0) <= X"000" & "000" & dprr_res;
			END IF;
		END IF;
	END PROCESS;
	rx <= regs(sel_x);
	rz <= regs(sel_z);
END beh;
