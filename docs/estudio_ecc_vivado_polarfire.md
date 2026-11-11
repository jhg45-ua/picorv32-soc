# Estudio y Caracterización de ECC en Vivado (PG058) y Portabilidad a FPGA PolarFire

**Autor:** Julián Hinojosa Gil  
**Proyecto:** PicoRV32 SoC Rad-Hard (TMR + ECC)  
**Fecha:** 16 de Noviembre de 2026  
**Referencia:** Tarea de Investigación (*INV: Estudio y caracterización de ECC en Vivado*)

---

## 1. Resumen Ejecutivo

Este documento formaliza la investigación y caracterización del soporte de memoria con tolerancia a fallos mediante códigos de corrección de errores (SECDED ECC) para el SoC PicoRV32. Se analiza el comportamiento de la IP **Block Memory Generator (PG058)** de AMD/Xilinx Vivado en arquitecturas Artix-7, las restricciones arquitectónicas de bus y temporización descubiertas, las pruebas de inyección y validación de banderas de error (`sbiterr` y `dbiterr`), y la evaluación de portabilidad técnica hacia la familia de FPGAs **Microchip PolarFire**.

---

## 2. Revisión de Soporte de ECC Nativo en Block Memory Generator (PG058)

De acuerdo con la guía oficial de producto de AMD/Xilinx (*PG058: LogiCORE IP Block Memory Generator v8.4*):

### 2.1. ECC Nativo (Hard ECC) vs. Soft ECC
1. **Restricción de Hard ECC en Serie 7 (`RAMB36E1`)**:
   - El soporte de **ECC nativo por hardware** embebido en los bloques `RAMB36E1` de la serie 7 (incluida la FPGA Artix-7 `xc7a100tcsg324-1`) está **estrictamente restringido a configuraciones de 64 bits de ancho de datos** (+ 8 bits de paridad = 72 bits totales) en modo *Simple Dual Port (SDP)*.
   - **Incompatibilidad con procesadores RV32**: Debido a que la arquitectura de PicoRV32 utiliza un bus de datos nativo de 32 bits, Vivado **no permite habilitar Hard ECC nativo** para este ancho de palabra.
2. **Uso forzado de Soft ECC**:
   - Al seleccionar un ancho de datos de 32 bits con ECC, Vivado recurre obligatoriamente a la implementación de **Soft ECC** (`CONFIG.softecc {true}`).
   - Soft ECC sintetiza los árboles de paridad Hamming/SECDED (codificadores y decodificadores) utilizando la matriz de celdas lógicas (LUTs) en lugar del hardware dedicado del bloque BRAM.
3. **Restricciones de Inicialización (`Load_Init_File` / `.coe`)**:
   - La IP BMG de Vivado prohíbe la inicialización de contenido mediante archivos COE cuando se combinan ciertas configuraciones de ECC con puertos de lectura/escritura independientes.
   - En nuestro SoC, dado que el procesador debe arrancar inmediatamente desde la dirección `0x0000_0000`, se implementó una arquitectura dual en `rtl/soc/bram_ecc.v`: generación opcional de la IP de Vivado sin inicializar y un modelo RTL inferido SECDED preinicializado con paridad calculada (`build/firmware.hex`).

---

## 3. Restricciones de Ancho de Bus y Latencia Añadida

### 3.1. Restricciones de Ancho de Bus y Escrituras Parciales (RMW)
- **Palabra de 39 bits (32 datos + 7 paridad)**: El esquema SECDED(39, 32) requiere 7 bits de paridad para cubrir 32 bits de datos (distancia mínima de Hamming $d_{min} = 4$).
- **Problema de las escrituras parciales (`sb`, `sh`)**: En una memoria protegida por ECC, no es posible actualizar un único byte o media palabra directamente en el array, ya que los 7 bits de paridad cubren conjuntamente los 32 bits.
- **Controlador Read-Modify-Write (RMW)**: Para resolver esto sin modificar la arquitectura del procesador, se implementó en `rtl/soc/system.v` una máquina de estados RMW:
  - **Escrituras de palabra completa (`sw`, 4 bytes)**: Se resuelven en **1 ciclo** de bus.
  - **Escrituras parciales (`sb`, `sh`)**: Se ejecutan de manera transparente en **2 ciclos**:
    1. *Ciclo 1*: Lectura de la palabra de 32 bits existente y corrección al vuelo mediante el decodificador ECC.
    2. *Ciclo 2*: Fusión (*merge*) de los bytes modificados según `mem_wstrb` y reescritura de la palabra completa con el nuevo síndrome calculado.

### 3.2. Latencia y Degradación de Frecuencia Máxima ($F_{max}$)
Al no disponer de Hard ECC para 32 bits en Artix-7, la inserción de los árboles combinacionales XOR de Soft ECC en la ruta crítica de lectura introduce una penalización temporal significativa:

| Configuración | Slice LUTs | Block RAM Tiles | WNS (@ 100 MHz) | $F_{max}$ Estimada |
| :--- | :---: | :---: | :---: | :---: |
| **Base (Sin protección)** | 1,100 | 4.0 | +3.056 ns (MET) | **144.0 MHz** |
| **ECC Only (BRAM + Regs)** | 1,595 (+45.0%) | 4.5 | -1.011 ns (VIOLATED) | **90.8 MHz** |
| **Full (TMR + ECC)** | 1,856 (+68.7%) | 4.5 | -0.547 ns (VIOLATED) | **94.8 MHz** |

- **Penalización temporal**: Soft ECC añade aproximadamente **2.5 ns** de retardo combinacional en el camino de datos de salida de la memoria BRAM hacia el bus del procesador.
- **Conclusión de temporización**: En grado de velocidad `-1` de Artix-7, un diseño unpipelined con Soft ECC alcanza un techo de operación de **~91-95 MHz**. Para alcanzar los 100 MHz de forma estricta sin violaciones de slack, se requiere habilitar una etapa de pipeline de salida en el puerto de lectura BRAM (añadiendo 1 ciclo de latencia al ciclo de lectura).

---

## 4. Proyecto de Prueba y Verificación en Vivado

Se integró y sintetizó el diseño completo en Vivado:
1. **Generación de bitstreams**:
   - `prebuilt/system_ecc.bit` (774 KB)
   - `prebuilt/system_tmr_ecc.bit` (865 KB)
2. **Informes de implementación**:
   - `reports/ecc_utilization_system_ecc.rpt`
   - `reports/ecc_timing_summary_system_ecc.rpt`
   - `reports/full_utilization_system_tmr_ecc.rpt`
   - `reports/full_timing_summary_system_tmr_ecc.rpt`

---

## 5. Verificación de Banderas de Error (`sbiterr` y `dbiterr`)

La funcionalidad de detección y corrección se verificó en tres niveles complementarios de simulación:

### 5.1. Test Unitario Matemático Exhaustivo (`sim/ecc_secded32_tb.v`)
- **Caso limpio**: 0 errores, `sbiterr = 0`, `dbiterr = 0`, síndrome nulo.
- **Barrido exhaustivo de 1 bit (SEU)**: Se inyectaron errores en cada una de las 39 posiciones de bit de la palabra de código. **Resultado: 39/39 corregidos con éxito**, `sbiterr = 1`, `dbiterr = 0`.
- **Barrido exhaustivo de 2 bits (MEU/MBU)**: Se evaluaron los $\binom{39}{2} = 741$ pares posibles de errores dobles simultáneos. **Resultado: 741/741 detectados como incorregibles**, `sbiterr = 0`, `dbiterr = 1`.

### 5.2. Test Unitario de Banco de Registros con Auto-Scrubbing (`sim/picorv32_regs_tb.v`)
- Verificación de lectura/escritura con LUTRAM (`RAM32M`).
- Inyección de SEU en registro activo: detección inmediata por `sbiterr` y sobreescritura automática (*auto-scrubbing*) en el ciclo siguiente cuando no hay escritura de CPU (`!wen`).

### 5.3. Inyección de Fallos en SoC Completo (`sim/system_tb.v`)
- **SEU en BRAM (Instrucción)**: Con el procesador ejecutando firmware en tiempo real, se inyectó 1 bit-flip en memoria de instrucciones. El hardware activó `bram_sbiterr = 1`, reportó la dirección física en `bram_rdaddrecc`, el decodificador corrigió la instrucción al vuelo y el procesador continuó su ejecución sin generar `trap`.
- **MEU en BRAM**: Se inyectaron 2 bit-flips simultáneos. Se activó `bram_dbiterr = 1`, `bram_sbiterr = 0`, capturando la dirección del fallo para telemetría.

---

## 6. Evaluación de Compatibilidad y Portabilidad hacia FPGA Microchip PolarFire

La familia **PolarFire (Microchip / Microsemi)** representa el estándar actual de la industria para sistemas aeroespaciales y de alta fiabilidad de bajo consumo, gracias a su arquitectura basada en celdas Flash no volátiles (inmunes a SEU en la configuración de la matriz de interconexión).

### 6.1. Comparativa Arquitectónica de Bloques de Memoria

| Característica | AMD/Xilinx Artix-7 (Nexys A7) | Microchip PolarFire (MPF300T / RT PolarFire) |
| :--- | :--- | :--- |
| **Bloque BRAM Principal** | `RAMB36E1` (36 Kb) | **LSRAM (Large SRAM, 20 Kb)** |
| **Soporte Hard ECC Nativo** | **Solo 64 bits** (512x64 + 8 parity) | **SÍ admite nativamente 32 bits** (modo 33b / x32 con parity dedicado) |
| **Coste en Lógica (LUTs) para ECC 32b** | Alto (+495 LUTs de Soft ECC) | **Cero LUTs** (lógica SECDED embebida en silicio en cada bloque LSRAM) |
| **Impacto en Frecuencia ($F_{max}$)** | Penalización de ~2.5 ns (cae a ~90-95 MHz) | Prácticamente nulo; opera a la frecuencia nativa del bloque LSRAM (~300+ MHz) |
| **Banderas de Error Nativas** | `SBITERR`, `DBITERR`, `RDADDRECC` | `SB_FLAG` (Single-bit), `DB_FLAG` (Double-bit), síndrome en registros |
| **Memoria Distribuida (LUTRAM)** | `RAM32M` / `SLICEM` | **uSRAM (Micro SRAM, 64x12 bits)** (requiere Soft ECC como el implementado) |
| **Inmunidad a Radiación** | Celdas SRAM (requiere Soft Error Mitigation / SEM) | **Inmune a SEU en configuración** (Celdas SONOS Flash) |

### 6.2. Estrategia de Portabilidad hacia Libero SoC

1. **Portabilidad Inmediata de RTL (Vendor-Agnostic)**:
   - Todo el RTL desarrollado (`ecc_secded32_enc.v`, `ecc_secded32_dec.v`, `tmr_voter.v` y el bloque `bram_ecc.v` en modo inferido) es código **Verilog-2001 estándar**, sin primitivas propietarias de Xilinx.
   - Sintetiza de manera directa y limpia en la herramienta de síntesis **Synopsys Synplify Pro** de Microchip Libero SoC.
2. **Aprovechamiento del Hard ECC en PolarFire**:
   - Para maximizar la eficiencia en PolarFire, se recomienda reemplazar la IP `blk_mem_gen_ecc` de Xilinx por la macro primitiva nativa `RAM1K20` en modo ECC o mediante el generador `PF_SRAM_AHBL_AXI` / `CoreMemory` de Libero configurado con ECC de 32 bits.
   - **Mapeo directo de señales**:
     - `clka`, `ena`, `wea`, `addra`, `dina` $\rightarrow$ Interfaz de escritura LSRAM.
     - `clkb`, `enb`, `addrb`, `doutb` $\rightarrow$ Interfaz de lectura LSRAM.
     - `sbiterr` $\rightarrow$ `SB_FLAG`.
     - `dbiterr` $\rightarrow$ `DB_FLAG`.
3. **Inicialización de Memoria**:
   - En PolarFire, la memoria LSRAM se inicializa durante el encendido mediante el controlador del sistema (*System Controller*) transfiriendo el binario desde la memoria interna no volátil segura (`sNVM`) o SPI Flash externa, eliminando la restricción de inicialización encontrada en Vivado BMG.

---

## 7. Conclusión y Veredicto de la Tarea

Todos los objetivos de la tarea han sido cumplidos y validados:
- [x] **Revisar soporte de ECC nativo en Block Memory Generator (PG058)**: Analizado y documentada la restricción de 64 bits para Hard ECC y el uso obligatorio de Soft ECC para 32 bits.
- [x] **Comprobar restricciones de ancho de bus y latencia añadida**: Implementado controlador RMW para escrituras parciales y caracterizada la degradación de temporización (~2.5 ns, $F_{max} \approx 91-95$ MHz).
- [x] **Crear proyecto de prueba con BRAM y ECC activado**: Flujo completo de síntesis con bitstreams y reportes en Vivado batch.
- [x] **Verificar funcionamiento de flags de error (sbiterr y dbiterr)**: Comprobado en unit tests (39/39 SEU, 741/741 MEU) y en simulación a nivel de sistema.
- [x] **Evaluar compatibilidad y portabilidad hacia FPGA PolarFire**: Concluida la alta portabilidad del RTL y las ventajas sustanciales de PolarFire (Hard ECC nativo de 32 bits sin coste en LUTs).

**Veredicto:** La tarea **puede darse formalmente por completada al 100%**.
