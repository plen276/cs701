-- Zoran Salcic

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;

USE work.recop_types.ALL;
USE work.opcodes.ALL;
USE work.various_constants.ALL;

ENTITY alu IS
	PORT
	(
		clk           : IN bit_1;
		z_flag        : OUT bit_1;
		-- ALU operation selection
		alu_operation : IN bit_3;
		-- operand selection
		alu_op1_sel   : IN bit_2;
		alu_op2_sel   : IN bit_1;
		alu_carry     : IN bit_1; --WARNING: carry in currently is not used
		alu_result    : OUT bit_16 := X"0000";
		-- operands
		rx            : IN bit_16;
		rz            : IN bit_16;
		ir_operand    : IN bit_16;
		-- flag control signal
		clr_z_flag    : IN bit_1;
		reset         : IN bit_1
	);
END alu;

ARCHITECTURE combined OF alu IS
	SIGNAL operand_1 : bit_16;
	SIGNAL operand_2 : bit_16;
	SIGNAL result    : bit_16;
BEGIN
	--MUX selecting first operand
	op1_select : PROCESS (alu_op1_sel, rx, ir_operand)
	BEGIN
		CASE alu_op1_sel IS
			WHEN "00" =>
				operand_1 <= rx;
			WHEN "01" =>
				operand_1 <= ir_operand;
			WHEN "10" => --not used currently
				operand_1 <= X"0001";
			WHEN OTHERS =>
				operand_1 <= X"0000";
		END CASE;
	END PROCESS op1_select;

	--MUX selecting second operand
	op2_select : PROCESS (alu_op2_sel, rx, rz)
	BEGIN
		CASE alu_op2_sel IS
			WHEN '0' =>
				operand_2 <= rx;
			WHEN '1' =>
				operand_2 <= rz;
			WHEN OTHERS =>
				operand_2 <= X"0000";
		END CASE;
	END PROCESS op2_select;

	-- perform ALU operation
	alu : PROCESS (alu_operation, operand_1, operand_2)
	BEGIN
		CASE alu_operation IS
			WHEN alu_add =>
				result <= operand_2 + operand_1;
			WHEN alu_sub =>
				result <= operand_2 - operand_1;
			WHEN alu_and =>
				result <= operand_2 AND operand_1;
			WHEN alu_or =>
				result <= operand_2 OR operand_1;
			WHEN OTHERS =>
				result <= X"0000";
		END CASE;
	END PROCESS alu;
	alu_result <= result;

	-- zero flag
	z1gen : PROCESS (clk)
	BEGIN
		IF reset = '1' THEN
			z_flag <= '0';
		ELSIF rising_edge(clk) THEN
			IF clr_z_flag = '1' THEN
				z_flag <= '0';
				-- if alu is working (operation is valid)
			ELSIF alu_operation(2) = '0' THEN
				IF result = X"0000" THEN
					z_flag <= '1';
				ELSE
					z_flag <= '0';
				END IF;
			END IF;
		END IF;
	END PROCESS z1gen;

END combined;
