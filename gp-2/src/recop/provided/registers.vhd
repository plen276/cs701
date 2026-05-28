-- Zoran Salcic

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;

USE work.recop_types.ALL;
USE work.opcodes.ALL;

-- various registers of recop
ENTITY registers IS
	PORT
	(
		clk          : IN bit_1;
		reset        : IN bit_1;
		dpcr         : OUT bit_32;
		r7           : IN bit_16;
		rx           : IN bit_16;
		ir_operand   : IN bit_16;
		dpcr_lsb_sel : IN bit_1;
		dpcr_wr      : IN bit_1;
		-- environment ready and set and clear signals
		er           : OUT bit_1;
		er_wr        : IN bit_1;
		er_clr       : IN bit_1;
		-- end of thread and set and clear signals
		eot          : OUT bit_1;
		eot_wr       : IN bit_1;
		eot_clr      : IN bit_1;
		-- svop and write enable signal
		svop         : OUT bit_16;
		svop_wr      : IN bit_1;
		-- sip souce and registered outputs
		sip_r        : OUT bit_16;
		sip          : IN bit_16;
		-- sop and write enable signal
		sop          : OUT bit_16;
		sop_wr       : IN bit_1;
		-- dprr, irq (dprr(1)) set and clear signals and result source and write enable signal
		dprr         : OUT bit_2;
		irq_wr       : IN bit_1;
		irq_clr      : IN bit_1;
		result_wen   : IN bit_1;
		result       : IN bit_1
	);
END registers;

ARCHITECTURE beh OF registers IS
BEGIN
	-- dpcr
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			dpcr <= X"00000000";
		ELSIF rising_edge(clk) THEN
			IF dpcr_wr = '1' THEN
				-- write to dpcr. lower byte depends on select signal
				CASE dpcr_lsb_sel IS
					WHEN '0' =>
						dpcr <= rx & r7;
					WHEN '1' =>
						dpcr <= rx & ir_operand;
					WHEN OTHERS =>
				END CASE;
			END IF;
		END IF;
	END PROCESS;

	-- er
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			er <= '0';
		ELSIF rising_edge(clk) THEN
			-- set or clear er
			IF er_wr = '1' THEN
				er <= '1';
			ELSIF er_clr = '1' THEN
				er <= '0';
			END IF;
		END IF;
	END PROCESS;

	-- eot
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			eot <= '0';
		ELSIF rising_edge(clk) THEN
			-- set or clear eot
			IF eot_wr = '1' THEN
				eot <= '1';
			ELSIF eot_clr = '1' THEN
				eot <= '0';
			END IF;
		END IF;
	END PROCESS;

	-- svop
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			svop <= X"0000";
		ELSIF rising_edge(clk) THEN
			IF svop_wr = '1' THEN
				-- write Rx into SVOP upon write signal 
				svop <= rx;
			END IF;
		END IF;
	END PROCESS;

	-- sip
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			sip_r <= X"0000";
		ELSIF rising_edge(clk) THEN
			-- register the sip signal with the system's clock
			sip_r <= sip;
		END IF;
	END PROCESS;

	-- sop
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			sop <= X"0000";
		ELSIF rising_edge(clk) THEN
			IF sop_wr = '1' THEN
				-- write Rx into SOP upon write signal 
				sop <= rx;
			END IF;
		END IF;
	END PROCESS;

	-- dprr: result
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			dprr(0) <= '0';
		ELSIF rising_edge(clk) THEN
			IF result_wen = '1' THEN
				-- write result upon write signal 
				dprr(0) <= result;
			END IF;
		END IF;
	END PROCESS;

	-- dprr: irq
	PROCESS (clk, reset)
	BEGIN
		IF reset = '1' THEN
			dprr(1) <= '1';
		ELSIF rising_edge(clk) THEN
			-- set or clear irq according to control signal
			IF irq_wr = '1' THEN
				dprr(1) <= '1';
			ELSIF irq_clr = '1' THEN
				dprr(1) <= '0';
			END IF;
		END IF;
	END PROCESS;
END beh;
