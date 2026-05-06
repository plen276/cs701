LIBRARY ieee;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.TdmaMinTypes.ALL;

ENTITY DpAsp IS
    PORT
    (
        clock : IN STD_LOGIC;
        key   : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        send  : OUT tdma_min_port;
        recv  : IN tdma_min_port
    );
END ENTITY;

ARCHITECTURE rtl OF DpAsp IS
    SIGNAL avg_ch0 : signed(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL avg_ch1 : signed(15 DOWNTO 0) := (OTHERS => '0');
BEGIN

    PROCESS (clock)
        -- separate shift registers per channel: s0 = newest, s3 = oldest
        VARIABLE s0_0, s1_0, s2_0, s3_0 : signed(15 DOWNTO 0) := (OTHERS => '0');
        VARIABLE s0_1, s1_1, s2_1, s3_1 : signed(15 DOWNTO 0) := (OTHERS => '0');
        VARIABLE sum                    : signed(17 DOWNTO 0);
        VARIABLE avg_v                  : signed(15 DOWNTO 0);
        VARIABLE result                 : signed(16 DOWNTO 0);
    BEGIN
        IF rising_edge(clock) THEN
            IF recv.data(31 DOWNTO 28) = "1000" THEN

                IF recv.data(16) = '0' THEN
                    -- channel 0
                    s3_0  := s2_0;
                    s2_0  := s1_0;
                    s1_0  := s0_0;
                    s0_0  := signed(recv.data(15 DOWNTO 0));

                    sum   := resize(s0_0, 18) + resize(s1_0, 18) + resize(s2_0, 18) + resize(s3_0, 18);
                    avg_v := signed(sum(17 DOWNTO 2));
                    avg_ch0 <= avg_v;
                ELSE
                    -- channel 1
                    s3_1  := s2_1;
                    s2_1  := s1_1;
                    s1_1  := s0_1;
                    s0_1  := signed(recv.data(15 DOWNTO 0));

                    sum   := resize(s0_1, 18) + resize(s1_1, 18) + resize(s2_1, 18) + resize(s3_1, 18);
                    avg_v := signed(sum(17 DOWNTO 2));
                    avg_ch1 <= avg_v;
                END IF;

                -- double the average, then clip |result| to 4096
                result := resize(avg_v, 17) + resize(avg_v, 17);
                IF result > to_signed(4096, 17) THEN
                    result := to_signed(4096, 17);
                ELSIF result < to_signed(-4096, 17) THEN
                    result := to_signed(-4096, 17);
                END IF;

                -- forward to DAC-ASP at port 1, unless muted by key
                IF (recv.data(16) = '0' AND key(2) = '0') OR
                    (recv.data(16) = '1' AND key(1) = '0') THEN
                    send.addr <= (OTHERS => '0');
                    send.data <= (OTHERS => '0');
                ELSE
                    send.addr <= x"01";
                    send.data <= "100000000000000" & recv.data(16) & STD_LOGIC_VECTOR(result(15 DOWNTO 0));
                END IF;
            ELSE
                send.addr <= (OTHERS => '0');
                send.data <= (OTHERS => '0');
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
