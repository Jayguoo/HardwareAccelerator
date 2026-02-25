# Matrix Multiply Accelerator — Architecture

## Overview

FPGA-based NxN matrix multiply accelerator using a **weight-stationary systolic array**.
Computes C = A x B where A, B are NxN matrices of signed 16-bit integers.

Target: Xilinx 7-series (Arty A7-35T), 100 MHz, AXI4-Lite interface.

## Block Diagram

```
                    AXI4-Lite Bus
                         |
                 +-------v-------+
                 | axi_lite_slave|
                 | (register map)|
                 +---+---+---+--+
                     |   |   |
              +------+   |   +------+
              |          |          |
         +----v---+ +---v----+ +---v----+
         | BRAM A | | BRAM B | | BRAM R |
         | (A mat)| | (B mat)| | (Result|
         +----+---+ +---+----+ +---^----+
              |          |          |
         +----v----------v----------+----+
         |       matmul_control_fsm      |
         +----+---------+----------+-----+
              |         |          |
         +----v---------v----------v-----+
         |        systolic_array         |
         |  +----+ +----+ +----+ +----+  |
         |  |PE00| |PE01| |PE02| |PE03|  |
         |  +----+ +----+ +----+ +----+  |
         |  |PE10| |PE11| |PE12| |PE13|  |
         |  +----+ +----+ +----+ +----+  |
         |  |PE20| |PE21| |PE22| |PE23|  |
         |  +----+ +----+ +----+ +----+  |
         |  |PE30| |PE31| |PE32| |PE33|  |
         |  +----+ +----+ +----+ +----+  |
         +-------------------------------+
```

## Module Hierarchy

```
matmul_top
├── axi_lite_slave          — AXI4-Lite register interface
└── matmul_core             — Compute core
    ├── bram_matrix (x3)    — Dual-port BRAM for A, B, Result
    ├── systolic_array       — NxN PE grid
    │   └── processing_element (NxN instances)
    │       └── mac_unit     — 2-stage pipelined MAC
    └── matmul_control_fsm   — State machine
```

## Systolic Array Dataflow

**Weight-stationary**: Matrix B elements are pre-loaded into PEs and held static.
Matrix A elements stream horizontally (left to right) through the array.
Partial sums accumulate vertically (top to bottom).

```
PE(r,c) holds weight B[r][c]
PE(r,c) computes: acc_out = a_in * B[r][c] + acc_in
PE(r,c) passes:   a_out = a_in (delayed 1 cycle)
```

For C[i][j] = sum_k(A[i][k] * B[k][j]):
- A[i][k] flows through row k horizontally
- At PE(k,j): multiply by B[k][j], add to running sum from PE(k-1,j)
- PE(N-1,j) outputs the final C[i][j]

## FSM States

```
IDLE --> LOAD_B --> COMPUTE --> DRAIN --> STORE --> DONE
                      ^                    |
                      +--------------------+
                      (next row of A)
```

The FSM processes one row of matrix A at a time:
1. **LOAD_B**: Load all B[r][c] into PE weight registers (N^2 cycles)
2. **COMPUTE**: Feed A[i][0..N-1] into array row 0 (N cycles)
3. **DRAIN**: Wait for pipeline flush (3N+4 cycles)
4. **STORE**: Capture result_out and write to BRAM R (N cycles)
5. Repeat COMPUTE-DRAIN-STORE for each row of A
6. **DONE**: Signal completion

## Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| MATRIX_DIM | 4 | Matrix dimension N (NxN) |
| DATA_WIDTH | 16 | Input element width (signed) |
| ACC_WIDTH | 32 | Accumulator width |

## Resource Utilization (Estimated)

| Config | LUTs | FFs | DSPs | BRAM18K |
|--------|------|-----|------|---------|
| 4x4 | ~800 | ~600 | 16 | 3 |
| 8x8 | ~2400 | ~2000 | 64 | 6 |
| 9x9 (max A7-35T) | ~3000 | ~2500 | 81 | 6 |
