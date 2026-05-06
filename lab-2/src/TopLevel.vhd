LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY TopLevel IS
	GENERIC (
		ports : POSITIVE := 4
	);
	PORT
	(
		CLOCK_50      : IN STD_LOGIC;
		CLOCK2_50     : IN STD_LOGIC;
		CLOCK3_50     : IN STD_LOGIC;

		FPGA_I2C_SCLK : OUT STD_LOGIC;
		FPGA_I2C_SDAT : INOUT STD_LOGIC;
		AUD_ADCDAT    : IN STD_LOGIC;
		AUD_ADCLRCK   : INOUT STD_LOGIC;
		AUD_BCLK      : INOUT STD_LOGIC;
		AUD_DACDAT    : OUT STD_LOGIC;
		AUD_DACLRCK   : INOUT STD_LOGIC;
		AUD_XCK       : OUT STD_LOGIC;

		KEY           : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		SW            : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
		LEDR          : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
		HEX0          : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX1          : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX2          : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX3          : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX4          : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX5          : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF TopLevel IS

	SIGNAL clock     : STD_LOGIC;

	SIGNAL adc_empty : STD_LOGIC;
	SIGNAL adc_get   : STD_LOGIC;
	SIGNAL adc_data  : STD_LOGIC_VECTOR(16 DOWNTO 0);
	SIGNAL dac_full  : STD_LOGIC;
	SIGNAL dac_put   : STD_LOGIC;
	SIGNAL dac_data  : STD_LOGIC_VECTOR(16 DOWNTO 0);

	SIGNAL send_port : tdma_min_ports(0 TO ports - 1);
	SIGNAL recv_port : tdma_min_ports(0 TO ports - 1);

BEGIN

	clock <= CLOCK_50;

	adc_dac : ENTITY work.Audio
		GENERIC MAP(
			enable_adc => true
		)
		PORT MAP
		(
			ref_clock     => CLOCK3_50,
			fpga_i2c_sclk => FPGA_I2C_SCLK,
			fpga_i2c_sdat => FPGA_I2C_SDAT,
			aud_adcdat    => AUD_ADCDAT,
			aud_adclrck   => AUD_ADCLRCK,
			aud_bclk      => AUD_BCLK,
			aud_dacdat    => AUD_DACDAT,
			aud_daclrck   => AUD_DACLRCK,
			aud_xck       => AUD_XCK,

			clock         => clock,
			adc_empty     => adc_empty,
			adc_get       => adc_get,
			adc_data      => adc_data,
			dac_full      => dac_full,
			dac_put       => dac_put,
			dac_data      => dac_data
		);

	tdma_min : ENTITY work.TdmaMin
		GENERIC MAP(
			ports => ports
		)
		PORT
		MAP (
		clock => clock,
		sends => send_port,
		recvs => recv_port
		);

	asp_adc : ENTITY work.AspAdc
		PORT
		MAP (
		clock => clock,
		empty => adc_empty,
		get   => adc_get,
		data  => adc_data,

		send  => send_port(0),
		recv  => recv_port(0)
		);

	asp_dac : ENTITY work.AspDac
		PORT
		MAP (
		clock => clock,
		full  => dac_full,
		put   => dac_put,
		data  => dac_data,

		send  => send_port(1),
		recv  => recv_port(1)
		);

	asp_example : ENTITY work.AspExample
		PORT
		MAP (
		clock => clock,
		key   => KEY,
		sw    => SW,
		ledr  => LEDR,
		hex0  => HEX0,
		hex1  => HEX1,
		hex2  => HEX2,
		hex3  => HEX3,
		hex4  => HEX4,
		hex5  => HEX5,

		send  => send_port(2),
		recv  => recv_port(2)
		);

	dp_asp : ENTITY work.DpAsp
		PORT
		MAP (
		clock => clock,
		key   => KEY,
		send  => send_port(3),
		recv  => recv_port(3)
		);

END ARCHITECTURE;
