//=============================================================================
// processing_element.sv — Systolic Array Processing Element
//
// Weight-stationary PE:
//   - Holds one element of matrix B in weight_reg (loaded once)
//   - A elements flow left-to-right with 1-cycle delay (a_in -> a_out)
//   - Partial sums flow top-to-bottom (acc_in + a_in*weight -> acc_out)
//   - Internal MAC is 2-stage pipelined
//=============================================================================

module processing_element #(
    parameter int DATA_WIDTH = 16,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // Control
    input  logic                            load_weight,
    input  logic                            clear_acc,
    input  logic                            enable,

    // Horizontal data flow (A elements, left to right)
    input  logic signed [DATA_WIDTH-1:0]    a_in,
    output logic signed [DATA_WIDTH-1:0]    a_out,

    // Vertical data flow (partial sums, top to bottom)
    input  logic signed [ACC_WIDTH-1:0]     acc_in,
    output logic signed [ACC_WIDTH-1:0]     acc_out,

    // Weight loading
    input  logic signed [DATA_WIDTH-1:0]    weight_in
);

    // Weight register — holds B[i][j], loaded once per computation
    logic signed [DATA_WIDTH-1:0] weight_reg;

    // Horizontal delay register — propagates A rightward with 1-cycle delay
    logic signed [DATA_WIDTH-1:0] a_delay_reg;

    // Weight loading
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            weight_reg <= '0;
        end else if (load_weight) begin
            weight_reg <= weight_in;
        end
    end

    // Horizontal A propagation — 1-cycle delay
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_delay_reg <= '0;
        end else if (clear_acc) begin
            a_delay_reg <= '0;
        end else if (enable) begin
            a_delay_reg <= a_in;
        end
    end

    assign a_out = a_delay_reg;

    // MAC unit — multiply a_in * weight_reg + acc_in
    mac_unit #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_mac (
        .clk     (clk),
        .rst_n   (rst_n),
        .clear   (clear_acc),
        .enable  (enable),
        .a_in    (a_in),
        .b_in    (weight_reg),
        .acc_in  (acc_in),
        .acc_out (acc_out)
    );

endmodule
