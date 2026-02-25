//=============================================================================
// systolic_array.sv — NxN Weight-Stationary Systolic Array
//
// Architecture:
//   - NxN grid of Processing Elements (PEs) via generate
//   - Horizontal wiring: a_out[r][c] -> a_in[r][c+1] (left to right)
//   - Vertical wiring:   acc_out[r][c] -> acc_in[r+1][c] (top to bottom)
//   - Top row acc_in = 0 (no partial sum from above)
//   - Left column a_in = a_row_in[r] (external input per row)
//   - Bottom row acc_out = result_out[c] (final results)
//
// Weight loading:
//   - Each PE(r,c) loads B[r][c] via targeted load_weight enable
//   - Sequential: iterate all (r,c) during LOAD_B phase
//
// Input skewing is handled externally by the control FSM.
//=============================================================================

module systolic_array #(
    parameter int MATRIX_DIM = 4,
    parameter int DATA_WIDTH = 16,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // Control (broadcast)
    input  logic                            clear_acc,
    input  logic                            enable,

    // Weight loading interface
    input  logic [$clog2(MATRIX_DIM)-1:0]   weight_row,
    input  logic [$clog2(MATRIX_DIM)-1:0]   weight_col,
    input  logic signed [DATA_WIDTH-1:0]    weight_data,
    input  logic                            weight_valid,

    // Matrix A input — one element per row, fed from left edge
    input  logic signed [DATA_WIDTH-1:0]    a_row_in  [MATRIX_DIM],

    // Result output — bottom edge of array
    output logic signed [ACC_WIDTH-1:0]     result_out [MATRIX_DIM]
);

    // Internal wires for horizontal A propagation
    logic signed [DATA_WIDTH-1:0] a_wire [MATRIX_DIM][MATRIX_DIM];

    // Internal wires for vertical accumulator propagation
    logic signed [ACC_WIDTH-1:0] acc_wire [MATRIX_DIM][MATRIX_DIM];

    // Per-PE weight load enable
    logic load_weight_en [MATRIX_DIM][MATRIX_DIM];

    // Generate weight load enable signals
    always_comb begin
        for (int r = 0; r < MATRIX_DIM; r++) begin
            for (int c = 0; c < MATRIX_DIM; c++) begin
                load_weight_en[r][c] = weight_valid &&
                                        (weight_row == r[$clog2(MATRIX_DIM)-1:0]) &&
                                        (weight_col == c[$clog2(MATRIX_DIM)-1:0]);
            end
        end
    end

    // Generate NxN PE grid
    genvar r, c;
    generate
        for (r = 0; r < MATRIX_DIM; r++) begin : gen_row
            for (c = 0; c < MATRIX_DIM; c++) begin : gen_col

                // Determine a_in source
                logic signed [DATA_WIDTH-1:0] pe_a_in;
                logic signed [ACC_WIDTH-1:0]  pe_acc_in;

                // Left edge gets external input, others get from left neighbor
                if (c == 0) begin : gen_a_left
                    assign pe_a_in = a_row_in[r];
                end else begin : gen_a_chain
                    assign pe_a_in = a_wire[r][c-1];
                end

                // Top edge gets zero, others get from top neighbor
                if (r == 0) begin : gen_acc_top
                    assign pe_acc_in = '0;
                end else begin : gen_acc_chain
                    assign pe_acc_in = acc_wire[r-1][c];
                end

                processing_element #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH)
                ) pe_inst (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .load_weight (load_weight_en[r][c]),
                    .clear_acc   (clear_acc),
                    .enable      (enable),
                    .a_in        (pe_a_in),
                    .a_out       (a_wire[r][c]),
                    .acc_in      (pe_acc_in),
                    .acc_out     (acc_wire[r][c]),
                    .weight_in   (weight_data)
                );

            end
        end
    endgenerate

    // Output results from bottom row
    generate
        for (genvar j = 0; j < MATRIX_DIM; j++) begin : gen_result
            assign result_out[j] = acc_wire[MATRIX_DIM-1][j];
        end
    endgenerate

endmodule
