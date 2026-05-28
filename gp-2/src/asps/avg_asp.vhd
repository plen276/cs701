LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

-- AVG-ASP: moving-average filter, window L in {4,8,16} selected by the
-- Conf-DP packet. Division is an arithmetic right shift by log2(L) (no
-- divider). A running sum keeps the per-sample cost at 1 add and 1
-- subtract regardless of L. Dual-channel. Drop-in NoC node (no reset /
-- NODE_ID; idle = all-zeros).
--
-- Conf-DP    "1001": 23-20 Next | 19-16 Mode (0000 bypass, 0001/0010/0011 L=4/8/16)
-- Data-Audio "1000": 27-24 Dest | 23-17 0 | 16 Ch | 15-0 signed sample

ENTITY avg_asp IS
	PORT
	(
		clock : IN STD_LOGIC;
		send  : OUT tdma_min_port;
		recv  : IN tdma_min_port
	);
END ENTITY;

ARCHITECTURE rtl OF avg_asp IS

	-- Packet protocol constants (named, single source of truth)
	CONSTANT TYPE_CONF_DP          : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1001";
	CONSTANT TYPE_DATA_AUDIO       : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1000";

	CONSTANT MODE_BYPASS           : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
	CONSTANT MODE_L4               : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";
	CONSTANT MODE_L8               : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0010";
	CONSTANT MODE_L16              : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0011";

	-- Build a Data-Audio payload:
	-- type(31:28) | Dest(27:24) | Reserved 0s(23:17) | Ch(16) | sample(15:0)
	FUNCTION make_data_audio (dest : STD_LOGIC_VECTOR(3 DOWNTO 0);
		ch                             : STD_LOGIC;
		sample                         : signed(15 DOWNTO 0))
		RETURN tdma_min_data IS
	BEGIN
		RETURN TYPE_DATA_AUDIO & dest & "0000000" & ch &
		STD_LOGIC_VECTOR(sample);
	END FUNCTION;

	-- Routing address for the NoC fabric: 8-bit, low nibble = node id.
	FUNCTION route_addr (dest : STD_LOGIC_VECTOR(3 DOWNTO 0))
		RETURN tdma_min_addr IS
	BEGIN
		RETURN "0000" & dest;
	END FUNCTION;

	-- Window is physically 16 deep regardless of L; only the first L
	-- taps are active. Index 0 = newest.
	TYPE win_t IS ARRAY(0 TO 15) OF signed(15 DOWNTO 0);

	-- Config shared by both channels.
	SIGNAL next_addr : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";
	SIGNAL l_len     : NATURAL RANGE 0 TO 16        := 4; -- 0 = bypass
	SIGNAL shamt     : NATURAL RANGE 0 TO 4         := 2;

BEGIN

	-- One Data-Audio packet arrives per clock (NoC-serialised), so a
	-- single process handles both channels without arbitration.
	-- A delivered packet is visible on recv.data for exactly one clock,
	-- so each sample is consumed exactly once.
	filter : PROCESS (clock)
		VARIABLE w0, w1     : win_t                 := (OTHERS => (OTHERS => '0'));
		VARIABLE sum0, sum1 : signed(20 DOWNTO 0)   := (OTHERS => '0');
		VARIABLE cnt0, cnt1 : NATURAL RANGE 0 TO 16 := 0;

		VARIABLE x          : signed(15 DOWNTO 0);
		VARIABLE leaving    : signed(15 DOWNTO 0);
		VARIABLE avg        : signed(15 DOWNTO 0);
		VARIABLE emit       : BOOLEAN;
	BEGIN
		IF rising_edge(clock) THEN

			IF recv.data(31 DOWNTO 28) = TYPE_CONF_DP THEN
				-- Latch dest + window and restart both channels. Only
				-- sum/cnt are cleared, not w0/w1 buffers: WARMUP refills L fresh
				-- samples before any leaving-tap is read, so stale window
				-- contents cannot affect a result.
				next_addr <= recv.data(23 DOWNTO 20);
				CASE recv.data(19 DOWNTO 16) IS
					WHEN MODE_L4 => l_len  <= 4;
						shamt                  <= 2;
					WHEN MODE_L8 => l_len  <= 8;
						shamt                  <= 3;
					WHEN MODE_L16 => l_len <= 16;
						shamt                  <= 4;
					WHEN OTHERS => l_len   <= 0;
						shamt                  <= 0; -- bypass
				END CASE;
				sum0 := (OTHERS => '0');
				cnt0 := 0;
				sum1 := (OTHERS => '0');
				cnt1 := 0;
				send.addr <= (OTHERS => '0');
				send.data <= (OTHERS => '0');

			ELSIF recv.data(31 DOWNTO 28) = TYPE_DATA_AUDIO THEN
				x    := signed(recv.data(15 DOWNTO 0));
				emit := false;

				IF l_len = 0 THEN
					-- Bypass: forward the sample unchanged.
					avg  := x;
					emit := true;

				ELSIF recv.data(16) = '0' THEN
					-- Channel 0
					IF cnt0 < l_len THEN
						-- WARMUP: accumulate until the first full window
						sum0 := sum0 + resize(x, sum0'length);
						cnt0 := cnt0 + 1;
						emit := (cnt0 = l_len); -- first full window
					ELSE
						leaving := w0(l_len - 1); -- sample leaving window
						sum0    := sum0 + resize(x, sum0'length)
							- resize(leaving, sum0'length);
						emit := true;
					END IF;
					FOR i IN 15 DOWNTO 1 LOOP w0(i) := w0(i - 1);
					END LOOP;
					w0(0) := x;
					avg   := resize(shift_right(sum0, shamt), 16);

				ELSE
					-- Channel 1
					IF cnt1 < l_len THEN
						sum1 := sum1 + resize(x, sum1'length);
						cnt1 := cnt1 + 1;
						emit := (cnt1 = l_len);
					ELSE
						leaving := w1(l_len - 1);
						sum1    := sum1 + resize(x, sum1'length)
							- resize(leaving, sum1'length);
						emit := true;
					END IF;
					FOR i IN 15 DOWNTO 1 LOOP w1(i) := w1(i - 1);
					END LOOP;
					w1(0) := x;
					avg   := resize(shift_right(sum1, shamt), 16);
				END IF;

				IF emit THEN
					send.addr <= route_addr(next_addr);
					send.data <= make_data_audio(next_addr, recv.data(16), avg);
				ELSE
					-- WARMUP: window not yet full, emit nothing.
					send.addr <= (OTHERS => '0');
					send.data <= (OTHERS => '0');
				END IF;

			ELSE
				send.addr <= (OTHERS => '0');
				send.data <= (OTHERS => '0');
			END IF;

		END IF;
	END PROCESS;

END ARCHITECTURE;
