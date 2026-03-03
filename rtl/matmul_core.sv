//=============================================================================
// matmul_core.sv — Matrix Multiply Core
//
// Integration of:
//   - 3x BRAM (Matrix A, Matrix B, Result)
//   - 1x Systolic Array (NxN PEs)
//   - 1x Control FSM
//
// Host accesses BRAMs via port A, FSM uses port B for computation.
//=============================================================================

import matmul_pkg::*;

module matmul_core #(
    parameter int MATRIX_DIM = matmul_pkg::MATRIX_DIM,
    parameter int DATA_WIDTH = matmul_pkg::DATA_WIDTH,
    parameter int ACC_WIDTH  = matmul_pkg::ACC_WIDTH,
    parameter int BRAM_DEPTH = MATRIX_DIM * MATRIX_DIM,
    parameter int BRAM_ADDR_W = $clog2(BRAM_DEPTH)
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Host BRAM A access (port A)
    input  logic [BRAM_ADDR_W-1:0]  host_a_addr,
    input  logic                    host_a_en,
    input  logic                    host_a_we,
    input  logic [31:0]             host_a_wdata,
    output logic [31:0]             host_a_rdata,

    // Host BRAM B access (port A)
    input  logic [BRAM_ADDR_W-1:0]  host_b_addr,
    input  logic                    host_b_en,
    input  logic                    host_b_we,
    input  logic [31:0]             host_b_wdata,
    output logic [31:0]             host_b_rdata,

    // Host BRAM Result access (port A, read-only)
    input  logic [BRAM_ADDR_W-1:0]  host_r_addr,
    input  logic                    host_r_en,
    output logic [31:0]             host_r_rdata,

    // Control
    input  logic                    start,
    input  logic                    clear_done,
    output logic                    busy,
    output logic                    done,
    output logic                    error,
    output logic [31:0]             cycle_count,

    // Interrupt
    output logic                    irq
);

    //=========================================================================
    // Internal Wires — FSM <-> BRAMs
    //=========================================================================
    logic [BRAM_ADDR_W-1:0] fsm_a_addr;
    logic                   fsm_a_en;
    logic [31:0]            fsm_a_rdata;

    logic [BRAM_ADDR_W-1:0] fsm_b_addr;
    logic                   fsm_b_en;
    logic [31:0]            fsm_b_rdata;

    logic [BRAM_ADDR_W-1:0] fsm_r_addr;
    logic                   fsm_r_en;
    logic                   fsm_r_we;
    logic [31:0]            fsm_r_wdata;

    //=========================================================================
    // Internal Wires — FSM <-> Systolic Array
    //=========================================================================
    logic                            sa_clear_acc;
    logic                            sa_enable;
    logic [$clog2(MATRIX_DIM)-1:0]   sa_weight_row;
    logic [$clog2(MATRIX_DIM)-1:0]   sa_weight_col;
    logic signed [DATA_WIDTH-1:0]    sa_weight_data;
    logic                            sa_weight_valid;
    logic signed [DATA_WIDTH-1:0]    sa_a_row_in [MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]     sa_result_out [MATRIX_DIM];

    //=========================================================================
    // BRAM Instances
    //=========================================================================

    // Matrix A BRAM
    bram_matrix #(
        .DATA_WIDTH (32),
        .DEPTH      (BRAM_DEPTH),
        .ADDR_WIDTH (BRAM_ADDR_W)
    ) u_bram_a (
        .clk     (clk),
        // Port A: Host
        .a_en    (host_a_en),
        .a_we    (host_a_we),
        .a_addr  (host_a_addr),
        .a_wdata (host_a_wdata),
        .a_rdata (host_a_rdata),
        // Port B: FSM (read only)
        .b_en    (fsm_a_en),
        .b_we    (1'b0),
        .b_addr  (fsm_a_addr),
        .b_wdata (32'b0),
        .b_rdata (fsm_a_rdata)
    );

    // Matrix B BRAM
    bram_matrix #(
        .DATA_WIDTH (32),
        .DEPTH      (BRAM_DEPTH),
        .ADDR_WIDTH (BRAM_ADDR_W)
    ) u_bram_b (
        .clk     (clk),
        // Port A: Host
        .a_en    (host_b_en),
        .a_we    (host_b_we),
        .a_addr  (host_b_addr),
        .a_wdata (host_b_wdata),
        .a_rdata (host_b_rdata),
        // Port B: FSM (read only)
        .b_en    (fsm_b_en),
        .b_we    (1'b0),
        .b_addr  (fsm_b_addr),
        .b_wdata (32'b0),
        .b_rdata (fsm_b_rdata)
    );

    // Result BRAM
    bram_matrix #(
        .DATA_WIDTH (32),
        .DEPTH      (BRAM_DEPTH),
        .ADDR_WIDTH (BRAM_ADDR_W)
    ) u_bram_r (
        .clk     (clk),
        // Port A: Host (read only)
        .a_en    (host_r_en),
        .a_we    (1'b0),
        .a_addr  (host_r_addr),
        .a_wdata (32'b0),
        .a_rdata (host_r_rdata),
        // Port B: FSM (write)
        .b_en    (fsm_r_en),
        .b_we    (fsm_r_we),
        .b_addr  (fsm_r_addr),
        .b_wdata (fsm_r_wdata),
        .b_rdata ()  // Not used
    );

    //=========================================================================
    // Systolic Array
    //=========================================================================
    systolic_array #(
        .MATRIX_DIM (MATRIX_DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_systolic_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear_acc    (sa_clear_acc),
        .enable       (sa_enable),
        .weight_row   (sa_weight_row),
        .weight_col   (sa_weight_col),
        .weight_data  (sa_weight_data),
        .weight_valid (sa_weight_valid),
        .a_row_in     (sa_a_row_in),
        .result_out   (sa_result_out)
    );

    //=========================================================================
    // Control FSM
    //=========================================================================
    matmul_control_fsm #(
        .MATRIX_DIM (MATRIX_DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_control_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        // Host control
        .start           (start),
        .clear_done      (clear_done),
        .busy            (busy),
        .done            (done),
        .error           (error),
        .cycle_count     (cycle_count),
        // BRAM A
        .bram_a_addr     (fsm_a_addr),
        .bram_a_en       (fsm_a_en),
        .bram_a_rdata    (fsm_a_rdata),
        // BRAM B
        .bram_b_addr     (fsm_b_addr),
        .bram_b_en       (fsm_b_en),
        .bram_b_rdata    (fsm_b_rdata),
        // BRAM Result
        .bram_r_addr     (fsm_r_addr),
        .bram_r_en       (fsm_r_en),
        .bram_r_we       (fsm_r_we),
        .bram_r_wdata    (fsm_r_wdata),
        // Systolic array
        .sa_clear_acc    (sa_clear_acc),
        .sa_enable       (sa_enable),
        .sa_weight_row   (sa_weight_row),
        .sa_weight_col   (sa_weight_col),
        .sa_weight_data  (sa_weight_data),
        .sa_weight_valid (sa_weight_valid),
        .sa_a_row_in     (sa_a_row_in),
        .sa_result_out   (sa_result_out)
    );

    //=========================================================================
    // Interrupt — active-high pulse on done rising edge
    //=========================================================================
    logic done_prev;

    always_ff @(posedge clk) begin
        if (!rst_n)
            done_prev <= 1'b0;
        else
            done_prev <= done;
    end

    assign irq = done & ~done_prev;

endmodule
