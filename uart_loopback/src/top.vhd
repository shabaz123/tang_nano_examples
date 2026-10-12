-- Tang Nano 9K onboard USB-UART loopback, VHDL-2008 compatible
-- 27 MHz oscillator, 115200 baud, 8N1, RX pin 18, TX pin 17.
-- Standalone test top: do not combine with the PSRAM top yet.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TOP is
    port (
        clk     : in  std_logic;
        uart_rx : in  std_logic;
        uart_tx : out std_logic;
        led     : out std_logic_vector(1 downto 0)
    );
end entity;

architecture rtl of TOP is
    constant CLOCK_HZ : integer := 27000000;
    constant BAUD     : integer := 115200;
    constant TICKS    : integer := (CLOCK_HZ + BAUD/2) / BAUD; -- 234
    type rx_state_t is (RX_IDLE, RX_START, RX_BITS, RX_STOP);
    type tx_state_t is (TX_IDLE, TX_START, TX_BITS, TX_STOP);
    signal rx_state : rx_state_t := RX_IDLE;
    signal tx_state : tx_state_t := TX_IDLE;
    signal rx_meta, rx_sync : std_logic := '1';
    signal rx_count : integer range 0 to TICKS-1 := 0;
    signal tx_count : integer range 0 to TICKS-1 := 0;
    signal rx_index, tx_index : integer range 0 to 7 := 0;
    signal rx_shift, tx_shift : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_line : std_logic := '1';
    signal pending : std_logic := '0';
    signal pending_data : std_logic_vector(7 downto 0) := (others => '0');
    signal activity : std_logic := '0';
    signal overflow : std_logic := '0';
begin
    uart_tx <= tx_line;
    led(0) <= not activity; -- active-low: toggles for each received byte
    led(1) <= not overflow; -- active-low: latched if one-byte queue overflows

    process(clk)
        variable got_byte : boolean;
        variable byte_value : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            -- Two flip-flop synchronization of asynchronous UART RX.
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
            got_byte := false;
            byte_value := (others => '0');

            case rx_state is
                when RX_IDLE =>
                    if rx_sync = '0' then
                        rx_count <= TICKS/2 - 1;
                        rx_state <= RX_START;
                    end if;
                when RX_START =>
                    if rx_count = 0 then
                        if rx_sync = '0' then
                            rx_count <= TICKS-1;
                            rx_index <= 0;
                            rx_state <= RX_BITS;
                        else
                            rx_state <= RX_IDLE; -- false start
                        end if;
                    else
                        rx_count <= rx_count-1;
                    end if;
                when RX_BITS =>
                    if rx_count = 0 then
                        rx_shift(rx_index) <= rx_sync; -- UART LSB first
                        rx_count <= TICKS-1;
                        if rx_index = 7 then
                            rx_state <= RX_STOP;
                        else
                            rx_index <= rx_index+1;
                        end if;
                    else
                        rx_count <= rx_count-1;
                    end if;
                when RX_STOP =>
                    if rx_count = 0 then
                        if rx_sync = '1' then
                            got_byte := true;
                            byte_value := rx_shift;
                            activity <= not activity;
                        end if;
                        rx_state <= RX_IDLE;
                    else
                        rx_count <= rx_count-1;
                    end if;
            end case;

            case tx_state is
                when TX_IDLE =>
                    tx_line <= '1';
                    if pending = '1' then
                        tx_shift <= pending_data;
                        pending <= '0';
                        tx_index <= 0;
                        tx_line <= '0';
                        tx_count <= TICKS-1;
                        tx_state <= TX_START;
                    end if;
                when TX_START =>
                    if tx_count = 0 then
                        tx_line <= tx_shift(0);
                        tx_count <= TICKS-1;
                        tx_state <= TX_BITS;
                    else
                        tx_count <= tx_count-1;
                    end if;
                when TX_BITS =>
                    if tx_count = 0 then
                        tx_count <= TICKS-1;
                        if tx_index = 7 then
                            tx_line <= '1';
                            tx_state <= TX_STOP;
                        else
                            tx_index <= tx_index+1;
                            tx_line <= tx_shift(tx_index+1);
                        end if;
                    else
                        tx_count <= tx_count-1;
                    end if;
                when TX_STOP =>
                    if tx_count = 0 then
                        tx_state <= TX_IDLE;
                    else
                        tx_count <= tx_count-1;
                    end if;
            end case;

            -- A single-byte elastic queue. Suitable for loopback at 115200:
            -- TX and RX take the same time, so back-to-back bytes are supported.
            if got_byte then
                if pending = '0' or (tx_state = TX_IDLE and pending = '1') then
                    pending_data <= byte_value;
                    pending <= '1';
                else
                    overflow <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
