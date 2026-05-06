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
    signal avg : signed(15 downto 0) := (others => '0');
begin

    process(clock)
        -- shift register: s0 = newest, s3 = oldest
        variable s0, s1, s2, s3 : signed(15 downto 0) := (others => '0');
        variable sum    : signed(17 downto 0);
        variable avg_v  : signed(15 downto 0);
        variable result : signed(16 downto 0);
    begin
        if rising_edge(clock) then
            if recv.data(31 downto 28) = "1000" then
                -- shift in new sample
                s3 := s2;
                s2 := s1;
                s1 := s0;
                s0 := signed(recv.data(15 downto 0));

                -- moving average of 4 samples (sum then divide by 4)
                sum   := resize(s0, 18) + resize(s1, 18) + resize(s2, 18) + resize(s3, 18);
                avg_v := signed(sum(17 downto 2));  -- arithmetic right shift by 2
                avg   <= avg_v;

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
