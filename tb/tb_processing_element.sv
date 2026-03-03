//=============================================================================
// tb_processing_element.sv — Testbench for Processing Element
//
// Tests:
//   1. Weight loading and persistence
//   2. Horizontal A propagation (1-cycle delay)
//   3. Vertical accumulation (a_in * weight + acc_in)
//   4. Full PE operation with streaming inputs
//   5. Clear accumulator
//=============================================================================

`timescale 1ns / 1ps

module tb_processing_element;

    parameter int DATA_WIDTH = 16;
    parameter int ACC_WIDTH  = 32;
    parameter int CLK_PERIOD = 10;

    // Signals
    logic                            clk;
    logic                            rst_n;
    logic                            load_weight;
    logic                            clear_acc;
    logic                            enable;
    logic signed [DATA_WIDTH-1:0]    a_in;
    logic signed [DATA_WIDTH-1:0]    a_out;
    logic signed [ACC_WIDTH-1:0]     acc_in;
    logic signed [ACC_WIDTH-1:0]     acc_out;
    logic signed [DATA_WIDTH-1:0]    weight_in;

    int test_num;
    int pass_count;
    int fail_count;

    // DUT
    processing_element #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .load_weight (load_weight),
        .clear_acc   (clear_acc),
        .enable      (enable),
        .a_in        (a_in),
        .a_out       (a_out),
        .acc_in      (acc_in),
        .acc_out     (acc_out),
        .weight_in   (weight_in)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    task automatic check_a_out(
        input logic signed [DATA_WIDTH-1:0] expected,
        input string test_name
    );
        #1;
        if (a_out === expected) begin
            $display("[PASS] Test %0d: %s — a_out=%0d", test_num, test_name, a_out);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s — a_out expected %0d, got %0d",
                     test_num, test_name, expected, a_out);
            fail_count++;
        end
        test_num++;
    endtask

    task automatic check_acc_out(
        input logic signed [ACC_WIDTH-1:0] expected,
        input string test_name
    );
        #1;
        if (acc_out === expected) begin
            $display("[PASS] Test %0d: %s — acc_out=%0d", test_num, test_name, acc_out);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s — acc_out expected %0d, got %0d",
                     test_num, test_name, expected, acc_out);
            fail_count++;
        end
        test_num++;
    endtask

    initial begin
        $display("============================================");
        $display("  Processing Element Testbench — Starting");
        $display("============================================");

        test_num   = 1;
        pass_count = 0;
        fail_count = 0;

        // Initialize
        rst_n       = 1'b0;
        load_weight = 1'b0;
        clear_acc   = 1'b0;
        enable      = 1'b0;
        a_in        = '0;
        acc_in      = '0;
        weight_in   = '0;

        // Reset
        wait_cycles(3);
        rst_n = 1'b1;
        wait_cycles(2);

        // ---- Test 1: Weight loading ----
        $display("\n--- Test: Weight Loading ---");
        weight_in   = 16'sd7;
        load_weight = 1'b1;
        @(posedge clk);
        load_weight = 1'b0;
        weight_in   = '0;
        wait_cycles(1);
        // Weight should be stored internally — verify via computation
        // Do: a_in=1, acc_in=0 => acc_out should be 1*7+0=7 after 2 pipeline stages
        a_in   = 16'sd1;
        acc_in = 32'sd0;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);  // Wait for 2-stage MAC pipeline
        check_acc_out(32'sd7, "Weight=7, a=1, acc=0 => 7");

        // ---- Test 2: Horizontal A propagation ----
        $display("\n--- Test: Horizontal A Propagation ---");
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(2);

        // Feed a_in=42, expect a_out=42 one cycle later
        a_in   = 16'sd42;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        // a_out should now be 42 (1-cycle delay)
        check_a_out(16'sd42, "a_in=42 appears as a_out after 1 cycle");
        enable = 1'b0;

        // ---- Test 3: Vertical accumulation ----
        $display("\n--- Test: Vertical Accumulation ---");
        // Clear first
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(2);

        // Weight is still 7. Feed a_in=3, acc_in=10 => 3*7+10=31
        a_in   = 16'sd3;
        acc_in = 32'sd10;
        enable = 1'b1;
        @(posedge clk);
        a_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_acc_out(32'sd31, "a=3, weight=7, acc_in=10 => 3*7+10=31");

        // ---- Test 4: Streaming operation ----
        $display("\n--- Test: Streaming Operation ---");
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        wait_cycles(2);

        // Load new weight = 5
        weight_in   = 16'sd5;
        load_weight = 1'b1;
        @(posedge clk);
        load_weight = 1'b0;
        weight_in   = '0;

        // Stream a_in = [2, 3, 4, 1] with acc_in = 0
        // Each should produce: 2*5=10, 3*5=15, 4*5=20, 1*5=5
        enable = 1'b1;

        a_in = 16'sd2; acc_in = 32'sd0;
        @(posedge clk);
        a_in = 16'sd3; acc_in = 32'sd0;
        @(posedge clk);
        // After 2 clocks, first result should appear
        check_acc_out(32'sd10, "Stream[0]: 2*5+0=10");
        a_in = 16'sd4; acc_in = 32'sd0;
        @(posedge clk);
        check_acc_out(32'sd15, "Stream[1]: 3*5+0=15");
        a_in = 16'sd1; acc_in = 32'sd0;
        @(posedge clk);
        check_acc_out(32'sd20, "Stream[2]: 4*5+0=20");
        a_in   = '0;
        acc_in = '0;
        enable = 1'b0;
        @(posedge clk);
        check_acc_out(32'sd5, "Stream[3]: 1*5+0=5");

        // ---- Test 5: Clear accumulator ----
        $display("\n--- Test: Clear Accumulator ---");
        clear_acc = 1'b1;
        @(posedge clk);
        clear_acc = 1'b0;
        @(posedge clk);
        check_acc_out(32'sd0, "Clear resets acc_out to 0");

        // ---- Summary ----
        $display("\n============================================");
        $display("  Processing Element Testbench — Complete");
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
        #(CLK_PERIOD * 500);
        $display("[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
