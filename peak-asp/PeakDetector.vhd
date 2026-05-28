library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity PeakDetector is
	port (
		clock : in std_logic;
		reset : in std_logic;
		addr : out std_logic_vector(7 downto 0);
		send : out std_logic_vector(31 downto 0);
		recv : in std_logic_vector(31 downto 0)
	);
end entity;

architecture beh of PeakDetector is

	-- Signals
	
	-- CU to BaseAdj
	signal base_reset : std_logic;
	signal base_conf : std_logic;
	signal base_rate : integer;
	signal base_ld : std_logic;
	signal base_in : std_logic_vector(15 downto 0);
	-- CU to FindPeak
	signal find_reset : std_logic;
	signal find_conf : std_logic;
	signal find_hysteresis : integer;
	signal find_ld : std_logic;
	signal find_in : std_logic_vector(15 downto 0);
	-- CU to Mem
	signal lifetime : integer;
	-- CU to Max_Mem
	signal max_reset : std_logic;
	signal max_conf : std_logic;
	signal max_sel_v : integer range 0 to 15;
	signal max_sel_a : integer range 0 to 15;
	-- CU to Min_Mem
	signal min_reset : std_logic;
	signal min_conf : std_logic;
	signal min_sel_v : integer range 0 to 15;
	signal min_sel_a : integer range 0 to 15;
	-- CU to Seq_Max
	signal seq_max_reset : std_logic;
	signal seq_max_ld : std_logic;
	signal seq_max_in : std_logic_vector(15 downto 0);
	-- CU to Seq_Min
	signal seq_min_reset : std_logic;
	signal seq_min_ld : std_logic;
	signal seq_min_in : std_logic_vector(15 downto 0);
	-- FindPeak to Mem
	signal max_wren : std_logic;
	signal min_wren : std_logic;
	signal find_out : std_logic_vector(15 downto 0);
	-- BaseAdj to FindPeak
	signal baseline : integer;
	-- Max_Mem to CU
	signal max_size : integer range 0 to 16;
	signal max_peak_time : integer;
	-- Max_Mem to SeqMax
	signal max_out_v : std_logic_vector(15 downto 0);
	-- Min_Mem to CU
	signal min_size : integer range 0 to 16;
	-- Min_Mem to SeqMin
	signal min_out_v : std_logic_vector(15 downto 0);
	-- Seq_Max to CU
	signal seq_max_out : std_logic_vector(15 downto 0);
	-- Seq_Min to CU
	signal seq_min_out : std_logic_vector(15 downto 0);
	-- Unused
	signal max_out_a : integer;
	signal min_out_a : integer;
	signal min_peak_time : integer;
	
	-- Components
	
	component ControlUnit is
		port (
			clock : in std_logic;
			reset : in std_logic;
			addr : out std_logic_vector(7 downto 0);
			send : out std_logic_vector(31 downto 0);
			recv : in std_logic_vector(31 downto 0);
			-- To BaseAdj
			base_reset : out std_logic;
			base_conf : out std_logic;
			base_rate : out integer;
			base_ld : out std_logic;
			base_in : out std_logic_vector(15 downto 0);
			-- To FindPeak
			find_reset : out std_logic;
			find_conf : out std_logic;
			find_hysteresis : out integer;
			find_ld : out std_logic;
			find_in : out std_logic_vector(15 downto 0);
			-- To Mem
			lifetime : out integer;
			-- To Max_Mem
			max_reset : out std_logic;
			max_conf : out std_logic;
			max_sel_v : out integer range 0 to 15;
			max_sel_a : out integer range 0 to 15;
			-- To Min_Mem
			min_reset : out std_logic;
			min_conf : out std_logic;
			min_sel_v : out integer range 0 to 15;
			min_sel_a : out integer range 0 to 15;
			-- To Seq_Max
			seq_max_reset : out std_logic;
			seq_max_ld : out std_logic;
			-- To Seq_Min
			seq_min_reset : out std_logic;
			seq_min_ld : out std_logic;
			-- From Max_Mem
			max_size : in integer range 0 to 16;
			peak_time : in integer;
			-- From Min_Mem
			min_size : in integer range 0 to 16;
			-- From Seq_Max
			seq_max_out : in std_logic_vector(15 downto 0);
			-- From Seq_Min
			seq_min_out : in std_logic_vector(15 downto 0)
		);
	end component;
	
	component BaseAdj is
		port (
			clock : in std_logic;
			reset : in std_logic;
			
			conf_en : in std_logic;
			set_adj_rate : in integer;
			
			ld_in : in std_logic;
			input : in std_logic_vector(15 downto 0);
			output : out integer
		);
	end component;
	
	component FindPeak is
		port (
			clock : in std_logic;
			reset : in std_logic;
			
			conf_en : in std_logic;
			set_hysteresis : in integer := 10;
			
			ld_en : in std_logic;
			baseline : in integer;
			input : in std_logic_vector(15 downto 0);
			
			out_max : out std_logic;
			out_min : out std_logic;
			output : out std_logic_vector(15 downto 0)
		);
	end component;
	
	component PkMem is
		port (
			clock : in std_logic;
			reset : in std_logic;
			
			conf_en : in std_logic;
			set_lifetime : in integer;
			
			wren : in std_logic;
			input : in std_logic_vector(15 downto 0);
			
			size : out integer range 0 to 16;
			select_v : in integer range 0 to 15;
			select_a : in integer range 0 to 15;
			output_v : out std_logic_vector(15 downto 0);
			output_a : out integer;
			output_a_avg : out integer
		);
	end component;
	
	component SeqMax is
		port (
			clock : in std_logic;
			reset : in std_logic;
			
			ld_in : in std_logic;
			input : in std_logic_vector(15 downto 0);
			
			output : out std_logic_vector(15 downto 0)
		);
	end component;
	
	component SeqMin is
		port (
			clock : in std_logic;
			reset : in std_logic;
			
			ld_in : in std_logic;
			input : in std_logic_vector(15 downto 0);
			
			output : out std_logic_vector(15 downto 0)
		);
	end component;
	
begin

	seq_max_in <= max_out_v;
	seq_min_in <= min_out_v;
	--reset <= reset;
	--send <= send;
	--recv <= recv;
	
	CU : ControlUnit
		port map (
			clock => clock,
			reset => reset,
			addr => addr,
			send => send,
			recv => recv,
			-- To BaseAdj
			base_reset => base_reset,
			base_conf => base_conf,
			base_rate => base_rate,
			base_ld => base_ld,
			base_in => base_in,
			-- To FindPeak
			find_reset => find_reset,
			find_conf => find_conf,
			find_hysteresis => find_hysteresis,
			find_ld => find_ld,
			find_in => find_in,
			-- To Mem
			lifetime => lifetime,
			-- To Max_Mem
			max_reset => max_reset,
			max_conf => max_conf,
			max_sel_v => max_sel_v,
			max_sel_a => max_sel_a,
			-- To Min_Mem
			min_reset => min_reset,
			min_conf => min_conf,
			min_sel_v => min_sel_v,
			min_sel_a => min_sel_a,
			-- To Seq_Max
			seq_max_reset => seq_max_reset,
			seq_max_ld => seq_max_ld,
			-- To Seq_Min
			seq_min_reset => seq_min_reset,
			seq_min_ld => seq_min_ld,
			-- From Max_Mem
			max_size => max_size,
			peak_time => max_peak_time,
			-- From Min_Mem
			min_size => min_size,
			-- From Seq_Max
			seq_max_out => seq_max_out,
			-- From Seq_Min
			seq_min_out => seq_min_out
		);
	
	Base_Adj : BaseAdj
		port map (
			clock => clock,
			reset => base_reset,
			
			conf_en => base_conf,
			set_adj_rate => base_rate,
			
			ld_in => base_ld,
			input => base_in,
			output => baseline
		);
	
	Find_Peak : FindPeak
		port map (
			clock => clock,
			reset => find_reset,
			
			conf_en => find_conf,
			set_hysteresis => find_hysteresis,
			
			ld_en => find_ld,
			baseline =>  baseline,
			input => find_in,
			
			out_max => max_wren,
			out_min => min_wren,
			output => find_out
		);
	
	Max_Mem : PkMem
		port map (
			clock => clock,
			reset => max_reset,
			
			conf_en => max_conf,
			set_lifetime => lifetime,
			
			wren => max_wren,
			input => find_out,
			
			size => max_size,
			select_v => max_sel_v,
			select_a => max_sel_a,
			output_v => max_out_v,
			output_a => max_out_a,
			output_a_avg => max_peak_time
		);
		
	Min_Mem : PkMem
		port map (
			clock => clock,
			reset => min_reset,
			
			conf_en => min_conf,
			set_lifetime => lifetime,
			
			wren => min_wren,
			input => find_out,
			
			size => min_size,
			select_v => min_sel_v,
			select_a => min_sel_a,
			output_v => min_out_v,
			output_a => min_out_a,
			output_a_avg => min_peak_time
		);
	
	Seq_Max : SeqMax
		port map (
			clock => clock,
			reset => seq_max_reset,
			
			ld_in => seq_max_ld,
			input => seq_max_in,
			
			output => seq_max_out
		);
	
	Seq_Min : SeqMin
		port map (
			clock => clock,
			reset => seq_min_reset,
			
			ld_in => seq_min_ld,
			input => seq_min_in,
			
			output => seq_min_out
		);
	
end architecture;