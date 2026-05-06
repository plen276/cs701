library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

library work;
use work.TdmaMinTypes.all;

entity DpAsp is
    port (
        clock : in  std_logic;
        send  : out tdma_min_port;
        recv  : in  tdma_min_port
    );
end entity;

architecture rtl of DpAsp is
    signal avg_ch0 : signed(15 downto 0) := (others => '0');
    signal avg_ch1 : signed(15 downto 0) := (others => '0');
begin

    process(clock)
        -- separate shift registers per channel: s0 = newest, s3 = oldest
        variable s0_0, s1_0, s2_0, s3_0 : signed(15 downto 0) := (others => '0');
        variable s0_1, s1_1, s2_1, s3_1 : signed(15 downto 0) := (others => '0');
        variable sum    : signed(17 downto 0);
        variable avg_v  : signed(15 downto 0);
        variable result : signed(16 downto 0);
    begin
        if rising_edge(clock) then
            if recv.data(31 downto 28) = "1000" then

                if recv.data(16) = '0' then
                    -- channel 0
                    s3_0 := s2_0;
                    s2_0 := s1_0;
                    s1_0 := s0_0;
                    s0_0 := signed(recv.data(15 downto 0));

                    sum   := resize(s0_0, 18) + resize(s1_0, 18) + resize(s2_0, 18) + resize(s3_0, 18);
                    avg_v := signed(sum(17 downto 2));
                    avg_ch0 <= avg_v;
                else
                    -- channel 1
                    s3_1 := s2_1;
                    s2_1 := s1_1;
                    s1_1 := s0_1;
                    s0_1 := signed(recv.data(15 downto 0));

                    sum   := resize(s0_1, 18) + resize(s1_1, 18) + resize(s2_1, 18) + resize(s3_1, 18);
                    avg_v := signed(sum(17 downto 2));
                    avg_ch1 <= avg_v;
                end if;

                -- double the average, then clip |result| to 4096
                result := resize(avg_v, 17) + resize(avg_v, 17);
                if result > to_signed(4096, 17) then
                    result := to_signed(4096, 17);
                elsif result < to_signed(-4096, 17) then
                    result := to_signed(-4096, 17);
                end if;

                -- forward to DAC-ASP at port 1, preserving channel bit
                send.addr <= x"01";
                send.data <= "100000000000000" & recv.data(16) & std_logic_vector(result(15 downto 0));
            else
                send.addr <= (others => '0');
                send.data <= (others => '0');
            end if;
        end if;
    end process;

end architecture;
