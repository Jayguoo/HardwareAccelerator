//=============================================================================
// axi_lite_slave.sv — AXI4-Lite Slave Register Interface
//
// Implements the register map and BRAM port routing:
//   0x0000: CTRL_REG (W)    — start, clear_done, soft_reset
//   0x0004: STATUS_REG (R)  — idle, done, busy, error
//   0x0008: DIM_REG (R/W)   — matrix dimension config
//   0x000C: CYCLE_COUNT (R) — performance counter
//   0x0010: VERSION_REG (R) — IP version
//   0x0014: CAPABILITY (R)  — max dim, data width, acc width
//   0x0100: MAT_A base      — matrix A data (R/W)
//   0x0200: MAT_B base      — matrix B data (R/W)
//   0x0400: MAT_R base      — result data (R)
//
// AXI4-Lite compliant: single-beat, no burst, no wrap.
//=============================================================================

import matmul_pkg::*;

module axi_lite_slave #(
    parameter int MATRIX_DIM     = matmul_pkg::MATRIX_DIM,
    parameter int DATA_WIDTH     = matmul_pkg::DATA_WIDTH,
    parameter int ACC_WIDTH      = matmul_pkg::ACC_WIDTH,
    parameter int AXI_ADDR_WIDTH = matmul_pkg::AXI_ADDR_WIDTH,
    parameter int AXI_DATA_WIDTH = matmul_pkg::AXI_DATA_WIDTH,
    parameter int BRAM_DEPTH     = MATRIX_DIM * MATRIX_DIM,
    parameter int BRAM_ADDR_W    = $clog2(BRAM_DEPTH)
)(
    // AXI Global
    input  logic                          S_AXI_ACLK,
    input  logic                          S_AXI_ARESETN,

    // Write Address Channel
    input  logic [AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic [2:0]                    S_AXI_AWPROT,
    input  logic                          S_AXI_AWVALID,
    output logic                          S_AXI_AWREADY,

    // Write Data Channel
    input  logic [AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  logic [AXI_DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  logic                          S_AXI_WVALID,
    output logic                          S_AXI_WREADY,

    // Write Response Channel
    output logic [1:0]                    S_AXI_BRESP,
    output logic                          S_AXI_BVALID,
    input  logic                          S_AXI_BREADY,

    // Read Address Channel
    input  logic [AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic [2:0]                    S_AXI_ARPROT,
    input  logic                          S_AXI_ARVALID,
    output logic                          S_AXI_ARREADY,

    // Read Data Channel
    output logic [AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output logic [1:0]                    S_AXI_RRESP,
    output logic                          S_AXI_RVALID,
    input  logic                          S_AXI_RREADY,

    // Core interface — BRAM A
    output logic [BRAM_ADDR_W-1:0]        host_a_addr,
    output logic                          host_a_en,
    output logic                          host_a_we,
    output logic [31:0]                   host_a_wdata,
    input  logic [31:0]                   host_a_rdata,

    // Core interface — BRAM B
    output logic [BRAM_ADDR_W-1:0]        host_b_addr,
    output logic                          host_b_en,
    output logic                          host_b_we,
    output logic [31:0]                   host_b_wdata,
    input  logic [31:0]                   host_b_rdata,

    // Core interface — BRAM Result
    output logic [BRAM_ADDR_W-1:0]        host_r_addr,
    output logic                          host_r_en,
    input  logic [31:0]                   host_r_rdata,

    // Core control
    output logic                          core_start,
    output logic                          core_clear_done,
    input  logic                          core_busy,
    input  logic                          core_done,
    input  logic                          core_error,
    input  logic [31:0]                   core_cycle_count
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
    logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
    logic                      aw_en;      // Write address handshake done
    logic                      w_en;       // Write data handshake done

    // Registers
    logic [7:0]  dim_reg;

    // Write channel state
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_DATA,
        WR_RESP
    } wr_state_t;
    wr_state_t wr_state;

    // Read channel state
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_BRAM_WAIT,
        RD_DATA
    } rd_state_t;
    rd_state_t rd_state;

    logic        rd_is_bram;     // Current read targets a BRAM
    logic [31:0] rd_reg_data;    // Data for register reads

    //=========================================================================
    // Address Region Decode
    //=========================================================================
    function automatic logic is_mat_a_region(input logic [AXI_ADDR_WIDTH-1:0] addr);
        return (addr >= ADDR_MAT_A_BASE) && (addr < ADDR_MAT_B_BASE);
    endfunction

    function automatic logic is_mat_b_region(input logic [AXI_ADDR_WIDTH-1:0] addr);
        return (addr >= ADDR_MAT_B_BASE) && (addr < ADDR_MAT_R_BASE);
    endfunction

    function automatic logic is_mat_r_region(input logic [AXI_ADDR_WIDTH-1:0] addr);
        return (addr >= ADDR_MAT_R_BASE) && (addr < (ADDR_MAT_R_BASE + BRAM_DEPTH * 4));
    endfunction

    // Convert AXI byte address to BRAM word address
    function automatic logic [BRAM_ADDR_W-1:0] to_bram_addr(
        input logic [AXI_ADDR_WIDTH-1:0] axi_addr,
        input logic [AXI_ADDR_WIDTH-1:0] base_addr
    );
        return (axi_addr - base_addr) >> 2;  // Byte to word
    endfunction

    //=========================================================================
    // Write Channel FSM
    //=========================================================================
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            wr_state       <= WR_IDLE;
            S_AXI_AWREADY  <= 1'b0;
            S_AXI_WREADY   <= 1'b0;
            S_AXI_BVALID   <= 1'b0;
            S_AXI_BRESP    <= 2'b00;
            axi_awaddr     <= '0;
            core_start     <= 1'b0;
            core_clear_done <= 1'b0;
            dim_reg        <= MATRIX_DIM[7:0];
            host_a_en      <= 1'b0;
            host_a_we      <= 1'b0;
            host_b_en      <= 1'b0;
            host_b_we      <= 1'b0;
        end else begin
            // Default: deassert one-shot signals
            core_start      <= 1'b0;
            core_clear_done <= 1'b0;
            host_a_en       <= 1'b0;
            host_a_we       <= 1'b0;
            host_b_en       <= 1'b0;
            host_b_we       <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    S_AXI_BVALID <= 1'b0;
                    // Accept both AW and W simultaneously
                    if (S_AXI_AWVALID && S_AXI_WVALID) begin
                        S_AXI_AWREADY <= 1'b1;
                        S_AXI_WREADY  <= 1'b1;
                        axi_awaddr    <= S_AXI_AWADDR;
                        wr_state      <= WR_RESP;

                        // Execute write
                        do_write(S_AXI_AWADDR, S_AXI_WDATA);
                    end else if (S_AXI_AWVALID) begin
                        S_AXI_AWREADY <= 1'b1;
                        axi_awaddr    <= S_AXI_AWADDR;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    S_AXI_AWREADY <= 1'b0;
                    if (S_AXI_WVALID) begin
                        S_AXI_WREADY <= 1'b1;
                        wr_state     <= WR_RESP;

                        // Execute write
                        do_write(axi_awaddr, S_AXI_WDATA);
                    end
                end

                WR_RESP: begin
                    S_AXI_AWREADY <= 1'b0;
                    S_AXI_WREADY  <= 1'b0;
                    S_AXI_BVALID  <= 1'b1;
                    S_AXI_BRESP   <= 2'b00;  // OKAY

                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // Write execution helper (called from within always_ff)
    task automatic do_write(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data
    );
        if (is_mat_a_region(addr)) begin
            host_a_addr  = to_bram_addr(addr, ADDR_MAT_A_BASE);
            host_a_wdata = data;
            host_a_en    = 1'b1;
            host_a_we    = 1'b1;
        end else if (is_mat_b_region(addr)) begin
            host_b_addr  = to_bram_addr(addr, ADDR_MAT_B_BASE);
            host_b_wdata = data;
            host_b_en    = 1'b1;
            host_b_we    = 1'b1;
        end else begin
            // Control registers
            case (addr[7:0])
                ADDR_CTRL_REG[7:0]: begin
                    core_start      = data[0];
                    core_clear_done = data[1];
                end
                ADDR_DIM_REG[7:0]: begin
                    dim_reg = data[7:0];
                end
                default: ; // Ignore writes to read-only or unmapped
            endcase
        end
    endtask

    //=========================================================================
    // Read Channel FSM
    //=========================================================================
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            rd_state      <= RD_IDLE;
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RDATA   <= '0;
            S_AXI_RRESP   <= 2'b00;
            axi_araddr    <= '0;
            rd_is_bram    <= 1'b0;
            rd_reg_data   <= '0;
            host_r_en     <= 1'b0;
        end else begin
            // Default
            host_a_en <= host_a_en; // Keep state from write FSM
            host_b_en <= host_b_en;
            host_r_en <= 1'b0;

            case (rd_state)
                RD_IDLE: begin
                    S_AXI_RVALID <= 1'b0;
                    if (S_AXI_ARVALID) begin
                        S_AXI_ARREADY <= 1'b1;
                        axi_araddr    <= S_AXI_ARADDR;

                        // Determine if BRAM or register read
                        if (is_mat_a_region(S_AXI_ARADDR) ||
                            is_mat_b_region(S_AXI_ARADDR) ||
                            is_mat_r_region(S_AXI_ARADDR)) begin
                            rd_is_bram <= 1'b1;
                            // Issue BRAM read
                            if (is_mat_a_region(S_AXI_ARADDR)) begin
                                host_a_addr = to_bram_addr(S_AXI_ARADDR, ADDR_MAT_A_BASE);
                                host_a_en   = 1'b1;
                            end else if (is_mat_b_region(S_AXI_ARADDR)) begin
                                host_b_addr = to_bram_addr(S_AXI_ARADDR, ADDR_MAT_B_BASE);
                                host_b_en   = 1'b1;
                            end else begin
                                host_r_addr = to_bram_addr(S_AXI_ARADDR, ADDR_MAT_R_BASE);
                                host_r_en   = 1'b1;
                            end
                            rd_state <= RD_BRAM_WAIT;
                        end else begin
                            rd_is_bram <= 1'b0;
                            // Register read — available immediately
                            case (S_AXI_ARADDR[7:0])
                                ADDR_STATUS_REG[7:0]: begin
                                    rd_reg_data <= {28'b0,
                                                    core_error,
                                                    core_busy,
                                                    core_done,
                                                    ~core_busy & ~core_done & ~core_error};
                                end
                                ADDR_DIM_REG[7:0]:
                                    rd_reg_data <= {24'b0, dim_reg};
                                ADDR_CYCLE_COUNT[7:0]:
                                    rd_reg_data <= core_cycle_count;
                                ADDR_VERSION_REG[7:0]:
                                    rd_reg_data <= IP_VERSION;
                                ADDR_CAPABILITY_REG[7:0]:
                                    rd_reg_data <= {8'b0, ACC_WIDTH[7:0], DATA_WIDTH[7:0], MATRIX_DIM[7:0]};
                                default:
                                    rd_reg_data <= '0;
                            endcase
                            rd_state <= RD_DATA;
                        end
                    end
                end

                RD_BRAM_WAIT: begin
                    S_AXI_ARREADY <= 1'b0;
                    // Wait 1 cycle for BRAM read latency
                    rd_state <= RD_DATA;
                end

                RD_DATA: begin
                    S_AXI_ARREADY <= 1'b0;
                    S_AXI_RVALID  <= 1'b1;
                    S_AXI_RRESP   <= 2'b00;  // OKAY

                    if (rd_is_bram) begin
                        // Select BRAM read data
                        if (is_mat_a_region(axi_araddr))
                            S_AXI_RDATA <= host_a_rdata;
                        else if (is_mat_b_region(axi_araddr))
                            S_AXI_RDATA <= host_b_rdata;
                        else
                            S_AXI_RDATA <= host_r_rdata;
                    end else begin
                        S_AXI_RDATA <= rd_reg_data;
                    end

                    if (S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
