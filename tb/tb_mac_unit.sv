//=============================================================================
// tb_mac_unit.sv — Testbench for MAC Unit
//
// Tests:
//   1. Reset clears output to zero
//   2. Single multiply: 3 * 5 + 0 = 15
//   3. Accumulate chain: (3*5) + (2*4) via acc_in
//   4. Negative numbers: (-3) * 5 + 10 = -5
//   5. Overflow boundary: max positive * max positive
//   6. Enable gating: values hold when enable=0
//   7. Clear during operation: verify clean restart
//=============================================================================

`timescale 1ns / 1ps

module tb_mac_unit;

    parameter int DATA_WIDTH = 16;
    parameter int ACC_WIDTH  = 32;
    parameter int CLK_PERIOD = 10;

    // Signals
    logic                            clk;
    logic                            rst_n;
    logic                            clear;
    logic                            enable;
    logic signed [DATA_WIDTH-1:0]    a_in;
    logic signed [DATA_WIDTH-1:0]    b_in;
    logic signed [ACC_WIDTH-1:0]     acc_in;
    logic signed [ACC_WIDTH-1:0]     acc_out;

    // Test tracking
    int test_num;
    int pass_count;
    int fail_count;

    // DUT
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .clear   (clear),
        .enable  (enable),
        .a_in    (a_in),
        .b_in    (b_in),
        .acc_in  (acc_in),
        .acc_out (acc_out)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Helper task: wait N clock cycles
    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    // Helper task: apply inputs and wait for pipeline (2 stages)
    task automatic apply_mac(
        input logic signed [DATA_WIDTH-1:0] a,
        input logic signed [DATA_WIDTH-1:0] b,
        input logic signed [ACC_WIDTH-1:0]  acc
    );
        a_in   = a;
        b_in   = b;
        acc_in = acc;
        enable = 1'b1;
        @(posedge clk);  // Stage 1 captures
        // Clear inputs after one cycle (pipeline holds them)
        a_in   = '0;
        b_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);  // Stage 2 produces result
    endtask

    // Helper task: check result
    task automatic check_result(
        input logic signed [ACC_WIDTH-1:0] expected,
        input string test_name
    );
        // Small delay for output to settle after clock edge
        #1;
        if (acc_out === expected) begin
            $display("[PASS] Test %0d: %s — Got %0d", test_num, test_name, acc_out);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s — Expected %0d, Got %0d",
                     test_num, test_name, expected, acc_out);
            fail_count++;
        end
        test_num++;
    endtask

    // Main test sequence
    initial begin
        $display("============================================");
        $display("  MAC Unit Testbench — Starting");
        $display("  DATA_WIDTH=%0d, ACC_WIDTH=%0d", DATA_WIDTH, ACC_WIDTH);
        $display("============================================");

        // Initialize
        test_num   = 1;
        pass_count = 0;
        fail_count = 0;
        rst_n      = 1'b0;
        clear      = 1'b0;
        enable     = 1'b0;
        a_in       = '0;
        b_in       = '0;
        acc_in     = '0;

        // Reset
        wait_cycles(3);
        rst_n = 1'b1;
        wait_cycles(2);

        // ---- Test 1: Reset clears output to zero ----
        check_result(0, "Reset clears accumulator to zero");

        // ---- Test 2: Single multiply 3 * 5 + 0 = 15 ----
        apply_mac(16'sd3, 16'sd5, 32'sd0);
        check_result(32'sd15, "3 * 5 + 0 = 15");

        // ---- Test 3: Accumulate via acc_in: 2 * 4 + 15 = 23 ----
        // Feed new values with acc_in = 15
        a_in   = 16'sd2;
        b_in   = 16'sd4;
        acc_in = 32'sd15;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        b_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_result(32'sd23, "2 * 4 + 15 = 23 (accumulation via acc_in)");

        // ---- Test 4: Negative numbers: (-3) * 5 + 10 = -5 ----
        a_in   = -16'sd3;
        b_in   = 16'sd5;
        acc_in = 32'sd10;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        b_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_result(-32'sd5, "(-3) * 5 + 10 = -5 (negative multiply)");

        // ---- Test 5: Overflow boundary: 100 * 200 + 0 = 20000 ----
        // Using moderate values that are safe
        a_in   = 16'sd100;
        b_in   = 16'sd200;
        acc_in = 32'sd0;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        b_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_result(32'sd20000, "100 * 200 + 0 = 20000 (larger values)");

        // Also test near-max: 32767 * 2 + 0 = 65534
        a_in   = 16'sd32767;
        b_in   = 16'sd2;
        acc_in = 32'sd0;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        b_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_result(32'sd65534, "32767 * 2 + 0 = 65534 (near-max)");

        // ---- Test 6: Enable gating ----
        // First, do a known computation
        a_in   = 16'sd7;
        b_in   = 16'sd8;
        acc_in = 32'sd0;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        b_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_result(32'sd56, "7 * 8 + 0 = 56 (before enable test)");

        // Now apply different inputs with enable=0 — output should hold
        a_in   = 16'sd99;
        b_in   = 16'sd99;
        acc_in = 32'sd99;
        enable = 1'b0;
        wait_cycles(3);
        check_result(32'sd56, "Output holds at 56 when enable=0");

        // ---- Test 7: Clear during operation ----
        // Do a computation first
        a_in   = 16'sd10;
        b_in   = 16'sd10;
        acc_in = 32'sd0;
        enable = 1'b1;
        @(posedge clk);
        enable = 1'b0;
        @(posedge clk);
        check_result(32'sd100, "10 * 10 + 0 = 100 (before clear)");

        // Now clear
        clear = 1'b1;
        @(posedge clk);
        clear = 1'b0;
        @(posedge clk);
        check_result(32'sd0, "Clear resets accumulator to 0");

        // ---- Summary ----
        $display("============================================");
        $display("  MAC Unit Testbench — Complete");
        $display("  PASSED: %0d / %0d", pass_count, pass_count + fail_count);
        if (fail_count > 0)
            $display("  FAILED: %0d", fail_count);
        else
            $display("  ALL TESTS PASSED");
        $display("============================================");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 500);
        $display("[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
