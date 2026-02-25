# AXI4-Lite Register Map

## Control/Status Registers

| Offset | Name | R/W | Width | Description |
|--------|------|-----|-------|-------------|
| 0x0000 | CTRL_REG | W | 32 | Control register |
| 0x0004 | STATUS_REG | R | 32 | Status register |
| 0x0008 | DIM_REG | R/W | 8 | Matrix dimension (1 to MATRIX_DIM) |
| 0x000C | CYCLE_COUNT | R | 32 | Clock cycles for last computation |
| 0x0010 | VERSION_REG | R | 32 | IP version (0x4D4D_0100 = "MM" v1.0) |
| 0x0014 | CAPABILITY | R | 32 | Hardware capabilities |

### CTRL_REG (0x0000) — Write Only

| Bit | Name | Description |
|-----|------|-------------|
| 0 | START | Write 1 to begin matrix multiplication |
| 1 | CLEAR_DONE | Write 1 to acknowledge completion and return to IDLE |
| 2 | SOFT_RESET | Write 1 to reset the compute core |
| 31:3 | Reserved | |

### STATUS_REG (0x0004) — Read Only

| Bit | Name | Description |
|-----|------|-------------|
| 0 | IDLE | 1 = Core is idle, ready for new operation |
| 1 | DONE | 1 = Computation complete, results available |
| 2 | BUSY | 1 = Computation in progress |
| 3 | ERROR | 1 = Error occurred |
| 31:4 | Reserved | |

### CAPABILITY_REG (0x0014) — Read Only

| Bits | Name | Description |
|------|------|-------------|
| 7:0 | MAX_DIM | Maximum supported matrix dimension |
| 15:8 | DATA_WIDTH | Input data width in bits |
| 23:16 | ACC_WIDTH | Accumulator width in bits |
| 31:24 | Reserved | |

## Matrix Data Regions

| Offset Range | Name | R/W | Description |
|-------------|------|-----|-------------|
| 0x0100 - 0x01FC | MAT_A | R/W | Matrix A elements (row-major, 32-bit per element) |
| 0x0200 - 0x02FC | MAT_B | R/W | Matrix B elements (row-major, 32-bit per element) |
| 0x0400 - 0x04FC | MAT_R | R | Result matrix elements (32-bit per element) |

Element address: `BASE + (row * MATRIX_DIM + col) * 4`

For 4x4 matrices: 16 elements x 4 bytes = 64 bytes per matrix.

## Programming Sequence

1. Write matrix A elements to 0x0100-0x013C
2. Write matrix B elements to 0x0200-0x023C
3. Write CTRL_REG = 0x01 (START)
4. Poll STATUS_REG until bit 1 (DONE) = 1
5. Read CYCLE_COUNT for performance data
6. Read result elements from 0x0400-0x043C
7. Write CTRL_REG = 0x02 (CLEAR_DONE) to return to IDLE
