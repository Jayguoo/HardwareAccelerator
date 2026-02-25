//=============================================================================
// matmul_pkg.sv — Shared parameters, types, and constants
// Matrix Multiply Accelerator
//=============================================================================

package matmul_pkg;

    // Matrix dimensions (default 4x4 for verification)
    parameter int MATRIX_DIM     = 4;

    // Data widths
    parameter int DATA_WIDTH     = 16;   // Input element width (INT16 signed)
    parameter int ACC_WIDTH      = 32;   // Accumulator width (prevents overflow)
    parameter int RESULT_WIDTH   = 32;   // Output result width

    // AXI-Lite parameters
    parameter int AXI_ADDR_WIDTH = 16;   // 64KB address space
    parameter int AXI_DATA_WIDTH = 32;   // Standard 32-bit AXI data

    // Derived parameters
    parameter int NUM_PES        = MATRIX_DIM * MATRIX_DIM;
    parameter int BRAM_DEPTH     = MATRIX_DIM * MATRIX_DIM;
    parameter int BRAM_ADDR_W    = $clog2(BRAM_DEPTH);

    // IP version
    parameter logic [31:0] IP_VERSION = 32'h4D4D_0100; // "MM" v1.0

    // FSM states
    typedef enum logic [3:0] {
        ST_IDLE       = 4'h0,
        ST_LOAD_B     = 4'h1,
        ST_COMPUTE    = 4'h2,
        ST_DRAIN      = 4'h3,
        ST_STORE      = 4'h4,
        ST_DONE       = 4'h5,
        ST_ERROR      = 4'hF
    } fsm_state_t;

    // Status register bit fields
    typedef struct packed {
        logic [27:0] reserved;
        logic        error;
        logic        busy;
        logic        done;
        logic        idle;
    } status_reg_t;

    // Control register bit fields
    typedef struct packed {
        logic [28:0] reserved;
        logic        soft_reset;
        logic        clear_done;
        logic        start;
    } control_reg_t;

    // AXI register offsets (byte addresses)
    parameter logic [15:0] ADDR_CTRL_REG       = 16'h0000;
    parameter logic [15:0] ADDR_STATUS_REG     = 16'h0004;
    parameter logic [15:0] ADDR_DIM_REG        = 16'h0008;
    parameter logic [15:0] ADDR_CYCLE_COUNT    = 16'h000C;
    parameter logic [15:0] ADDR_VERSION_REG    = 16'h0010;
    parameter logic [15:0] ADDR_CAPABILITY_REG = 16'h0014;
    parameter logic [15:0] ADDR_MAT_A_BASE     = 16'h0100;
    parameter logic [15:0] ADDR_MAT_B_BASE     = 16'h0200;
    parameter logic [15:0] ADDR_MAT_R_BASE     = 16'h0400;

endpackage
