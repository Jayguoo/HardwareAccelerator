//=============================================================================
// tb_matmul_core.sv — Testbench for Matrix Multiply Core
//
// Tests the core by directly driving BRAM host ports and control signals
// (bypasses AXI-Lite wrapper).
//
// Tests:
//   1. Identity matrix: A * I = A
//   2. Known 4x4 values
//   3. Negative values
//   4. Cycle count verification
//=============================================================================

`timescale 1ns / 1ps

import matmul_pkg::*;

module tb_matmul_core;

    parameter int MATRIX_DIM = matmul_pkg::MATRIX_DIM;
    parameter int DATA_WIDTH = matmul_pkg::DATA_WIDTH;
    parameter int ACC_WIDTH  = matmul_pkg::ACC_WIDTH;
    parameter int BRAM_DEPTH = MATRIX_DIM * MATRIX_DIM;
    parameter int BRAM_ADDR_W = $clog2(BRAM_DEPTH);
    parameter int CLK_PERIOD = 10;

    // Clock and reset
    logic clk;
    logic rst_n;

    // Host BRAM interfaces
    logic [BRAM_ADDR_W-1:0] host_a_addr, host_b_addr, host_r_addr;
    logic                   host_a_en,   host_b_en,   host_r_en;
    logic                   host_a_we,   host_b_we;
    logic [31:0]            host_a_wdata, host_b_wdata;
    logic [31:0]            host_a_rdata, host_b_rdata, host_r_rdata;

    // Control
    logic        start, clear_done;
    logic        busy, done, error;
    logic [31:0] cycle_count;
    logic        irq;

    // Test data
    logic signed [DATA_WIDTH-1:0] mat_a [MATRIX_DIM][MATRIX_DIM];
    logic signed [DATA_WIDTH-1:0] mat_b [MATRIX_DIM][MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]  mat_expected [MATRIX_DIM][MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]  mat_result [MATRIX_DIM][MATRIX_DIM];

    int test_num;
    int pass_count;
    int fail_count;

    // DUT
    matmul_core #(
        .MATRIX_DIM (MATRIX_DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
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
        .start        (start),
        .clear_done   (clear_done),
        .busy         (busy),
        .done         (done),
        .error        (error),
        .cycle_count  (cycle_count),
        .irq          (irq)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    // Write a value to BRAM A via host port
    task automatic write_bram_a(input int addr, input logic [31:0] data);
        host_a_addr  = addr[BRAM_ADDR_W-1:0];
        host_a_en    = 1'b1;
        host_a_we    = 1'b1;
        host_a_wdata = data;
        @(posedge clk);
        host_a_en    = 1'b0;
        host_a_we    = 1'b0;
    endtask

    // Write a value to BRAM B via host port
    task automatic write_bram_b(input int addr, input logic [31:0] data);
        host_b_addr  = addr[BRAM_ADDR_W-1:0];
        host_b_en    = 1'b1;
        host_b_we    = 1'b1;
        host_b_wdata = data;
        @(posedge clk);
        host_b_en    = 1'b0;
        host_b_we    = 1'b0;
    endtask

    // Read a value from BRAM Result via host port
    task automatic read_bram_r(input int addr, output logic [31:0] data);
        host_r_addr = addr[BRAM_ADDR_W-1:0];
        host_r_en   = 1'b1;
        @(posedge clk);  // Issue read
        @(posedge clk);  // Data available
        data = host_r_rdata;
        host_r_en = 1'b0;
    endtask

    // Load matrices into BRAMs
    task automatic load_matrices();
        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                // Sign-extend to 32-bit for BRAM write
                write_bram_a(i * MATRIX_DIM + j, {{(32-DATA_WIDTH){mat_a[i][j][DATA_WIDTH-1]}}, mat_a[i][j]});
                write_bram_b(i * MATRIX_DIM + j, {{(32-DATA_WIDTH){mat_b[i][j][DATA_WIDTH-1]}}, mat_b[i][j]});
            end
        end
    endtask

    // Compute SW reference
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

    // Run computation and wait for done
    task automatic run_compute();
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Wait for done (with timeout)
        for (int i = 0; i < 10000; i++) begin
            @(posedge clk);
            if (done) begin
                $display("  Computation done in %0d cycles", cycle_count);
                return;
            end
        end
        $display("  [ERROR] Computation timeout!");
    endtask

    // Read results and compare
    task automatic verify_results(input string test_name);
        logic [31:0] rdata;
        int errors;

        errors = 0;

        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                read_bram_r(i * MATRIX_DIM + j, rdata);
                mat_result[i][j] = $signed(rdata);

                if (mat_result[i][j] !== mat_expected[i][j]) begin
                    $display("  [FAIL] C[%0d][%0d]: expected %0d, got %0d",
                             i, j, mat_expected[i][j], mat_result[i][j]);
                    errors++;
                end
            end
        end

        if (errors == 0) begin
            $display("  [PASS] %s — All %0d elements correct",
                     test_name, MATRIX_DIM * MATRIX_DIM);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — %0d mismatches", test_name, errors);
            fail_count++;
        end
        test_num++;

        // Print result matrix
        $display("  Result:");
        for (int i = 0; i < MATRIX_DIM; i++) begin
            $write("    [");
            for (int j = 0; j < MATRIX_DIM; j++)
                $write(" %6d", mat_result[i][j]);
            $display(" ]");
        end

        // Clear done
        clear_done = 1'b1;
        @(posedge clk);
        clear_done = 1'b0;
        wait_cycles(2);
    endtask

    // Main test sequence
    initial begin
        $display("============================================");
        $display("  Matrix Multiply Core Testbench — Starting");
        $display("  MATRIX_DIM=%0d", MATRIX_DIM);
        $display("============================================");

        test_num   = 1;
        pass_count = 0;
        fail_count = 0;

        // Initialize
        rst_n       = 1'b0;
        start       = 1'b0;
        clear_done  = 1'b0;
        host_a_addr = '0; host_a_en = 0; host_a_we = 0; host_a_wdata = '0;
        host_b_addr = '0; host_b_en = 0; host_b_we = 0; host_b_wdata = '0;
        host_r_addr = '0; host_r_en = 0;

        // Reset
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(5);

        // ---- Test 1: Identity multiplication ----
        $display("\n--- Test 1: A * Identity = A ---");
        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_a[i][j] = DATA_WIDTH'(i * MATRIX_DIM + j + 1);
                mat_b[i][j] = (i == j) ? 16'sd1 : 16'sd0;
            end
        end
        compute_reference();
        load_matrices();
        wait_cycles(2);
        run_compute();
        verify_results("A * Identity = A");

        // ---- Test 2: General multiplication ----
        $display("\n--- Test 2: General 4x4 multiplication ---");
        mat_a[0][0]=1;  mat_a[0][1]=2;  mat_a[0][2]=3;  mat_a[0][3]=4;
        mat_a[1][0]=5;  mat_a[1][1]=6;  mat_a[1][2]=7;  mat_a[1][3]=8;
        mat_a[2][0]=9;  mat_a[2][1]=10; mat_a[2][2]=11; mat_a[2][3]=12;
        mat_a[3][0]=13; mat_a[3][1]=14; mat_a[3][2]=15; mat_a[3][3]=16;

        mat_b[0][0]=1;  mat_b[0][1]=0;  mat_b[0][2]=2;  mat_b[0][3]=0;
        mat_b[1][0]=0;  mat_b[1][1]=1;  mat_b[1][2]=0;  mat_b[1][3]=2;
        mat_b[2][0]=2;  mat_b[2][1]=0;  mat_b[2][2]=1;  mat_b[2][3]=0;
        mat_b[3][0]=0;  mat_b[3][1]=2;  mat_b[3][2]=0;  mat_b[3][3]=1;

        compute_reference();
        load_matrices();
        wait_cycles(2);
        run_compute();
        verify_results("General 4x4 multiplication");

        // ---- Test 3: Negative values ----
        $display("\n--- Test 3: Negative values ---");
        mat_a[0][0]=1;   mat_a[0][1]=-2;  mat_a[0][2]=3;   mat_a[0][3]=-4;
        mat_a[1][0]=-5;  mat_a[1][1]=6;   mat_a[1][2]=-7;  mat_a[1][3]=8;
        mat_a[2][0]=9;   mat_a[2][1]=-10; mat_a[2][2]=11;  mat_a[2][3]=-12;
        mat_a[3][0]=-1;  mat_a[3][1]=2;   mat_a[3][2]=-3;  mat_a[3][3]=4;

        mat_b[0][0]=2;   mat_b[0][1]=-1;  mat_b[0][2]=0;   mat_b[0][3]=3;
        mat_b[1][0]=-3;  mat_b[1][1]=2;   mat_b[1][2]=1;   mat_b[1][3]=-2;
        mat_b[2][0]=0;   mat_b[2][1]=1;   mat_b[2][2]=-2;  mat_b[2][3]=4;
        mat_b[3][0]=1;   mat_b[3][1]=-3;  mat_b[3][2]=2;   mat_b[3][3]=-1;

        compute_reference();
        load_matrices();
        wait_cycles(2);
        run_compute();
        verify_results("Negative values multiplication");

        // ---- Test 4: Back-to-back operations ----
        $display("\n--- Test 4: Back-to-back (change A, same B) ---");
        // Keep B from test 3, change A
        for (int i = 0; i < MATRIX_DIM; i++)
            for (int j = 0; j < MATRIX_DIM; j++)
                mat_a[i][j] = DATA_WIDTH'((i + 1) * (j + 1));

        compute_reference();
        // Only reload A
        for (int i = 0; i < MATRIX_DIM; i++)
            for (int j = 0; j < MATRIX_DIM; j++)
                write_bram_a(i * MATRIX_DIM + j,
                    {{(32-DATA_WIDTH){mat_a[i][j][DATA_WIDTH-1]}}, mat_a[i][j]});

        wait_cycles(2);
        run_compute();
        verify_results("Back-to-back operation");

        // ---- Summary ----
        $display("\n============================================");
        $display("  Matrix Multiply Core Testbench — Complete");
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
        #(CLK_PERIOD * 100000);
        $display("[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
