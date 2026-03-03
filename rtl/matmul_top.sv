//=============================================================================
// matmul_top.sv — Top-Level Matrix Multiply Accelerator
//
// Integrates:
//   - AXI4-Lite Slave interface
//   - Matrix Multiply Core (systolic array + FSM + BRAMs)
//
// External interface: AXI4-Lite slave + interrupt output
//=============================================================================

import matmul_pkg::*;

module matmul_top #(
    parameter int MATRIX_DIM     = matmul_pkg::MATRIX_DIM,
    parameter int DATA_WIDTH     = matmul_pkg::DATA_WIDTH,
    parameter int ACC_WIDTH      = matmul_pkg::ACC_WIDTH,
    parameter int AXI_ADDR_WIDTH = matmul_pkg::AXI_ADDR_WIDTH,
    parameter int AXI_DATA_WIDTH = matmul_pkg::AXI_DATA_WIDTH,
    parameter int BRAM_DEPTH     = MATRIX_DIM * MATRIX_DIM,
    parameter int BRAM_ADDR_W    = $clog2(BRAM_DEPTH)
)(
    // AXI4-Lite Slave Interface
    input  logic                          S_AXI_ACLK,
    input  logic                          S_AXI_ARESETN,

    input  logic [AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic [2:0]                    S_AXI_AWPROT,
    input  logic                          S_AXI_AWVALID,
    output logic                          S_AXI_AWREADY,

    input  logic [AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  logic [AXI_DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  logic                          S_AXI_WVALID,
    output logic                          S_AXI_WREADY,

    output logic [1:0]                    S_AXI_BRESP,
    output logic                          S_AXI_BVALID,
    input  logic                          S_AXI_BREADY,

    input  logic [AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic [2:0]                    S_AXI_ARPROT,
    input  logic                          S_AXI_ARVALID,
    output logic                          S_AXI_ARREADY,

    output logic [AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output logic [1:0]                    S_AXI_RRESP,
    output logic                          S_AXI_RVALID,
    input  logic                          S_AXI_RREADY,

    // Interrupt
    output logic                          irq
);

    //=========================================================================
    // Internal Wires — AXI Slave <-> Core
    //=========================================================================
    logic [BRAM_ADDR_W-1:0] host_a_addr, host_b_addr, host_r_addr;
    logic                   host_a_en,   host_b_en,   host_r_en;
    logic                   host_a_we,   host_b_we;
    logic [31:0]            host_a_wdata, host_b_wdata;
    logic [31:0]            host_a_rdata, host_b_rdata, host_r_rdata;

    logic        core_start, core_clear_done;
    logic        core_busy, core_done, core_error;
    logic [31:0] core_cycle_count;

    //=========================================================================
    // AXI4-Lite Slave
    //=========================================================================
    axi_lite_slave #(
        .MATRIX_DIM     (MATRIX_DIM),
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_axi_slave (
        .S_AXI_ACLK    (S_AXI_ACLK),
        .S_AXI_ARESETN (S_AXI_ARESETN),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID (S_AXI_ARVALID),
        .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),
        .S_AXI_RVALID  (S_AXI_RVALID),
        .S_AXI_RREADY  (S_AXI_RREADY),
        // Core interface
        .host_a_addr    (host_a_addr),
        .host_a_en      (host_a_en),
        .host_a_we      (host_a_we),
        .host_a_wdata   (host_a_wdata),
        .host_a_rdata   (host_a_rdata),
        .host_b_addr    (host_b_addr),
        .host_b_en      (host_b_en),
        .host_b_we      (host_b_we),
        .host_b_wdata   (host_b_wdata),
        .host_b_rdata   (host_b_rdata),
        .host_r_addr    (host_r_addr),
        .host_r_en      (host_r_en),
        .host_r_rdata   (host_r_rdata),
        .core_start     (core_start),
        .core_clear_done(core_clear_done),
        .core_busy      (core_busy),
        .core_done      (core_done),
        .core_error     (core_error),
        .core_cycle_count(core_cycle_count)
    );

    //=========================================================================
    // Matrix Multiply Core
    //=========================================================================
    matmul_core #(
        .MATRIX_DIM (MATRIX_DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_core (
        .clk          (S_AXI_ACLK),
        .rst_n        (S_AXI_ARESETN),
        .host_a_addr  (host_a_addr),
        .host_a_en    (host_a_en),
        .host_a_we    (host_a_we),
        .host_a_wdata (host_a_wdata),
        .host_a_rdata (host_a_rdata),
        .host_b_addr  (host_b_addr),
        .host_b_en    (host_b_en),
        .host_b_we    (host_b_we),
        .host_b_wdata (host_b_wdata),
        .host_b_rdata (host_b_rdata),
        .host_r_addr  (host_r_addr),
        .host_r_en    (host_r_en),
        .host_r_rdata (host_r_rdata),
        .start        (core_start),
        .clear_done   (core_clear_done),
        .busy         (core_busy),
        .done         (core_done),
        .error        (core_error),
        .cycle_count  (core_cycle_count),
        .irq          (irq)
    );

endmodule
