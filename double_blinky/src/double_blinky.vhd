-----------------------------------
-- double blinky
-- rev 1 - shabaz - oct 2026
-----------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    port (
        led     : out STD_LOGIC_VECTOR(1 downto 0);
        clk     : in  STD_LOGIC;
        reset_n : in  STD_LOGIC
    );
end TOP;


architecture RTL of TOP is

    -- CONSTANTS
    constant CLK_FREQ_HZ     : integer := 27_000_000;
    constant MSEC_CONST      : integer := CLK_FREQ_HZ / 1000;
    constant LED_DELAY_CONST : integer := MSEC_CONST * 500;

    -- INTERNAL SIGNALS
    signal counter_reg : integer range 0 to LED_DELAY_CONST - 1 := 0;

    -- LEDs are active-low: '1' = off, '0' = on.
    -- Start with only the rightmost LED on.
    signal led_reg : STD_LOGIC_VECTOR(1 downto 0) := "10";

begin

    -- Continuously connect the internal LED register outputs to the LED signals
    led <= led_reg;

    -- this process will "do something" whenever there is a change on clk or reset_n
    blinky_process : process(clk, reset_n)
    begin
        if reset_n = '0' then
            -- Asynchronous logic on reset:
            counter_reg <= 0;  -- clear the counter_reg output
            led_reg <= "10";  -- set the LED register output to a known setting

        elsif rising_edge(clk) then
            -- On every rising edge of the 27 MHz clock
            -- i.e. every assignment here results in a clocked output,
            -- i.e. registers.
            if counter_reg = LED_DELAY_CONST - 1 then
                -- 500 ms worth of clock cycles have elapsed
                counter_reg <= 0;

                -- Concatenate the two bits in reverse order,
                -- effectively swapping the two LED states
                led_reg <= led_reg(0) & led_reg(1);

            else
                counter_reg <= counter_reg + 1;
            end if;
        end if;
    end process;

end RTL;
