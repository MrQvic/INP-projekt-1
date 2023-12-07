-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Adam Mrkva xmrkva04
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
    port (
      CLK   : in std_logic;  -- hodinovy signal
      RESET : in std_logic;  -- asynchronni reset procesoru
      EN    : in std_logic;  -- povoleni cinnosti procesoru
    
      -- synchronni pamet RAM
      DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
      DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
      DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
      DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
      DATA_EN    : out std_logic;                    -- povoleni cinnosti
      
      -- vstupni port
      IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
      IN_VLD    : in std_logic;                      -- data platna
      IN_REQ    : out std_logic;                     -- pozadavek na vstup data
      
      -- vystupni port
      OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
      OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
      OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
   
      -- stavove signaly
      READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
      DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
    );
   end cpu;

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

--PC
signal pc_out   : std_logic_vector (12 downto 0);
signal pc_inc   : std_logic;
signal pc_dec   : std_logic;

--PTR
signal ptr_out  : std_logic_vector (12 downto 0);
signal ptr_inc  : std_logic;
signal ptr_dec  : std_logic;

--MUX1
signal mx1_select: std_logic;

--MUX2
signal mx2_select: std_logic_vector (1 downto 0);

--FSM
type fsm_states is (
    s_start, s_init, s_initready, s_ready, s_fetch, s_decode, 
    s_valinc_begin, s_valdec_begin, s_valdec_ready, s_valdec, s_valinc_ready, s_valinc,
    s_print_setup, s_print, s_input_setup, s_input, s_null
);
signal current_state: fsm_states := s_start;
signal next_state: fsm_states;

begin
    --PC
    PC: process (CLK, RESET, pc_inc, pc_dec)
    begin
        if(RESET = '1') then
            pc_out <= (others => '0');  -- Reset hodnoty pc na nulu
        elsif(rising_edge(CLK)) then
            if pc_inc = '1' then
                pc_out <= (pc_out + 1);  -- Přičítání hodnoty
            elsif pc_dec = '1' then
                pc_out <= (pc_out - 1);  -- Odečítání hodnoty
            end if;
        end if;
    end process;

    --PTR
    PTR: process (CLK, RESET, ptr_inc, ptr_dec)
    begin
        if(RESET = '1') then
            ptr_out <= (others => '0');  -- Reset hodnoty ptr na nulu
        elsif(rising_edge(CLK)) then
            if ptr_inc = '1' then
                ptr_out <= ptr_out + 1;  -- Přičti
            elsif ptr_dec = '1' then
                ptr_out <= ptr_out - 1;  -- Odečti
            end if;
        end if;
    end process;

    --MX1
    MX1: process(CLK, RESET, mx1_select)
        begin
            if(RESET = '1') then
                DATA_ADDR <= (others => '0');   -- Reset vynuluje výstup
            elsif rising_edge(CLK) then
                if mx1_select = '0' then
                    DATA_ADDR <= ptr_out;   -- Použij ptr hodnotu
                else
                    DATA_ADDR <= pc_out;    -- Použij pc hodnotu
                end if;
            end if;
        end process;

    --MX2
    MX2: process (CLK, RESET, mx2_select)
    begin
        if(RESET = '1') then 
            DATA_WDATA <= (others => '0');
        elsif(rising_edge(CLK)) then
            case mx2_select is
                when "00" =>    DATA_WDATA <= IN_DATA;
                when "01" =>    DATA_WDATA <= DATA_RDATA - 1;
                when "10" =>    DATA_WDATA <= DATA_RDATA + 1;
                when others =>  DATA_WDATA <= (others => '0');
            end case;
        end if;
    end process;

    --FSM
    fsm_states_logic: process(CLK, RESET, EN)
    begin 
        if(RESET = '1') then
            current_state <= s_start;
        elsif(rising_edge(CLK)) then
            current_state <= next_state;
        end if;
    end process;

    fsm_main: process(current_state, IN_VLD, OUT_BUSY, EN, DATA_RDATA)
    begin
        DATA_EN		<= '0';
        DATA_RDWR 	<= '0';
        DONE        <= '0';
        IN_REQ	  	<= '0';
        OUT_WE	  	<= '0';
        pc_inc		<= '0';
        pc_dec		<= '0';
        ptr_inc		<= '0';
        ptr_dec		<= '0';
        mx2_select  <= "00";
        mx1_select <= '1';
        
        case current_state is
            when s_start =>
                READY <= '0';
                mx1_select <= '0';
                next_state <= s_init;

            when s_init =>
                DATA_EN <= '1';                 --povoleni nacitani dat
                mx1_select <= '0';
                next_state <= s_initready;

            when s_initready =>                 
                ptr_inc <= '1';
                case DATA_RDATA is              --procházej data dokud @
                    when X"40" =>               
                        ptr_inc <= '0';         --data prochazi pomoci ptr hodnoty, ptr nastaven na x+1
                        next_state <= s_ready;  
                    when others =>
                        next_state <= s_init;
                        mx1_select <= '0';
                end case;

            when s_ready =>
                READY <= '1';                  --inicializace probehla
                next_state <= s_fetch;
                
            when s_fetch =>                     --načítej data přes pc
                DATA_EN <= '1';
                mx1_select <= '1';
                next_state <= s_decode;

            when s_decode =>                        --identifikace prichozi instrukce
                case DATA_RDATA is
                    when X"40" =>                   -- "@" @ na vstupu, ukonči činnost programu DONE
                        DONE <= '1';

                    when X"3E"	=>                  -- ">" inkrementace hodnoty ukazatele
                        ptr_inc <= '1';
                        pc_inc <= '1';

                        next_state  <= s_ready;

                    when X"3C"	=>                  -- "<" dekrementace hodnoty ukazatele
                        ptr_dec <= '1';
                        pc_inc <= '1';

                        next_state  <= s_ready;

                    when X"2B"	=>                  -- "+" inkrementace hodnoty buňky 
                        DATA_EN <= '1';
                        mx1_select <= '0';
                        
                        next_state  <= s_valinc_begin;

                    when X"2D"  =>                  -- "-" dekrementace hodnoty buňky
                        DATA_EN <= '1';
                        mx1_select <= '0';

                        next_state  <= s_valdec_begin; 

                    when X"2E"  =>                  -- "." tisk hodnoty buňky
                        mx1_select <= '0'; 

                        next_state <= s_print_setup;

                    when X"2C"  =>                  -- "," načtení hodnoty do buňky
                        mx1_select <= '0'; 
                        
                        next_state <= s_input_setup;

                    when others => 
                        next_state <= s_null;
                        pc_inc <= '1';
                end case;

            --Inkrementace/dekrementace hodnot
            when s_valinc_begin =>
                DATA_EN <= '1';             
                mx1_select <= '0';              --načti data přes ptr
                next_state <= s_valinc_ready;

            when s_valinc_ready =>
                pc_inc <= '1';                  --do data WDATA zapiš hodnotu + 1
                mx1_select <= '0';
                mx2_select <= "10";
                next_state <= s_valinc;

            when s_valinc =>
                DATA_EN <= '1';                 
                DATA_RDWR <= '1';               --ulož hodnotu z WDATA
                next_state <= s_fetch;

            when s_valdec_begin =>              --stejně jako increment, jen nastavit mx2 na odečítání
                DATA_EN <= '1';
                mx1_select <= '0';
                next_state <= s_valdec_ready;

            when s_valdec_ready =>
                pc_inc <= '1';
                mx1_select <= '0';
                mx2_select <= "01";
                next_state <= s_valdec;

            when s_valdec =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= s_fetch;

            --Výpis na LCD
            when s_print_setup =>
                DATA_EN <= '1';
                next_state <= s_print;
                
            when s_print =>
                if(OUT_BUSY = '0') then             -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
                    pc_inc <= '1';
                    OUT_WE <= '1';
                    OUT_DATA <= DATA_RDATA;         -- do OUT_DATA vložit data z ram
                    next_state <= s_ready;
                else
                    mx1_select <= '0';
                    next_state <= s_print_setup;
                end if;
            
            when s_input_setup =>
                IN_REQ <= '1';              -- požadavek pro vstup dat
                DATA_EN <= '1';
                mx1_select <= '0';
                next_state <= s_input;

            when s_input =>
                DATA_EN <= '1';
                IN_REQ <= '1';
                if(IN_VLD = '1') then       -- pokud data validni
                    pc_inc <= '1';
                    mx2_select <= "00";     
                    DATA_RDWR <= '1';       -- zapiš data do ram na pozici ptr
                    next_state <= s_ready;
                else
                    mx1_select <= '0';
                    next_state <= s_input_setup;
                end if;

            when s_null =>
                --pc_inc <= '1';
                next_state <= s_fetch;

            when others => null;
                --mx1_select <= '1';
                --next_state <= init;

        end case;

    end process;

end behavioral;

