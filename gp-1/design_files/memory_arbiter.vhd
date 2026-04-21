-- Zoran Salcic

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;

USE work.recop_types.ALL;

ENTITY memory_arbiter IS
	PORT
	(
		--Signals from master
		master_address : IN bit_16;  --Master address to read/write
		master_data    : IN bit_16;  --Master data to write
		master_we      : IN bit_1;   --Master write enable bit
		master_en      : IN bit_1;   --Master enable bit, used by the master to control the memory

		--Signals from recop
		recop_address  : IN bit_16;  --Recop address
		recop_data     : IN bit_16;  --Recop data
		recop_we       : IN bit_1;   --Recop write enable
		recop_grant    : OUT bit_1;  --Recop grant signal, indicates the recop has access to the memory

		--Signals to memory
		memory_address : OUT bit_16; --Memory address to read/write
		memory_data    : OUT bit_16; --Memory data to write
		memory_we      : OUT bit_1;  --Memory write enable bit

		clk            : IN bit_1;   --Clock input
		reset          : IN bit_1    --Reset input (doesn't do much as this is largely combinational logic)
	);
END memory_arbiter;

ARCHITECTURE behaviour OF memory_arbiter IS

BEGIN

	update : PROCESS (clk, reset)
	BEGIN

		IF (reset = '1') THEN  --To reset, set WE low so no data is written, set the address and data to 0

			memory_we      <= '0'; --TODO: check that we is active high
			memory_address <= "0000000000000000";
			memory_data    <= "0000000000000000";
			recop_grant    <= '0';

		ELSIF (RISING_EDGE(clk)) THEN

			IF (master_en = '1') THEN --If the master wishes to use it, pass through the master signals
				memory_we      <= master_we;
				memory_address <= master_address;
				memory_data    <= master_data;
				recop_grant    <= '0'; --Indicate to the Recop that it doesn't have control
			ELSE
				memory_we      <= recop_we; --Else, pass the recop signals to the memory
				memory_address <= recop_address;
				memory_data    <= recop_data;
				recop_grant    <= '1'; --And let it know
			END IF;

		END IF;

	END PROCESS update;

END behaviour;
