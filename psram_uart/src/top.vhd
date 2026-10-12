-- UART-to-PSRAM upload/readback 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity TOP is
  port (
    clk : in std_logic;
    reset_n : in std_logic;
    uart_rx : in std_logic;
    uart_tx : out std_logic;
    led : out std_logic_vector(1 downto 0);
    out_ch1 : out std_logic;
    out_ch2 : out std_logic;
    O_psram_ck : out std_logic_vector(1 downto 0);
    O_psram_ck_n : out std_logic_vector(1 downto 0);
    IO_psram_rwds : inout std_logic_vector(1 downto 0);
    O_psram_reset_n : out std_logic_vector(1 downto 0);
    IO_psram_dq : inout std_logic_vector(15 downto 0);
    O_psram_cs_n : out std_logic_vector(1 downto 0)
  );
end entity;
architecture RTL of TOP is
    component Gowin_rPLL
        port (
            clkout : out std_logic;
            lock   : out std_logic;
            clkin  : in  std_logic
        );
    end component;


    --------------------------------------------------------------------
    -- PSRAM component definition as supplied by the Gowin IP gen tool
    --------------------------------------------------------------------

    component PSRAM_Memory_Interface_HS_Top
        port (
            clk             : in    std_logic;
            rst_n           : in    std_logic;
            memory_clk      : in    std_logic;
            pll_lock        : in    std_logic;

            O_psram_ck      : out   std_logic_vector(1 downto 0);
            O_psram_ck_n    : out   std_logic_vector(1 downto 0);
            IO_psram_rwds   : inout std_logic_vector(1 downto 0);
            O_psram_reset_n : out   std_logic_vector(1 downto 0);
            IO_psram_dq     : inout std_logic_vector(15 downto 0);
            O_psram_cs_n    : out   std_logic_vector(1 downto 0);

            init_calib0     : out std_logic;
            init_calib1     : out std_logic;

            clk_out         : out std_logic;

            cmd0            : in std_logic;
            cmd1            : in std_logic;

            cmd_en0         : in std_logic;
            cmd_en1         : in std_logic;

            addr0           : in std_logic_vector(20 downto 0);
            addr1           : in std_logic_vector(20 downto 0);

            wr_data0        : in std_logic_vector(31 downto 0);
            wr_data1        : in std_logic_vector(31 downto 0);

            rd_data0        : out std_logic_vector(31 downto 0);
            rd_data1        : out std_logic_vector(31 downto 0);

            rd_data_valid0  : out std_logic;
            rd_data_valid1  : out std_logic;

            data_mask0      : in std_logic_vector(3 downto 0);
            data_mask1      : in std_logic_vector(3 downto 0)
        );
    end component;



  signal memory_clk, pll_lock, clk_out : std_logic;
  signal init_calib0, init_calib1 : std_logic;
  signal cmd0,cmd1,cmd_en0,cmd_en1 : std_logic := '0';
  signal addr0,addr1 : std_logic_vector(20 downto 0) := (others=>'0');
  signal wr_data0,wr_data1 : std_logic_vector(31 downto 0) := (others=>'0');
  signal rd_data0,rd_data1 : std_logic_vector(31 downto 0);
  signal rd_data_valid0,rd_data_valid1 : std_logic;
  signal data_mask0,data_mask1 : std_logic_vector(3 downto 0) := (others=>'0');
  constant TICKS : integer := 352; -- 40.5 MHz / 115200, rounded
  type rx_t is (RI,RS,RB,RP);
  type tx_t is (TI,TS,TB,TP);
  signal rx_state : rx_t := RI;
  signal tx_state : tx_t := TI;
  signal rx_meta,rx_sync : std_logic := '1';
  signal rx_count,tx_count : integer range 0 to TICKS-1 := 0;
  signal rx_idx,tx_idx : integer range 0 to 7 := 0;
  signal rx_shift,tx_shift : std_logic_vector(7 downto 0) := (others=>'0');
  signal tx_line : std_logic := '1';
  signal activity, error_flag : std_logic := '0';
  -- Request: 2 sync + 1 cmd + 1 channel + 4 index + 1 len + 32 data + 2 crc
  type bytes_t is array(0 to 43) of std_logic_vector(7 downto 0);
  signal req : bytes_t := (others=>(others=>'0'));
  signal rsp : bytes_t := (others=>(others=>'0'));
  signal rx_pos : integer range 0 to 43 := 0;
  signal req_size : integer range 0 to 43 := 0;
  signal rsp_size : integer range 0 to 44 := 0;
  signal rsp_pos : integer range 0 to 44 := 0;
  signal rsp_active : std_logic := '0';
  type engine_t is (COLLECT, VALIDATE, ISSUE_WRITE, WRITE_WAIT,
                    ISSUE_READ, READ_WAIT, PREP_REPLY, SEND_REPLY, WAIT_REPLY);
  signal engine : engine_t := COLLECT;
  signal selected_channel : integer range 0 to 1 := 0;
  signal selected_index : unsigned(16 downto 0) := (others=>'0');
  signal op : std_logic_vector(7 downto 0) := (others=>'0');
  signal result_code : std_logic_vector(7 downto 0) := (others=>'0');
  signal write_idx : integer range 0 to 7 := 0;
  signal read_idx : integer range 0 to 8 := 0;
  signal wait_count : integer range 0 to 4095 := 0;
  signal payload : std_logic_vector(255 downto 0) := (others=>'0');
  function crc_step(c : unsigned(15 downto 0); b : std_logic_vector(7 downto 0)) return unsigned is
    variable v : unsigned(15 downto 0) := c xor (resize(unsigned(b),16) sll 8);
  begin
    for i in 0 to 7 loop
      if v(15)='1' then v := (v sll 1) xor x"1021";
      else v := v sll 1; end if;
    end loop;
    return v;
  end;
  function word_at(v : std_logic_vector(255 downto 0); n : integer) return std_logic_vector is
  begin
    return v(n*32+31 downto n*32);
  end;
begin
  uart_tx <= tx_line;
  led(0) <= not activity;
  led(1) <= not error_flag;
  out_ch1 <= '0'; out_ch2 <= '0';
  data_mask0 <= (others=>'0'); data_mask1 <= (others=>'0');
    pll_inst : Gowin_rPLL
        port map (
            clkin  => clk,
            clkout => memory_clk,
            lock   => pll_lock
        );

    --------------------------------------------------------------------
    -- PSRAM controller
    --------------------------------------------------------------------

    -- this component instance was copy-pasted from the Gowin IP generator output
    psram_instance : PSRAM_Memory_Interface_HS_Top
        port map (
            clk             => clk,
            rst_n           => reset_n,
            memory_clk      => memory_clk,
            pll_lock        => pll_lock,

            O_psram_ck      => O_psram_ck,
            O_psram_ck_n    => O_psram_ck_n,
            IO_psram_rwds   => IO_psram_rwds,
            O_psram_reset_n => O_psram_reset_n,
            IO_psram_dq     => IO_psram_dq,
            O_psram_cs_n    => O_psram_cs_n,

            init_calib0     => init_calib0,
            init_calib1     => init_calib1,
            clk_out         => clk_out,

            cmd0            => cmd0,
            cmd1            => cmd1,
            cmd_en0         => cmd_en0,
            cmd_en1         => cmd_en1,
            addr0           => addr0,
            addr1           => addr1,
            wr_data0        => wr_data0,
            wr_data1        => wr_data1,
            rd_data0        => rd_data0,
            rd_data1        => rd_data1,
            rd_data_valid0  => rd_data_valid0,
            rd_data_valid1  => rd_data_valid1,
            data_mask0      => data_mask0,
            data_mask1      => data_mask1
        );


  process(clk_out,reset_n)
    variable got : boolean;
    variable b : std_logic_vector(7 downto 0);
    variable c : unsigned(15 downto 0);
    variable idx32 : unsigned(31 downto 0);
    variable n : integer;
    variable d : std_logic_vector(7 downto 0);
    variable reply_buf : bytes_t;
    variable reply_len : integer range 0 to 44;
  begin
    if reset_n='0' then
      rx_state<=RI; tx_state<=TI; rx_pos<=0; engine<=COLLECT;
      tx_line<='1'; cmd_en0<='0';cmd_en1<='0';cmd0<='0';cmd1<='0';
      rsp_active<='0'; error_flag<='0'; activity<='0';
    elsif rising_edge(clk_out) then
      rx_meta<=uart_rx; rx_sync<=rx_meta;
      got:=false; b:=(others=>'0');
      cmd_en0<='0';cmd_en1<='0';
      case rx_state is
        when RI => if rx_sync='0' then rx_count<=TICKS/2-1;rx_state<=RS;end if;
        when RS => if rx_count=0 then
          if rx_sync='0' then rx_count<=TICKS-1;rx_idx<=0;rx_state<=RB;
          else rx_state<=RI;end if;
          else rx_count<=rx_count-1;end if;
        when RB => if rx_count=0 then
          rx_shift(rx_idx)<=rx_sync;rx_count<=TICKS-1;
          if rx_idx=7 then rx_state<=RP;else rx_idx<=rx_idx+1;end if;
          else rx_count<=rx_count-1;end if;
        when RP => if rx_count=0 then
          if rx_sync='1' then got:=true;b:=rx_shift;activity<=not activity;end if;
          rx_state<=RI;
          else rx_count<=rx_count-1;end if;
      end case;
      case tx_state is
        when TI => tx_line<='1';
          if rsp_active='1' and rsp_pos<rsp_size then
            tx_shift<=rsp(rsp_pos);rsp_pos<=rsp_pos+1;
            tx_idx<=0;tx_line<='0';tx_count<=TICKS-1;tx_state<=TS;
          end if;
        when TS => if tx_count=0 then tx_line<=tx_shift(0);tx_count<=TICKS-1;tx_state<=TB;
                   else tx_count<=tx_count-1;end if;
        when TB => if tx_count=0 then tx_count<=TICKS-1;
          if tx_idx=7 then tx_line<='1';tx_state<=TP;
          else tx_idx<=tx_idx+1;tx_line<=tx_shift(tx_idx+1);end if;
          else tx_count<=tx_count-1;end if;
        when TP => if tx_count=0 then tx_state<=TI;else tx_count<=tx_count-1;end if;
      end case;
      case engine is
        when COLLECT =>
          if got then
            if rx_pos=0 then
              if b=x"A5" then req(0)<=b;rx_pos<=1;end if;
            elsif rx_pos=1 then
              if b=x"5A" then req(1)<=b;rx_pos<=2;
              elsif b=x"A5" then req(0)<=b;rx_pos<=1;
              else rx_pos<=0;end if;
            else
              req(rx_pos)<=b;
              if rx_pos=8 then
                if unsigned(b)>32 then rx_pos<=0;error_flag<='1';
                else req_size<=11+to_integer(unsigned(b));rx_pos<=9;end if;
              elsif rx_pos+1=req_size then rx_pos<=0;engine<=VALIDATE;
              else rx_pos<=rx_pos+1;end if;
            end if;
          end if;
        when VALIDATE =>
          c:=x"FFFF";
          for i in 0 to 40 loop
            if i<req_size-2 then c:=crc_step(c,req(i));end if;
          end loop;
          op<=req(2);
          selected_channel<=0;
          if req(3)=x"01" then selected_channel<=1;end if;
          idx32 := resize(unsigned(req(4)), 32) or
                   shift_left(resize(unsigned(req(5)), 32), 8) or
                   shift_left(resize(unsigned(req(6)), 32), 16) or
                   shift_left(resize(unsigned(req(7)), 32), 24);
          selected_index<=idx32(16 downto 0);
          result_code<=x"00";
          if c(7 downto 0) /= unsigned(req(req_size-2)) or
             c(15 downto 8) /= unsigned(req(req_size-1)) then result_code<=x"01";engine<=PREP_REPLY;
          elsif req(3)/=x"00" and req(3)/=x"01" then result_code<=x"02";engine<=PREP_REPLY;
          elsif idx32>to_unsigned(131071,32) then result_code<=x"02";engine<=PREP_REPLY;
          elsif (req(2)=x"01" and req(8)/=x"20") or
                (req(2)=x"02" and req(8)/=x"00") or
                (req(2)=x"03" and req(8)/=x"00") or
                (req(2)/=x"01" and req(2)/=x"02" and req(2)/=x"03") then
            result_code<=x"02";engine<=PREP_REPLY;
          elsif pll_lock='0' or init_calib0='0' or init_calib1='0' then
            result_code<=x"03";engine<=PREP_REPLY;
          elsif req(2)=x"03" then engine<=PREP_REPLY;
          else
            if req(2)=x"01" then
              for i in 0 to 31 loop payload(i*8+7 downto i*8)<=req(i+9);end loop;
              engine<=ISSUE_WRITE;
            else engine<=ISSUE_READ;end if;
          end if;
        when ISSUE_WRITE =>
          addr0<=std_logic_vector(selected_index & "0000");
          addr1<=std_logic_vector(selected_index & "0000");
          if selected_channel=0 then
            cmd0<='1';cmd_en0<='1';wr_data0<=word_at(payload,0);
          else cmd1<='1';cmd_en1<='1';wr_data1<=word_at(payload,0);end if;
          write_idx<=0;wait_count<=0;engine<=WRITE_WAIT;
        when WRITE_WAIT =>
          cmd0<='0';cmd1<='0';
          if write_idx<7 then
            if selected_channel=0 then wr_data0<=word_at(payload,write_idx+1);
            else wr_data1<=word_at(payload,write_idx+1);end if;
            write_idx<=write_idx+1;
          end if;
          if wait_count=31 then engine<=PREP_REPLY;
          else wait_count<=wait_count+1;end if;
        when ISSUE_READ =>
          addr0<=std_logic_vector(selected_index & "0000");
          addr1<=std_logic_vector(selected_index & "0000");
          if selected_channel=0 then cmd0<='0';cmd_en0<='1';
          else cmd1<='0';cmd_en1<='1';end if;
          read_idx<=0;wait_count<=0;engine<=READ_WAIT;
        when READ_WAIT =>
          if selected_channel=0 and rd_data_valid0='1' and read_idx<8 then
            payload(read_idx*32+31 downto read_idx*32)<=rd_data0;
            read_idx<=read_idx+1;
          elsif selected_channel=1 and rd_data_valid1='1' and read_idx<8 then
            payload(read_idx*32+31 downto read_idx*32)<=rd_data1;
            read_idx<=read_idx+1;
          end if;
          if read_idx=8 and wait_count>=19 then engine<=PREP_REPLY;
          elsif wait_count=4095 then result_code<=x"04";engine<=PREP_REPLY;
          else wait_count<=wait_count+1;end if;
        when PREP_REPLY =>
          -- Construct the *entire* response in one clock using a variable.
          -- CRC is calculated over exactly the bytes that will be transmitted.
          -- No signal assignment in this branch is read back to compute CRC.
          reply_buf := (others => (others => '0'));
          reply_buf(0) := x"5A";
          reply_buf(1) := x"A5";
          reply_buf(2) := op;
          reply_buf(3) := req(3);
          for i in 4 to 7 loop reply_buf(i) := req(i); end loop;
          reply_buf(8) := result_code;
          if op=x"02" and result_code=x"00" then
            reply_buf(9) := x"20";
            for i in 0 to 31 loop
              reply_buf(10+i) := payload(i*8+7 downto i*8);
            end loop;
            reply_len := 44;
          else
            reply_buf(9) := x"00";
            reply_len := 12;
          end if;
          c := x"FFFF";
          for i in 0 to 41 loop
            if i < reply_len-2 then
              c := crc_step(c, reply_buf(i));
            end if;
          end loop;
          reply_buf(reply_len-2) := std_logic_vector(c(7 downto 0));
          reply_buf(reply_len-1) := std_logic_vector(c(15 downto 8));
          rsp <= reply_buf;
          rsp_size <= reply_len;
          engine <= SEND_REPLY;
        when SEND_REPLY =>
          -- The buffer and CRC were registered in the previous cycle.
          rsp_pos <= 0;
          rsp_active <= '1';
          engine <= WAIT_REPLY;
        when WAIT_REPLY =>
          if rsp_pos=rsp_size and tx_state=TI then
            rsp_active <= '0';
            engine <= COLLECT;
          end if;
      end case;
    end if;
  end process;
end architecture;
