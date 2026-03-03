//=============================================================================
// mac_unit.sv — 2-Stage Pipelined Multiply-Accumulate Unit
//
// Pipeline:
//   Stage 1: product_reg = a_in * b_in        (registered multiply)
//   Stage 2: acc_out     = product_reg + acc_in (registered add)
//
// Coded to infer Xilinx DSP48E1 (A/B reg -> M reg -> P reg)
//=============================================================================

module mac_unit #(
    parameter int DATA_WIDTH = 16,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            clear,
    input  logic                            enable,
    input  logic signed [DATA_WIDTH-1:0]    a_in,
    input  logic signed [DATA_WIDTH-1:0]    b_in,
    input  logic signed [ACC_WIDTH-1:0]     acc_in,
    output logic signed [ACC_WIDTH-1:0]     acc_out
);

    // Pipeline stage 1: registered multiply
    logic signed [2*DATA_WIDTH-1:0] product_reg;

    // Pipeline stage 1: delay acc_in to align with product
    logic signed [ACC_WIDTH-1:0] acc_in_reg;

    // Pipeline stage 2: registered accumulate
    logic signed [ACC_WIDTH-1:0] acc_out_reg;

    // Stage 1: Multiply + register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            product_reg <= '0;
            acc_in_reg  <= '0;
        end else if (clear) begin
            product_reg <= '0;
            acc_in_reg  <= '0;
        end else if (enable) begin
            product_reg <= a_in * b_in;
            acc_in_reg  <= acc_in;
        end
    end

    // Stage 2: Add + register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            acc_out_reg <= '0;
        end else if (clear) begin
            acc_out_reg <= '0;
        end else if (enable) begin
            acc_out_reg <= product_reg + acc_in_reg;
        end
    end

    assign acc_out = acc_out_reg;

endmodule
