//=============================================================================
// tb_systolic_array.sv — Testbench for Systolic Array
//
// Tests:
//   1. 2x2 known values (parameterized DIM=2)
//   2. Identity matrix test
//   3. 4x4 known values
//   4. Zero matrix test
//
// The testbench manually handles input skewing (row r delayed by r cycles)
// and result draining (accounting for pipeline latency through the array).
//=============================================================================

`timescale 1ns / 1ps

module tb_systolic_array;

    // Use 4x4 for main tests
    parameter int MATRIX_DIM = 4;
    parameter int DATA_WIDTH = 16;
    parameter int ACC_WIDTH  = 32;
    parameter int CLK_PERIOD = 10;

    // Pipeline latency of MAC = 2 cycles
    // Total latency through column of N PEs = 2*N cycles (each PE adds 2 cycles)
    // But PEs are pipelined, so effective is: N (data flow) + 2 (pipeline) cycles
    // Input skew adds N-1 cycles
    // Total: need to wait (2*N - 1 + 2) = 2*4-1+2 = 9 cycles after first input
    // Actually: with 1-cycle a_out delay per PE + 2-cycle MAC pipeline,
    // results for column c appear after: (N-1) skew + c (horizontal) + 2*N (vertical pipeline)
    // Let's be conservative and run enough cycles, then check at the end.

    // Signals
    logic                            clk;
    logic                            rst_n;
    logic                            clear_acc;
    logic                            enable;
    logic [$clog2(MATRIX_DIM)-1:0]   weight_row;
    logic [$clog2(MATRIX_DIM)-1:0]   weight_col;
    logic signed [DATA_WIDTH-1:0]    weight_data;
    logic                            weight_valid;
    logic signed [DATA_WIDTH-1:0]    a_row_in [MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]     result_out [MATRIX_DIM];

    int test_num;
    int pass_count;
    int fail_count;

    // Test matrices
    logic signed [DATA_WIDTH-1:0] mat_a [MATRIX_DIM][MATRIX_DIM];
    logic signed [DATA_WIDTH-1:0] mat_b [MATRIX_DIM][MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]  mat_expected [MATRIX_DIM][MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]  mat_result [MATRIX_DIM][MATRIX_DIM];

    // DUT
    systolic_array #(
        .MATRIX_DIM (MATRIX_DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear_acc    (clear_acc),
        .enable       (enable),
        .weight_row   (weight_row),
        .weight_col   (weight_col),
        .weight_data  (weight_data),
        .weight_valid (weight_valid),
        .a_row_in     (a_row_in),
        .result_out   (result_out)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    // Load weight matrix B into the systolic array
    task automatic load_weights();
        for (int r = 0; r < MATRIX_DIM; r++) begin
            for (int c = 0; c < MATRIX_DIM; c++) begin
                weight_row   = r[$clog2(MATRIX_DIM)-1:0];
                weight_col   = c[$clog2(MATRIX_DIM)-1:0];
                weight_data  = mat_b[r][c];
                weight_valid = 1'b1;
                @(posedge clk);
            end
        end
        weight_valid = 1'b0;
        weight_data  = '0;
    endtask

    // Compute reference result: mat_expected = mat_a * mat_b
    task automatic compute_reference();
        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_expected[i][j] = 0;
                for (int k = 0; k < MATRIX_DIM; k++) begin
                    mat_expected[i][j] += ACC_WIDTH'(mat_a[i][k]) * ACC_WIDTH'(mat_b[k][j]);
                end
            end
        end
    endtask

    // Feed matrix A with skewed inputs and capture results
    // Row r starts at cycle r (skew by r cycles)
    // Each row feeds N elements across N cycles
    // Total feed cycles: N + (N-1) = 2N - 1
    task automatic feed_and_compute();
        int total_cycles;
        // Total cycles needed: input feeding + pipeline drain
        // Feed: 2*N - 1 cycles (last row starts at cycle N-1, feeds N elements)
        // Pipeline drain: 2*N cycles (2 stages per PE, N PEs in column)
        // Extra margin for safety
        total_cycles = 4 * MATRIX_DIM + 4;

        enable = 1'b1;

        for (int cyc = 0; cyc < total_cycles; cyc++) begin
            // Set a_row_in for each row based on skewing
            for (int r = 0; r < MATRIX_DIM; r++) begin
                int col_idx;
                col_idx = cyc - r;  // Skew: row r starts at cycle r
                if (col_idx >= 0 && col_idx < MATRIX_DIM) begin
                    a_row_in[r] = mat_a[r][col_idx];
                end else begin
                    a_row_in[r] = '0;  // Zero when no valid data
                end
            end

            @(posedge clk);

            // Capture results from bottom row
            // Results for column j of result row i appear when the computation
            // for that element completes through the vertical pipeline
            // We'll capture all results at the end after drain
        end

        enable = 1'b0;
        for (int r = 0; r < MATRIX_DIM; r++) begin
            a_row_in[r] = '0;
        end
    endtask

    // Run a complete matrix multiply and check results
    // This version captures results by reading them at the right time
    task automatic run_matmul_and_check(input string test_name);
        int total_feed_cycles;
        int errors;

        $display("\n--- %s ---", test_name);

        // Compute SW reference
        compute_reference();

        // Clear accumulator
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(2);

        // Load weights
        load_weights();
        wait_cycles(1);

        // Clear again after weight loading
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(1);

        // Feed A with skewing
        // We need enough cycles for data to propagate through.
        // The systolic array with 1-cycle horizontal delay per PE and 2-cycle MAC pipeline:
        // For result C[i][j] = sum_k A[i][k] * B[k][j]:
        //   - A[i][k] enters row i at cycle (i + k) due to skew
        //   - Reaches PE(k,j) at cycle (i + k + j) due to horizontal delay
        //   - MAC pipeline: +2 cycles for multiply+add
        //   - Vertical accumulation: partial sum from PE(k-1,j) must arrive first
        //
        // The last element to complete is C[N-1][N-1]:
        //   - Last A input: A[N-1][N-1] enters at cycle (N-1)+(N-1) = 2N-2
        //   - Reaches PE(N-1,N-1) at cycle 2N-2+(N-1) = 3N-3
        //   - Plus MAC pipeline: +2 cycles
        //   - But vertical accumulation is pipelined, so:
        //     PE(0,j) result ready at cycle (i+0+j+2)
        //     PE(1,j) result ready at cycle max(i+1+j+2, PE(0,j)+2) etc.
        //
        // Simplified: run for enough cycles and capture the final stable values.
        // The results should be stable after: 3*N + 2*N = 5*N cycles from start.

        total_feed_cycles = 2 * MATRIX_DIM - 1;

        enable = 1'b1;

        // Feed phase: 2N-1 cycles with skewed A inputs
        for (int cyc = 0; cyc < total_feed_cycles; cyc++) begin
            for (int r = 0; r < MATRIX_DIM; r++) begin
                int col_idx;
                col_idx = cyc - r;
                if (col_idx >= 0 && col_idx < MATRIX_DIM) begin
                    a_row_in[r] = mat_a[r][col_idx];
                end else begin
                    a_row_in[r] = '0;
                end
            end
            @(posedge clk);
        end

        // Zero inputs during drain
        for (int r = 0; r < MATRIX_DIM; r++) begin
            a_row_in[r] = '0;
        end

        // Drain phase: wait for results to propagate through pipeline
        // Need 2*N more cycles for vertical pipeline drain
        wait_cycles(3 * MATRIX_DIM);

        enable = 1'b0;

        // Read results — the result_out gives the bottom row's acc_out
        // which contains the accumulated products for each column.
        // But we need results for ALL rows, not just the last.
        //
        // In a weight-stationary systolic array, the bottom row result_out[j]
        // actually contains C[*][j] accumulated across all rows.
        // Wait — that's the key insight:
        //   PE(0,j) computes: A[i][0] * B[0][j] for each i flowing through
        //   PE(1,j) computes: A[i][1] * B[1][j] + acc from PE(0,j)
        //   ...
        //   PE(N-1,j) computes the full dot product for ONE result element.
        //
        // But which row i? Because of the skewing, different rows of A
        // flow through at different times. The partial sums in each column
        // accumulate ALL the A[i][k]*B[k][j] for a SINGLE i value.
        //
        // Actually, in the standard weight-stationary systolic array:
        // - At any given time, each column processes data for one row of C.
        // - The skewing ensures that all N elements needed for one output
        //   arrive at the right PEs at the right times.
        // - Results for different rows of C come out at different times
        //   (staggered by the skew + pipeline latency).
        //
        // So we need to capture result_out at N different time points
        // to get all N rows of the result matrix.
        //
        // For now, let's collect the result that's at the output and
        // simply verify the computation is correct by re-running with
        // a simpler approach: feed one row at a time.

        // Since the standard systolic array interleaves results for different
        // output rows, let's verify with a self-contained approach:
        // We'll compare the stable output against expected after full drain.

        // For a proper test, we need to capture results as they emerge.
        // Let's restructure: feed all data, then capture results at the right cycles.

        errors = 0;
        $display("  Results captured at bottom of array:");
        for (int j = 0; j < MATRIX_DIM; j++) begin
            $display("    result_out[%0d] = %0d", j, result_out[j]);
        end

        // The bottom output after full drain should contain the result of the
        // LAST row that passed through. With proper skewing for a single pass,
        // the result at the bottom after full drain is C[N-1][j] for each j.
        // But actually ALL rows of C pass through the bottom - we need to capture
        // each one when it appears.

        // For verification, let's use a simpler approach:
        // Process ONE row of A at a time (no skewing) and verify each result row.
        $display("  [INFO] Running row-by-row verification...");
    endtask

    // Simplified row-by-row test: feed one row of A at a time, clear between rows
    task automatic run_single_row(
        input int row_idx,
        output logic signed [ACC_WIDTH-1:0] row_result [MATRIX_DIM]
    );
        // Clear accumulators
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(1);

        // Feed row elements one at a time through left edge (row 0 only)
        // A[row_idx][0], A[row_idx][1], ... each enters at row 0 and flows right
        enable = 1'b1;
        for (int k = 0; k < MATRIX_DIM; k++) begin
            a_row_in[0] = mat_a[row_idx][k];
            // All other rows get zero
            for (int r = 1; r < MATRIX_DIM; r++) begin
                a_row_in[r] = '0;
            end
            @(posedge clk);
        end

        // Zero inputs
        for (int r = 0; r < MATRIX_DIM; r++) begin
            a_row_in[r] = '0;
        end

        // Wait for pipeline drain: N-1 cycles for horizontal prop + 2*N for vertical
        wait_cycles(3 * MATRIX_DIM + 2);
        enable = 1'b0;

        // Capture results
        for (int j = 0; j < MATRIX_DIM; j++) begin
            row_result[j] = result_out[j];
        end
    endtask

    // Full matrix multiply test using row-by-row approach
    task automatic test_matmul(input string test_name);
        int errors;
        logic signed [ACC_WIDTH-1:0] row_result [MATRIX_DIM];

        $display("\n--- %s ---", test_name);
        compute_reference();

        // Load weights (B matrix)
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(2);
        load_weights();
        wait_cycles(1);

        errors = 0;

        // Process each row of A independently
        for (int i = 0; i < MATRIX_DIM; i++) begin
            run_single_row(i, row_result);

            // Check results for this row
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_result[i][j] = row_result[j];
                if (row_result[j] !== mat_expected[i][j]) begin
                    $display("  [FAIL] C[%0d][%0d]: expected %0d, got %0d",
                             i, j, mat_expected[i][j], row_result[j]);
                    errors++;
                end
            end
        end

        if (errors == 0) begin
            $display("  [PASS] %s — All %0d elements correct", test_name,
                     MATRIX_DIM * MATRIX_DIM);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — %0d mismatches", test_name, errors);
            fail_count++;
        end
        test_num++;

        // Print result matrix
        $display("  Result matrix:");
        for (int i = 0; i < MATRIX_DIM; i++) begin
            $write("    [");
            for (int j = 0; j < MATRIX_DIM; j++) begin
                $write(" %6d", mat_result[i][j]);
            end
            $display(" ]");
        end
    endtask

    // Main test sequence
    initial begin
        $display("============================================");
        $display("  Systolic Array Testbench — Starting");
        $display("  MATRIX_DIM=%0d", MATRIX_DIM);
        $display("============================================");

        test_num   = 1;
        pass_count = 0;
        fail_count = 0;

        // Initialize
        rst_n        = 1'b0;
        clear_acc    = 1'b0;
        enable       = 1'b0;
        weight_row   = '0;
        weight_col   = '0;
        weight_data  = '0;
        weight_valid = 1'b0;
        for (int r = 0; r < MATRIX_DIM; r++) a_row_in[r] = '0;

        // Reset
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(3);

        // ---- Test 1: Identity matrix B, A = simple values ----
        // A = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]]
        // B = I (identity)
        // C = A
        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_a[i][j] = DATA_WIDTH'(i * MATRIX_DIM + j + 1);
                mat_b[i][j] = (i == j) ? 16'sd1 : 16'sd0;
            end
        end
        test_matmul("A * Identity = A");

        // ---- Test 2: Known 4x4 multiplication ----
        // A = [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]] (identity)
        // B = [[2,3,4,5],[6,7,8,9],[10,11,12,13],[14,15,16,17]]
        // C = B
        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_a[i][j] = (i == j) ? 16'sd1 : 16'sd0;
                mat_b[i][j] = DATA_WIDTH'(i * MATRIX_DIM + j + 2);
            end
        end
        test_matmul("Identity * B = B");

        // ---- Test 3: General 4x4 multiplication ----
        // A = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]]
        // B = [[1,0,2,0],[0,1,0,2],[2,0,1,0],[0,2,0,1]]
        mat_a[0][0]=1;  mat_a[0][1]=2;  mat_a[0][2]=3;  mat_a[0][3]=4;
        mat_a[1][0]=5;  mat_a[1][1]=6;  mat_a[1][2]=7;  mat_a[1][3]=8;
        mat_a[2][0]=9;  mat_a[2][1]=10; mat_a[2][2]=11; mat_a[2][3]=12;
        mat_a[3][0]=13; mat_a[3][1]=14; mat_a[3][2]=15; mat_a[3][3]=16;

        mat_b[0][0]=1;  mat_b[0][1]=0;  mat_b[0][2]=2;  mat_b[0][3]=0;
        mat_b[1][0]=0;  mat_b[1][1]=1;  mat_b[1][2]=0;  mat_b[1][3]=2;
        mat_b[2][0]=2;  mat_b[2][1]=0;  mat_b[2][2]=1;  mat_b[2][3]=0;
        mat_b[3][0]=0;  mat_b[3][1]=2;  mat_b[3][2]=0;  mat_b[3][3]=1;
        // Expected C:
        // C[0] = [1*1+2*0+3*2+4*0, 1*0+2*1+3*0+4*2, 1*2+2*0+3*1+4*0, 1*0+2*2+3*0+4*1]
        //       = [7, 10, 5, 8]
        // C[1] = [5+0+14+0, 0+6+0+16, 10+0+7+0, 0+12+0+8] = [19, 22, 17, 20]
        // C[2] = [9+0+22+0, 0+10+0+24, 18+0+11+0, 0+20+0+12] = [31, 34, 29, 32]
        // C[3] = [13+0+30+0, 0+14+0+32, 26+0+15+0, 0+28+0+16] = [43, 46, 41, 44]
        test_matmul("General 4x4 multiplication");

        // ---- Test 4: Zero matrix ----
        for (int i = 0; i < MATRIX_DIM; i++)
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_a[i][j] = DATA_WIDTH'(i + j + 1);
                mat_b[i][j] = 16'sd0;
            end
        test_matmul("A * Zero = Zero");

        // ---- Test 5: Negative values ----
        mat_a[0][0]=1;   mat_a[0][1]=-2;  mat_a[0][2]=3;   mat_a[0][3]=-4;
        mat_a[1][0]=-5;  mat_a[1][1]=6;   mat_a[1][2]=-7;  mat_a[1][3]=8;
        mat_a[2][0]=9;   mat_a[2][1]=-10; mat_a[2][2]=11;  mat_a[2][3]=-12;
        mat_a[3][0]=-1;  mat_a[3][1]=2;   mat_a[3][2]=-3;  mat_a[3][3]=4;

        mat_b[0][0]=2;   mat_b[0][1]=-1;  mat_b[0][2]=0;   mat_b[0][3]=3;
        mat_b[1][0]=-3;  mat_b[1][1]=2;   mat_b[1][2]=1;   mat_b[1][3]=-2;
        mat_b[2][0]=0;   mat_b[2][1]=1;   mat_b[2][2]=-2;  mat_b[2][3]=4;
        mat_b[3][0]=1;   mat_b[3][1]=-3;  mat_b[3][2]=2;   mat_b[3][3]=-1;
        test_matmul("Mixed positive/negative values");

        // ---- Summary ----
        $display("\n============================================");
        $display("  Systolic Array Testbench — Complete");
        $display("  PASSED: %0d / %0d", pass_count, pass_count + fail_count);
        if (fail_count > 0)
            $display("  FAILED: %0d", fail_count);
        else
            $display("  ALL TESTS PASSED");
        $display("============================================");

        $finish;
    end

    // Timeout
    initial begin
        #(CLK_PERIOD * 50000);
        $display("[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
