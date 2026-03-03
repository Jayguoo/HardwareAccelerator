//=============================================================================
// bram_matrix.sv — True Dual-Port Block RAM (Inferred)
//
// Coded for Xilinx BRAM inference (no IP dependency).
// Port A: Host side (AXI-Lite read/write)
// Port B: Compute side (FSM read/write)
//
// Both ports operate on the same clock domain.
//=============================================================================

module bram_matrix #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 16,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic                    clk,

    // Port A (host side)
    input  logic                    a_en,
    input  logic                    a_we,
    input  logic [ADDR_WIDTH-1:0]   a_addr,
    input  logic [DATA_WIDTH-1:0]   a_wdata,
    output logic [DATA_WIDTH-1:0]   a_rdata,

    // Port B (compute side)
    input  logic                    b_en,
    input  logic                    b_we,
    input  logic [ADDR_WIDTH-1:0]   b_addr,
    input  logic [DATA_WIDTH-1:0]   b_wdata,
    output logic [DATA_WIDTH-1:0]   b_rdata
);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [DEPTH];

    // Initialize to zero (for simulation)
    initial begin
        for (int i = 0; i < DEPTH; i++)
            mem[i] = '0;
    end

    // Port A: write-first mode
    always_ff @(posedge clk) begin
        if (a_en) begin
            if (a_we) begin
                mem[a_addr] <= a_wdata;
                a_rdata     <= a_wdata;  // Write-first
            end else begin
                a_rdata <= mem[a_addr];
            end
        end
    end

    // Port B: write-first mode
    always_ff @(posedge clk) begin
        if (b_en) begin
            if (b_we) begin
                mem[b_addr] <= b_wdata;
                b_rdata     <= b_wdata;  // Write-first
            end else begin
                b_rdata <= mem[b_addr];
            end
        end
    end

endmodule
