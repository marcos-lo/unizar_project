---------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    13:38:18 05/15/2014 
-- Design Name: 
-- Module Name:    UC_slave - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: la UC incluye un contador de 2 bits para llevar la cuenta de las transferencias de bloque y una máquina de estados
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity UC_MC_CB is
    Port ( 	clk : in  STD_LOGIC;
			reset : in  STD_LOGIC;
			-- Órdenes del MIPS
			RE : in  STD_LOGIC; 
			WE : in  STD_LOGIC;
			-- Respuesta al MIPS
			ready : out  STD_LOGIC; -- indica si podemos procesar la orden actual del MIPS en este ciclo. En caso contrario habrá que detener el MIPs
			-- Señales de la MC
			hit0 : in  STD_LOGIC; --se activa si hay acierto en la via 0
			hit1 : in  STD_LOGIC; --se activa si hay acierto en la via 1
			via_2_rpl :  in  STD_LOGIC; --indica que via se va a reemplazar
			addr_non_cacheable: in STD_LOGIC; --indica que la dirección no debe almacenarse en MC. En este caso porque pertenece a la scratch
			internal_addr: in STD_LOGIC; -- indica que la dirección solicitada es de un registro de MC
			MC_WE0 : out  STD_LOGIC;
            MC_WE1 : out  STD_LOGIC;
           	-- Señales para indicar la operación que se quiere hacer en el bus
       		MC_bus_Read : out  STD_LOGIC; -- para pedir el bus en acceso de lectura
			MC_bus_Write : out  STD_LOGIC; --  para pedir el bus en acceso de escritura
			MC_tags_WE : out  STD_LOGIC; -- para escribir la etiqueta en la memoria de etiquetas
            palabra : out  STD_LOGIC_VECTOR (1 downto 0);--indica la palabra actual dentro de una transferencia de bloque (1ª, 2ª...)
            mux_origen: out STD_LOGIC; -- Se utiliza para elegir si el origen de la dirección de la palabra y el dato es el Mips (cuando vale 0) o la UC y el bus (cuando vale 1)
			block_addr : out  STD_LOGIC; -- indica si la dirección a enviar es la de bloque (rm) o la de palabra (w)
			mux_output: out  std_logic_vector(1 downto 0); -- para elegir si le mandamos al procesador la salida de MC (valor 0),los datos que hay en el bus (valor 1), o un registro interno( valor 2)
			-- señales para los contadores de rendimiento de la MC
			inc_m : out STD_LOGIC; -- indica que ha habido un fallo en MC
			inc_w : out STD_LOGIC; -- indica que ha habido una escritura en MC
			inc_r : out STD_LOGIC; -- indica que ha habido una escritura en MC
			inc_cb :out STD_LOGIC; -- indica que ha habido un reemplazo sucio en MC
			-- Gestión de errores
			unaligned: in STD_LOGIC; --indica que la dirección solicitada por el MIPS no está alineada
			Mem_ERROR: out std_logic; -- Se activa si en la ultima transferencia el esclavo no respondió a su dirección
			load_addr_error: out std_logic; --para controlar el registro que guarda la dirección que causó error
			-- Gestión de los bloques sucios
			send_dirty: out std_logic;-- Indica que hay que enviar la @ del bloque sucio
			Update_dirty	: out  STD_LOGIC; --indica que hay que actualizar los bits dirty tanto por que se ha realizado una escritura, como porque se ha enviado el bloque sucio a memoria
			dirty_bit_rpl : in  STD_LOGIC; --indica si el bloque a reemplazar es sucio
			Block_copied_back	: out  STD_LOGIC; -- indica que se ha enviado a memoria un bloque que estaba sucio. Se usa para elegir la máscara que quita el bit de sucio
			-- Para gestionar las transferencias a través del bus
			bus_TRDY : in  STD_LOGIC; --indica que la memoria puede realizar la operación solicitada en este ciclo
			Bus_DevSel: in  STD_LOGIC; --indica que la memoria ha reconocido que la dirección está dentro de su rango
			Bus_grant :  in  STD_LOGIC; --indica la concesión del uso del bus
			MC_send_addr_ctrl : out  STD_LOGIC; --ordena que se envíen la dirección y las señales de control al bus
            MC_send_data : out  STD_LOGIC; --ordena que se envíen los datos
            Frame : out  STD_LOGIC; --indica que la operación no ha terminado
            last_word : out  STD_LOGIC; --indica que es el último dato de la transferencia
            Bus_req :  out  STD_LOGIC --indica la petición al árbitro del uso del bus
			);
end UC_MC_CB;

architecture Behavioral of UC_MC_CB is
 
component counter is 
	generic (
	   size : integer := 10
	);
	Port ( clk : in  STD_LOGIC;
	       reset : in  STD_LOGIC;
	       count_enable : in  STD_LOGIC;
	       count : out  STD_LOGIC_VECTOR (size-1 downto 0)
					  );
end component;		           
-- Ejemplos de nombres de estado. No hay que usar estos. Nombrad a vuestros estados con nombres descriptivos. Así se facilita la depuración
type state_type is (Inicio, dir_palabra, latencia_etiq_1, escribir_bloque_sucio, enviar_palabra, dir_bloque, bloque_entero_mem, espera_bus, arbitraje_sucio, fallo, Dir_bloque_sucio, latencia_etiq_2); 
type error_type is (memory_error, No_error); 
signal state, next_state : state_type; 
signal error_state, next_error_state : error_type; 
signal last_word_block: STD_LOGIC; --se activa cuando se está pidiendo la última palabra de un bloque
signal one_word: STD_LOGIC; --se activa cuando sólo se quiere transferir una palabra
signal count_enable: STD_LOGIC; -- se activa si se ha recibido una palabra de un bloque para que se incremente el contador de palabras
signal hit: std_logic;
signal palabra_UC : STD_LOGIC_VECTOR (1 downto 0);
begin

hit <= hit0 or hit1;	
 
--el contador nos dice cuantas palabras hemos recibido. Se usa para saber cuando se termina la transferencia del bloque y para direccionar la palabra en la que se escribe el dato leido del bus en la MC
word_counter: counter 	generic map (size => 2)
						port map (clk, reset, count_enable, palabra_UC); --indica la palabra actual dentro de una transferencia de bloque (1ª, 2ª...)

last_word_block <= '1' when palabra_UC="11" else '0';--se activa cuando estamos pidiendo la última palabra

palabra <= palabra_UC;

   State_reg: process (clk)
   begin
      if (clk'event and clk = '1') then
         if (reset = '1') then
            state <= Inicio;
         else
            state <= next_state;
         end if;        
      end if;
   end process;
 
   ---------------------------------------------------------------------------
-- 2023
-- Máquina de estados para el bit de error
---------------------------------------------------------------------------

error_reg: process (clk)
   begin
      if (clk'event and clk = '1') then
         if (reset = '1') then           
            error_state <= No_error;
        else
            error_state <= next_error_state;
         end if;   
      end if;
   end process;
   
--Salida Mem Error
Mem_ERROR <= '1' when (error_state = memory_error) else '0';

   
   --MEALY State-Machine - Outputs based on state and inputs
   --Sensitivity list: check that all the combinational inputs used are included
OUTPUT_DECODE: process (state, hit, last_word_block, bus_TRDY, RE, WE, Bus_DevSel, Bus_grant, via_2_rpl, hit0, hit1, dirty_bit_rpl, addr_non_cacheable, internal_addr, unaligned)
   begin
    -- 1. Valores por defecto
    MC_WE0 <= '0';
    MC_WE1 <= '0';
    MC_bus_Read <= '0';
    MC_bus_Write <= '0';
    MC_tags_WE <= '0';
    ready <= '0'; 
    mux_origen <= '0';
    MC_send_addr_ctrl <= '0';
    MC_send_data <= '0';
    next_state <= state;  
    count_enable <= '0';
    Frame <= '0';
    block_addr <= '0';
    inc_m <= '0';
    inc_w <= '0';
    inc_r <= '0';
    inc_cb <= '0';
    Bus_req <= '0';
    one_word <= '0';
    mux_output <= "00";
    last_word <= '0';
    next_error_state <= error_state; 
    load_addr_error <= '0';
    send_dirty <= '0';
    Update_dirty <= '0';
    Block_copied_back <= '0';
    
    CASE state is 
        when Inicio =>          
            ready <= '1'; 
            if (RE = '0' and WE = '0') then 
                next_state <= Inicio;
                ready <= '1';
            elsif ((RE = '1' or WE = '1') and unaligned ='1') then 
                next_error_state <= memory_error; 
                load_addr_error <= '1';
                next_state <= Inicio;
            elsif (RE= '1' and internal_addr ='1') then 
                mux_output <= "10"; 
                next_error_state <= No_error; 
                next_state <= Inicio;
            elsif (WE = '1' and internal_addr ='1') then 
                next_error_state <= memory_error; 
                load_addr_error <= '1';
                next_state <= Inicio;
            elsif (RE= '1' and hit='1' and addr_non_cacheable='0') then 
                inc_r <= '1'; 
                mux_output <= "00"; 
                next_state <= Inicio;
            elsif (WE= '1' and hit='1' and addr_non_cacheable='0') then 
                if (hit0= '1') then MC_WE0 <= '1';
                elsif (hit1='1') then MC_WE1 <= '1';
                end if;
                Update_dirty <= '1';
                inc_w <= '1';
                next_state <= Inicio;
            elsif ((RE= '1' or WE= '1')) then  
                ready <= '0'; 
                next_state <= fallo; -- ¡USAMOS EL ESTADO FALLO!
            end if;


       -- =========================================================
        -- ESTADO FALLO (Gestión de contadores)
        -- =========================================================
        when fallo =>
            ready <= '0';
            -- Solo contamos el fallo si NO es de la MD Scratch
            if (addr_non_cacheable = '0') then
                inc_m <= '1';
            end if;
            
            if (WE = '1') then
                next_state <= espera_bus;
            elsif (RE = '1') then
               if (addr_non_cacheable = '1') then
                    next_state <= espera_bus;
                elsif (dirty_bit_rpl = '1') then
                    next_state <= arbitraje_sucio;
                else
                    next_state <= espera_bus;
                end if;
            end if;

        -- =========================================================
        -- FASE 1: ARBITRAJE 
        -- =========================================================
		when espera_bus =>  
            Bus_req <= '1';           
            if (Bus_grant = '0') then
                next_state <= espera_bus;
            else
                if (WE = '1') then
                    next_state <= dir_palabra;
                elsif (RE = '1' and addr_non_cacheable = '1') then
                    next_state <= dir_palabra;
                elsif (RE = '1' and addr_non_cacheable = '0') then
                    next_state <= dir_bloque; -- ¡ESTO OBLIGA A IR AL ESTADO DE DIRECCIÓN!
                end if;
            end if;

        when arbitraje_sucio => 
            Bus_req <= '1';
            if (Bus_grant = '0') then
                next_state <= arbitraje_sucio;
            else
                next_state <= Dir_bloque_sucio;
            end if; 

        -- =========================================================
        -- FASE 2: DIRECCIÓN
        -- =========================================================
       when dir_palabra =>
            -- FASE DE DIRECCIÓN: Aquí es donde se debe comprobar Bus_DevSel
            Bus_req <= '1';
            Frame <= '1';
            MC_send_addr_ctrl <= '1';
            last_word <= '1';
            if (WE = '1') then 
                MC_bus_Write <= '1';
            else 
                MC_bus_Read <= '1'; 
            end if;
            
            -- Comprobamos AQUÍ si algún esclavo ha reconocido la dirección
            if (Bus_DevSel = '0') then
                next_state <= Inicio;
                next_error_state <= memory_error; 
                load_addr_error <= '1';
                ready <= '1';
            else
                next_state <= enviar_palabra;
            end if;

        when dir_bloque =>
            Bus_req <= '1';
            Frame <= '1';
            MC_send_addr_ctrl <= '1';
            MC_bus_Read <= '1';
            block_addr <= '1';
            
            next_state <= bloque_entero_mem;

        when Dir_bloque_sucio =>
            Bus_req <= '1';
            Frame <= '1';
            MC_send_addr_ctrl <= '1';
            send_dirty <= '1';
            MC_bus_Write <= '1';
            mux_origen <= '1';
            
            next_state <= escribir_bloque_sucio;

       -- =========================================================
        -- FASE 3: DATOS
        -- =========================================================
       when enviar_palabra =>  
            -- FASE DE DATOS: Solo esperamos TRDY. Bus_DevSel ya no es válido aquí.
            Bus_req <= '1';
            Frame <= '1'; 
            MC_send_addr_ctrl <= '1';
            last_word <= '1';
            
            if (WE = '1') then
                MC_bus_Write <= '1';
                MC_send_data <= '1';
            else
                MC_bus_Read <= '1';
                mux_output <= "01";
            end if;
            
            if (bus_TRDY = '1') then
                ready <= '1'; 
                next_state <= Inicio;
            else
                next_state <= enviar_palabra;
            end if;

        when bloque_entero_mem =>  
            Bus_req <= '1';
            MC_bus_Read <= '1';
            block_addr <= '1';
            MC_send_addr_ctrl <= '1';
            mux_origen <= '1'; 
            Frame <= '1'; 

            if (last_word_block = '0') then
                last_word <= '0';
            else 
                last_word <= '1';
            end if;

            -- CÓDIGO CAMBIADO: Reordenación idéntica para los bloques de la MD.
            -- Aseguramos que un bus_TRDY='1' siempre prime sobre un DevSel inestable.
            if (bus_TRDY = '1') then
                count_enable <= '1';
                if (via_2_rpl = '0') then MC_WE0 <= '1';
                else MC_WE1 <= '1';
                end if;

                if (last_word_block = '1') then
                    MC_tags_WE <= '1';
                    next_state <= latencia_etiq_1; 
                else 
                    next_state <= bloque_entero_mem;
                end if;
            elsif (Bus_DevSel = '0' and palabra_UC = "00") then
                next_state <= Inicio;
                next_error_state <= memory_error; 
                load_addr_error <= '1';
                ready <= '1';
            else
                next_state <= bloque_entero_mem;
            end if;

        -- =========================================================
        -- ESTADO PUENTE (Espera de 1 ciclo para las etiquetas)
        -- =========================================================

        when escribir_bloque_sucio =>  
            Bus_req <= '1';
            MC_send_addr_ctrl <= '1'; 
            MC_bus_Write <= '1';
            MC_send_data <= '1';
            mux_origen <= '1';
            send_dirty <= '1';
            Frame <= '1'; 

            if (last_word_block = '0') then
                last_word <= '0';
            else
                last_word <= '1';
            end if;

            if (Bus_DevSel = '0' and palabra_UC = "00") then
                next_state <= Inicio;
                next_error_state <= memory_error; 
                load_addr_error <= '1';
                ready <= '1';
            elsif (bus_TRDY = '1') then
                count_enable <= '1';
                if (last_word_block = '1') then
                    Block_copied_back <= '1';
                    inc_cb <= '1';
                    Update_dirty <= '1';
                    next_state <= espera_bus;
                else 
                    next_state <= escribir_bloque_sucio;
                end if;
            else
                 next_state <= escribir_bloque_sucio;
            end if;
        -- =========================================================
        -- ESTADOS PUENTE (Sala de espera de 2 ciclos para RAM síncrona)
        -- =========================================================
        when latencia_etiq_1 =>  
            -- Ciclo 1: La caché captura la dirección del MIPS
            next_state <= latencia_etiq_2; 

        when latencia_etiq_2 =>
            -- Ciclo en el que la MC ya tiene la etiqueta nueva y hit=1
            next_state <= Inicio;
        WHEN others => 
            next_state <= Inicio;
    end CASE;    
   end process;
 
   
end Behavioral;

