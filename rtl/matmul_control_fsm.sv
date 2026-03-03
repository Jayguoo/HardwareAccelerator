//=============================================================================
// matmul_control_fsm.sv — Control State Machine for Matrix Multiply Core
//
// States: IDLE -> LOAD_B -> COMPUTE -> DRAIN -> STORE -> DONE
//
// Orchestrates:
//   - Loading weights from BRAM B into systolic array PEs
//   - Feeding matrix A rows with proper skewing into the array
//   - Draining results and writing to BRAM Result
//   - Cycle counting for performance measurement
//
// The FSM processes one row of A at a time (row-by-row approach)
// to simplify result capture from the bottom of the systolic array.
// For each row i of A:
//   1. Clear accumulators
//   2. Feed A[i][0..N-1] into row 0 of the array
//   3. Wait for pipeline drain
//   4. Capture result_out[0..N-1] = C[i][0..N-1]
//   5. Write to result BRAM
// This approach trades throughput for simplicity and correctness.
//=============================================================================

import matmul_pkg::*;

module matmul_control_fsm #(
    parameter int MATRIX_DIM = matmul_pkg::MATRIX_DIM,
    parameter int DATA_WIDTH = matmul_pkg::DATA_WIDTH,
    parameter int ACC_WIDTH  = matmul_pkg::ACC_WIDTH,
    parameter int BRAM_DEPTH = MATRIX_DIM * MATRIX_DIM,
    parameter int BRAM_ADDR_W = $clog2(BRAM_DEPTH)
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // Host control
    input  logic                            start,
    input  logic                            clear_done,
    output logic                            busy,
    output logic                            done,
    output logic                            error,
    output logic [31:0]                     cycle_count,

    // BRAM A read interface (port B of BRAM A)
    output logic [BRAM_ADDR_W-1:0]          bram_a_addr,
    output logic                            bram_a_en,
    input  logic [31:0]                     bram_a_rdata,

    // BRAM B read interface (port B of BRAM B)
    output logic [BRAM_ADDR_W-1:0]          bram_b_addr,
    output logic                            bram_b_en,
    input  logic [31:0]                     bram_b_rdata,

    // BRAM Result write interface (port B of BRAM R)
    output logic [BRAM_ADDR_W-1:0]          bram_r_addr,
    output logic                            bram_r_en,
    output logic                            bram_r_we,
    output logic [31:0]                     bram_r_wdata,

    // Systolic array control
    output logic                            sa_clear_acc,
    output logic                            sa_enable,

    // Systolic array weight loading
    output logic [$clog2(MATRIX_DIM)-1:0]   sa_weight_row,
    output logic [$clog2(MATRIX_DIM)-1:0]   sa_weight_col,
    output logic signed [DATA_WIDTH-1:0]    sa_weight_data,
    output logic                            sa_weight_valid,

    // Systolic array A input (row 0 only for row-by-row processing)
    output logic signed [DATA_WIDTH-1:0]    sa_a_row_in [MATRIX_DIM],

    // Systolic array result output
    input  logic signed [ACC_WIDTH-1:0]     sa_result_out [MATRIX_DIM]
);

    // FSM state
    fsm_state_t state, next_state;

    // Counters
    logic [$clog2(MATRIX_DIM)-1:0] row_cnt;     // Current B row / A col being loaded/processed
    logic [$clog2(MATRIX_DIM)-1:0] col_cnt;     // Current B col being loaded
    logic [$clog2(MATRIX_DIM)-1:0] a_row_idx;   // Current A row being processed
    logic [$clog2(MATRIX_DIM)-1:0] a_col_idx;   // Current A column being fed
    logic [7:0]                    drain_cnt;    // Drain cycle counter
    logic [$clog2(MATRIX_DIM)-1:0] store_cnt;   // Store column counter

    // Cycle counter
    logic [31:0] cycle_cnt_reg;

    // BRAM read pipeline delay (1 cycle)
    logic        bram_read_valid;
    logic        weight_load_phase;
    logic        a_feed_phase;

    // Constants for drain time
    // Each PE has 1-cycle horizontal delay + 2-cycle MAC pipeline
    // For N PEs in a column: need N-1 horizontal + 2*N vertical pipeline
    // Conservative: 3*N + 4 cycles
    localparam int DRAIN_CYCLES = 3 * MATRIX_DIM + 4;

    //=========================================================================
    // State Register
    //=========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    //=========================================================================
    // Next State Logic
    //=========================================================================
    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start)
                    next_state = ST_LOAD_B;
            end

            ST_LOAD_B: begin
                // Loading N*N weights, one per cycle (+ 1 BRAM latency)
                // row_cnt/col_cnt iterate through all elements
                if (row_cnt == MATRIX_DIM-1 && col_cnt == MATRIX_DIM-1 && bram_read_valid)
                    next_state = ST_COMPUTE;
            end

            ST_COMPUTE: begin
                // Feed N elements of current A row
                if (a_col_idx == MATRIX_DIM-1)
                    next_state = ST_DRAIN;
            end

            ST_DRAIN: begin
                // Wait for pipeline to flush
                if (drain_cnt >= DRAIN_CYCLES[7:0])
                    next_state = ST_STORE;
            end

            ST_STORE: begin
                // Write N result elements for current row
                if (store_cnt == MATRIX_DIM-1) begin
                    if (a_row_idx == MATRIX_DIM-1)
                        next_state = ST_DONE;  // All rows processed
                    else
                        next_state = ST_COMPUTE;  // Next row
                end
            end

            ST_DONE: begin
                if (clear_done)
                    next_state = ST_IDLE;
            end

            ST_ERROR: begin
                if (clear_done)
                    next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    //=========================================================================
    // Counter and Control Logic
    //=========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            row_cnt          <= '0;
            col_cnt          <= '0;
            a_row_idx        <= '0;
            a_col_idx        <= '0;
            drain_cnt        <= '0;
            store_cnt        <= '0;
            cycle_cnt_reg    <= '0;
            bram_read_valid  <= 1'b0;
            weight_load_phase <= 1'b0;
            a_feed_phase     <= 1'b0;
        end else begin
            // Default: deassert one-shot signals
            bram_read_valid  <= 1'b0;
            weight_load_phase <= 1'b0;
            a_feed_phase     <= 1'b0;

            case (state)
                ST_IDLE: begin
                    row_cnt       <= '0;
                    col_cnt       <= '0;
                    a_row_idx     <= '0;
                    a_col_idx     <= '0;
                    drain_cnt     <= '0;
                    store_cnt     <= '0;
                    if (start)
                        cycle_cnt_reg <= '0;
                end

                ST_LOAD_B: begin
                    cycle_cnt_reg <= cycle_cnt_reg + 1;

                    // Issue BRAM B reads and track valid data
                    // First cycle: issue read for (0,0)
                    // Each subsequent cycle: issue next read, previous data is valid
                    weight_load_phase <= 1'b1;

                    if (bram_read_valid) begin
                        // Advance to next element
                        if (col_cnt == MATRIX_DIM-1) begin
                            col_cnt <= '0;
                            if (row_cnt < MATRIX_DIM-1)
                                row_cnt <= row_cnt + 1;
                        end else begin
                            col_cnt <= col_cnt + 1;
                        end
                    end

                    // BRAM read takes 1 cycle, so data is valid on the cycle after enable
                    bram_read_valid <= bram_b_en;
                end

                ST_COMPUTE: begin
                    cycle_cnt_reg <= cycle_cnt_reg + 1;
                    a_feed_phase  <= 1'b1;

                    // Feed A elements: A[a_row_idx][a_col_idx]
                    // BRAM A read has 1-cycle latency, so we need to pipeline
                    if (a_col_idx < MATRIX_DIM-1)
                        a_col_idx <= a_col_idx + 1;
                end

                ST_DRAIN: begin
                    cycle_cnt_reg <= cycle_cnt_reg + 1;
                    drain_cnt     <= drain_cnt + 1;
                end

                ST_STORE: begin
                    cycle_cnt_reg <= cycle_cnt_reg + 1;

                    if (store_cnt < MATRIX_DIM-1)
                        store_cnt <= store_cnt + 1;
                    else begin
                        store_cnt <= '0;
                        // Prepare for next row
                        if (a_row_idx < MATRIX_DIM-1) begin
                            a_row_idx <= a_row_idx + 1;
                            a_col_idx <= '0;
                            drain_cnt <= '0;
                        end
                    end
                end

                ST_DONE: begin
                    // Hold cycle count
                end

                default: ;
            endcase
        end
    end

    //=========================================================================
    // Output Logic
    //=========================================================================

    // Status outputs
    assign busy  = (state != ST_IDLE) && (state != ST_DONE) && (state != ST_ERROR);
    assign done  = (state == ST_DONE);
    assign error = (state == ST_ERROR);
    assign cycle_count = cycle_cnt_reg;

    // BRAM B read (weight loading)
    assign bram_b_en   = (state == ST_LOAD_B);
    assign bram_b_addr = row_cnt * MATRIX_DIM + col_cnt;

    // BRAM A read (A element feeding)
    // We need to pre-read: issue read on cycle before we need the data
    assign bram_a_en   = (state == ST_COMPUTE) || (next_state == ST_COMPUTE && state == ST_LOAD_B);
    assign bram_a_addr = a_row_idx * MATRIX_DIM + a_col_idx;

    // Systolic array weight loading
    // Weight data arrives 1 cycle after BRAM read, so we use delayed row/col
    logic [$clog2(MATRIX_DIM)-1:0] weight_row_d, weight_col_d;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            weight_row_d <= '0;
            weight_col_d <= '0;
        end else begin
            weight_row_d <= row_cnt;
            weight_col_d <= col_cnt;
        end
    end

    assign sa_weight_row   = weight_row_d;
    assign sa_weight_col   = weight_col_d;
    assign sa_weight_data  = bram_b_rdata[DATA_WIDTH-1:0];
    assign sa_weight_valid = bram_read_valid && (state == ST_LOAD_B);

    // Systolic array control
    assign sa_clear_acc = (state == ST_LOAD_B && next_state == ST_COMPUTE) ||
                          (state == ST_STORE && next_state == ST_COMPUTE);
    assign sa_enable    = (state == ST_COMPUTE) || (state == ST_DRAIN);

    // Feed A elements into the correct row of the systolic array.
    // A[i][k] must enter row k so that PE(k,j) multiplies by weight B[k][j]
    // and the vertical accumulation produces C[i][j] = sum_k(A[i][k]*B[k][j]).
    // Data from BRAM A arrives 1 cycle after read, so we use delayed signals.
    logic a_data_valid;
    logic [$clog2(MATRIX_DIM)-1:0] a_col_idx_d;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_data_valid <= 1'b0;
            a_col_idx_d  <= '0;
        end else begin
            a_data_valid <= (state == ST_COMPUTE);
            a_col_idx_d  <= a_col_idx;
        end
    end

    always_comb begin
        for (int r = 0; r < MATRIX_DIM; r++) begin
            if (a_data_valid && r[$clog2(MATRIX_DIM)-1:0] == a_col_idx_d)
                sa_a_row_in[r] = bram_a_rdata[DATA_WIDTH-1:0];
            else
                sa_a_row_in[r] = '0;
        end
    end

    // BRAM Result write
    assign bram_r_en    = (state == ST_STORE);
    assign bram_r_we    = (state == ST_STORE);
    assign bram_r_addr  = a_row_idx * MATRIX_DIM + store_cnt;
    assign bram_r_wdata = sa_result_out[store_cnt];

endmodule
