----------------------------------------------------------------------------------
-- Company: 
-- Engineers: Marcos López Gracia NIP: 845031, Daniel Olmos Gomera NIP: 926237-- 
-- Create Date:    12:10:07 04/01/2026 
-- Design Name: 
-- Module Name:    ALU - Behavioral with support for vectorial MAC with internal accumulation
-- Additional Comments: by AOC2 Team Unizar 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;



entity ALU_Vector_MAC is
    Port ( DA : in  STD_LOGIC_VECTOR (31 downto 0); --input 1
           DB : in  STD_LOGIC_VECTOR (31 downto 0); --input 2
           valid_I_EX : in  STD_LOGIC;
           clk : in  STD_LOGIC;
		   reset : in  STD_LOGIC;
		   ready : out STD_LOGIC; --initially is always '1', but if ALU supports multicycle ops, it will be cero when the output is not ready
           ALUctrl : in  STD_LOGIC_VECTOR (2 downto 0); -- Ops: "000" add, "001" sub, "010" AND, "011" OR, "100" MAC with internal acc, "101" MAC without previous acc.
           Dout : out  STD_LOGIC_VECTOR (31 downto 0); -- Output
           -- RF8
           Exception_accepted : in STD_LOGIC;
           RTE_EX : in STD_LOGIC
           );
end ALU_Vector_MAC;

architecture Behavioral of ALU_Vector_MAC is

component reg is
    generic (size: natural := 32);  -- por defecto son de 32 bits, pero se puede usar cualquier tamaño
	Port ( Din : in  STD_LOGIC_VECTOR (size -1 downto 0);
           clk : in  STD_LOGIC;
		   reset : in  STD_LOGIC;
           load : in  STD_LOGIC;
           Dout : out  STD_LOGIC_VECTOR (size -1 downto 0));
end component;

signal Dout_internal: STD_LOGIC_VECTOR (31 downto 0);
signal ACC_out : STD_LOGIC_VECTOR (31 downto 0) := X"00000000";
signal ACC_input, sum_total_ext: Signed (31 downto 0);
signal prod0, prod1, prod2, prod3 : Signed(15 downto 0);
signal sum1, sum2 : Signed(16 downto 0);
signal sum_total : Signed(17 downto 0);
signal load_acc, Acc_op, MAC_start : STD_LOGIC;
signal ACC_shadow : STD_LOGIC_VECTOR (31 downto 0) := X"00000000"; -- RF8

-- NUEVAS SEÑALES PARA LA MÁQUINA DE ESTADOS MAC MULTICICLO
type state_type is (S_IDLE, S_PROD, S_SUM);
signal state, next_state : state_type := S_IDLE;

-- Registros para guardar los cálculos intermedios
signal reg_prod0, reg_prod1, reg_prod2, reg_prod3 : Signed(15 downto 0);
signal reg_sum_total : Signed(17 downto 0);
begin
	process(clk)
    begin
		if rising_edge(clk) then
            if reset = '1' then
                state <= S_IDLE;
                reg_prod0 <= (others => '0');
                reg_prod1 <= (others => '0');
                reg_prod2 <= (others => '0');
                reg_prod3 <= (others => '0');
                reg_sum_total <= (others => '0');
            else
                state <= next_state;
                -- Ciclo 1: Guardamos los productos
                if state = S_IDLE and valid_I_EX = '1' and Acc_op = '1' then
                    reg_prod0 <= signed(DA(7 downto 0))   * signed(DB(7 downto 0));
                    reg_prod1 <= signed(DA(15 downto 8))  * signed(DB(15 downto 8));
                    reg_prod2 <= signed(DA(23 downto 16)) * signed(DB(23 downto 16));
                    reg_prod3 <= signed(DA(31 downto 24)) * signed(DB(31 downto 24));
                end if;
                -- Ciclo 2: Guardamos la suma parcial
                if state = S_PROD then
                    reg_sum_total <= (sum1(16) & sum1) + (sum2(16) & sum2);
                end if;
            end if;
        end if;
end process;

-- PROCESO COMBINACIONAL DE LA MÁQUINA DE ESTADOS
process(state, valid_I_EX, Acc_op)
begin
    next_state <= state;
    ready <= '1'; -- Por defecto, la ALU está lista
    
    case state is
        when S_IDLE =>
            if valid_I_EX = '1' and Acc_op = '1' then
                next_state <= S_PROD;
                ready <= '0'; -- Congelamos el MIPS (Ciclo 1)
            end if;
            
        when S_PROD =>
            next_state <= S_SUM;
            ready <= '0'; -- Congelamos el MIPS (Ciclo 2)
            
        when S_SUM =>
            next_state <= S_IDLE;
            ready <= '1'; -- ¡Terminamos! Liberamos el MIPS (Ciclo 3)
    end case;
end process;
-- Las sumas parciales ahora leen de los registros calculados en el Ciclo 1
sum1 <= (reg_prod0(15) & reg_prod0) + (reg_prod1(15) & reg_prod1);
sum2 <= (reg_prod2(15) & reg_prod2) + (reg_prod3(15) & reg_prod3);

-- sum_total ya no se usa directamente, la extensión de signo lee del registro del Ciclo 2
sum_total_ext(17 downto 0) <= reg_sum_total;
sum_total_ext(31 downto 18) <= "00000000000000" when reg_sum_total(17)='0' else "11111111111111";

Acc_op <= '1' when (ALUctrl(2 downto 1) = "10") else '0';

-- ¡IMPORTANTE! El acumulador SOLO se carga en el Ciclo 3 (S_SUM)
load_acc <= '1' when (state = S_SUM) else '0';

MAC_start <=   '1' when (ALUctrl(0) = '1') else '0';

ACC_input	 <= 	sum_total_ext when (MAC_start = '1')
                    else sum_total_ext + signed(ACC_out);
-- 1. EL REGISTRO ACUMULADOR (Guarda el dato en el flanco de reloj)
process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            ACC_out <= (others => '0');
            ACC_shadow <= (others => '0');
        -- 1. ALERTA DE EXCEPCIÓN: Hacemos la copia de seguridad (Máxima prioridad)
        elsif Exception_accepted = '1' then
            ACC_shadow <= ACC_out;
            
        -- 2. REGRESO DE EXCEPCIÓN: Restauramos el valor original
        elsif RTE_EX = '1' then
            ACC_out <= ACC_shadow;
            
        -- 4. FUNCIONAMIENTO NORMAL: El MAC guarda su resultado
        elsif load_acc = '1' then
            ACC_out <= std_logic_vector(ACC_input);
        end if;
        
    end if;
end process;

-- 2. OPERACIONES BÁSICAS DE LA ALU (ADD, SUB, AND, OR)
Dout_internal <=    DA + DB when (ALUctrl(2 downto 0) = "000") else
                    DA - DB when (ALUctrl(2 downto 0) = "001") else
                    DA and DB when (ALUctrl(2 downto 0) = "010") else
                    DA or DB when (ALUctrl(2 downto 0) = "011") else
                    std_logic_vector(ACC_input); -- Para las operaciones MAC, el resultado es el Acumulador

-- 3. SALIDA FINAL
Dout <= Dout_internal;
end Behavioral;