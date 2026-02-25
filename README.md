# FPGA Matrix Multiply Accelerator

A parameterizable NxN matrix multiply accelerator using a weight-stationary systolic array architecture, implemented in SystemVerilog with an AXI4-Lite host interface.

## Architecture

- **Systolic array** of NxN Processing Elements, each with a 2-stage pipelined MAC unit
- **Weight-stationary dataflow** — same architecture as Google's TPU
- **INT16 inputs, INT32 accumulators** — maps to Xilinx DSP48E1 slices
- **AXI4-Lite** slave interface for host communication
- **Parameterizable** — default 4x4, scalable to 9x9 on Arty A7-35T (90 DSPs)

## Target

- **FPGA**: Xilinx Arty A7-35T (xc7a35ticsg324-1L)
- **Toolchain**: Vivado 2023.x+
- **Clock**: 100 MHz
- **Performance**: ~33 cycles per 4x4 multiply (330 ns)

## Quick Start

### Simulation (Vivado)

```bash
cd scripts
make sim_mac      # Test MAC unit
make sim_pe       # Test Processing Element
make sim_array    # Test Systolic Array
make sim_core     # Test Core (BRAM + FSM + Array)
make sim_top      # Test Full System (AXI)
```

### Generate Test Vectors

```bash
pip install -r scripts/python/requirements.txt
make gen_vectors
```

### FPGA Build

```bash
vivado -mode batch -source scripts/tcl/create_project.tcl
vivado -mode batch -source scripts/tcl/run_synthesis.tcl
vivado -mode batch -source scripts/tcl/program_fpga.tcl
```

## Project Structure

```
rtl/                  SystemVerilog RTL sources
  pkg/matmul_pkg.sv   Shared parameters and types
  mac_unit.sv          Multiply-accumulate unit (2-stage pipeline)
  processing_element.sv PE: MAC + weight register + data routing
  systolic_array.sv    NxN PE grid with generate
  bram_matrix.sv       Dual-port BRAM (inferred)
  matmul_control_fsm.sv Control state machine
  matmul_core.sv       Core: array + FSM + 3 BRAMs
  axi_lite_slave.sv    AXI4-Lite register interface
  matmul_top.sv        Top-level wrapper

tb/                   Testbenches (one per module + full system)
scripts/python/       Reference model and verification
scripts/tcl/          Vivado automation scripts
constraints/          FPGA pin and timing constraints
docs/                 Architecture and register map documentation
```

## Documentation

- [Architecture](docs/architecture.md) — Block diagram, dataflow, FSM states
- [Register Map](docs/register_map.md) — AXI4-Lite address map and programming sequence

## Skills Demonstrated

- Digital design and pipelining (systolic array, DSP48E1 inference)
- Parallel architecture (NxN MAC array, weight-stationary dataflow)
- Industry-standard bus protocol (AXI4-Lite)
- Hardware/software co-design (Python reference model + RTL verification)
- FPGA deployment (Xilinx Vivado, timing closure, resource optimization)
