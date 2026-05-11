# CPU Cache Architecture - VHDL Implementation

Proyecto universitario de Arquitectura de Computadores (AOC) en la Universidad de Zaragoza.

## Descripción

Implementación en VHDL de un procesador con memoria cache de dos niveles (L1, L2).

### Características

- Protocolo de coherencia de cache
- Máquina de estados para control de hits/misses
- Testbenches completos

### Archivos principales

- `cpu.vhd` - CPU principal
- `cache_controller.vhd` - Controlador de cache
- `testbench_cache.vhd` - Tests unitarios

### Cómo compilar

```bash
ghdl -a *.vhd
ghdl -e tb_cache
ghdl -r tb_cache
```

### Estado

- ✅ Lógica de cache implementada
- 🔄 Documentación en progreso
- 📊 Tests finalizados
