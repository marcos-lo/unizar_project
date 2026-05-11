----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    10:38:16 04/08/2014 
-- Design Name: 
-- Module Name:    memoriaRAM_I - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity memoriaRAM_I is port (
		  CLK : in std_logic;
		  ADDR : in std_logic_vector (31 downto 0); --Dir 
        Din : in std_logic_vector (31 downto 0);--entrada de datos para el puerto de escritura
        WE : in std_logic;		-- write enable	
		  RE : in std_logic;		-- read enable		  
		  Dout : out std_logic_vector (31 downto 0));
end memoriaRAM_I;

architecture Behavioral of memoriaRAM_I is
type RamType is array(0 to 127) of std_logic_vector(31 downto 0);
--signal RAM : RamType := (  			X"10210003", X"1021003E", X"1021005D", X"1021006C", X"08010000", X"04212000", X"04842000", X"04844000",  -- word 0,1,2,3,4,5,6,7
--									X"05088000", X"06003000", X"08040004", X"08C20000", X"08C20004", X"06063000", X"04252800", X"1000FFFB",--word 8,9,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000",--word 16,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 24,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 32,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000",--word 40,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000",
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000",
--									X"08010000", X"0C017008", X"20000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 64,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000",--word 72,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 80,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 88,...
--									X"08020104", X"0C027004", X"08020108", X"08420000", X"0C027004", X"20000000", X"00000000", X"00000000", --word 96,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 104,...
--									X"0802010C", X"0C027004", X"1000FFFF", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", --word 112,...
--									X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000", X"00000000");--word 120,...
-- Ram para calculo de latencias y test completo de la UC
signal RAM : RamType := (

    X"08070100",  -- word 0: lw r7, 0x0100  -> MISS limpio. (Carga el puntero Scratch de la word 64, inc_m++)
    X"00000000", X"00000000", X"00000000", X"00000000",
    X"08010000",  -- word 5: lw r1, 0x0000  -> MISS limpio. Trae Bloque 0 a Vía 0. (inc_m++)
    X"00000000", X"00000000", X"00000000", X"00000000",
    X"08020004",  -- word 10: lw r2, 0x0004 -> HIT LECTURA. (inc_r++)
    X"00000000", X"00000000", X"00000000", X"00000000",
    X"0C040000",  -- word 15: sw r4, 0x0000 -> HIT ESCRITURA. Ensucia el bloque 0. (inc_w++)
    X"0C010020",  -- word 16: sw r1, 0x0020 -> MISS ESCRITURA (Write-around directo a memoria, inc_m++)
    X"00000000", X"00000000", X"00000000", 
    X"08050040",  -- word 20: lw r5, 0x0040 -> MISS limpio. Llena vía 1. (inc_m++)
    X"00000000", X"00000000", X"00000000", X"00000000",
    X"08060080",  -- word 25: lw r6, 0x0080 -> MISS SUCIO. Expulsa bloque 0. ¡COPYBACK! (inc_cb++)
    X"00000000", X"00000000", X"00000000", X"00000000",

    X"08E80000",  -- word 30: lw r8, 0(r7)  -> LECTURA SCRATCH.
    X"00000000", X"00000000", X"00000000", X"00000000",

    X"0CE10004",  -- word 35: sw r1, 4(r7)  -> ESCRITURA SCRATCH. 
    X"00000000", X"00000000", X"00000000", X"00000000",
    X"08097000",  -- word 40: lw r9, 0x7000 -> LECTURA I/O.
    X"00000000", X"00000000", X"00000000", X"00000000",
    X"0C097004",  -- word 45: sw r9, 0x7004 -> ESCRITURA I/O.
    X"00000000", X"00000000", X"00000000", X"00000000",

    X"1000FFFF",  -- word 50: beq r0, r0, -1 -> Bucle infinito. Congela el procesador.
    
    -- Rellenamos con ceros hasta llegar a la posición clave (word 63)
    X"00000000", X"00000000", X"00000000", X"00000000", -- words 51-54
    X"00000000", X"00000000", X"00000000", X"00000000", -- words 55-58
    X"00000000", X"00000000", X"00000000", X"00000000", -- words 59-62
    X"00000000",                                        -- word 63-

    X"10000000",  -- word 64 (0x0100): Puntero MD Scratch. ¡Evita el Data Abort!
    X"00000000",  -- word 65
    X"01000000",  -- word 66 (0x0108): Puntero Registros Internos.
    
    others => X"00000000"
);

signal dir_7:  std_logic_vector(6 downto 0); 
begin
 
 dir_7 <= ADDR(8 downto 2); -- como la memoria es de 128 plalabras no usamos la dirección completa sino sólo 7 bits. Como se direccionan los bytes, pero damos palabras no usamos los 2 bits menos significativos
 process (CLK)
    begin
        if (CLK'event and CLK = '1') then
            if (WE = '1') then -- sólo se escribe si WE vale 1
                RAM(conv_integer(dir_7)) <= Din;
            end if;
        end if;
    end process;

    Dout <= RAM(conv_integer(dir_7)) when (RE='1') else "00000000000000000000000000000000"; --sólo se lee si RE vale 1

end Behavioral;


