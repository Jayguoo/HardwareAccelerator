//=============================================================================
// tb_helpers_pkg.sv — Shared Testbench Utilities
//
// Provides AXI4-Lite Bus Functional Model (BFM) tasks and utilities.
//=============================================================================

`timescale 1ns / 1ps

package tb_helpers_pkg;

    parameter int AXI_ADDR_WIDTH = 16;
    parameter int AXI_DATA_WIDTH = 32;

endpackage
