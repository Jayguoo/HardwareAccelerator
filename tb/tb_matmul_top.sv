//=============================================================================
// tb_matmul_top.sv — Full System AXI4-Lite Testbench
//
// Exercises the complete matrix multiply accelerator via AXI4-Lite:
//   1. Read VERSION and CAPABILITY registers
//   2. Write matrices A and B
//   3. Start computation
//   4. Poll STATUS until done
//   5. Read result matrix
//   6. Compare against expected
//
// Uses AXI4-Lite BFM tasks for all communication.
//=============================================================================

`timescale 1ns / 1ps

import matmul_pkg::*;

module tb_matmul_top;

    parameter int MATRIX_DIM     = matmul_pkg::MATRIX_DIM;
    parameter int DATA_WIDTH     = matmul_pkg::DATA_WIDTH;
    parameter int ACC_WIDTH      = matmul_pkg::ACC_WIDTH;
    parameter int AXI_ADDR_WIDTH = matmul_pkg::AXI_ADDR_WIDTH;
    parameter int AXI_DATA_WIDTH = matmul_pkg::AXI_DATA_WIDTH;
    parameter int CLK_PERIOD     = 10;

    //=========================================================================
    // AXI Signals
    //=========================================================================
    logic                          clk;
    logic                          resetn;

    logic [AXI_ADDR_WIDTH-1:0]     awaddr;
    logic [2:0]                    awprot;
    logic                          awvalid;
    logic                          awready;

    logic [AXI_DATA_WIDTH-1:0]     wdata;
    logic [AXI_DATA_WIDTH/8-1:0]   wstrb;
    logic                          wvalid;
    logic                          wready;

    logic [1:0]                    bresp;
    logic                          bvalid;
    logic                          bready;

    logic [AXI_ADDR_WIDTH-1:0]     araddr;
    logic [2:0]                    arprot;
    logic                          arvalid;
    logic                          arready;

    logic [AXI_DATA_WIDTH-1:0]     rdata;
    logic [1:0]                    rresp;
    logic                          rvalid;
    logic                          rready;

    logic                          irq;

    // Test tracking
    int test_num;
    int pass_count;
    int fail_count;

    // Test data
    logic signed [DATA_WIDTH-1:0] mat_a [MATRIX_DIM][MATRIX_DIM];
    logic signed [DATA_WIDTH-1:0] mat_b [MATRIX_DIM][MATRIX_DIM];
    logic signed [ACC_WIDTH-1:0]  mat_expected [MATRIX_DIM][MATRIX_DIM];

    //=========================================================================
    // DUT
    //=========================================================================
    matmul_top #(
        .MATRIX_DIM     (MATRIX_DIM),
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
    ) dut (
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (resetn),
        .S_AXI_AWADDR  (awaddr),
        .S_AXI_AWPROT  (awprot),
        .S_AXI_AWVALID (awvalid),
        .S_AXI_AWREADY (awready),
        .S_AXI_WDATA   (wdata),
        .S_AXI_WSTRB   (wstrb),
        .S_AXI_WVALID  (wvalid),
        .S_AXI_WREADY  (wready),
        .S_AXI_BRESP   (bresp),
        .S_AXI_BVALID  (bvalid),
        .S_AXI_BREADY  (bready),
        .S_AXI_ARADDR  (araddr),
        .S_AXI_ARPROT  (arprot),
        .S_AXI_ARVALID (arvalid),
        .S_AXI_ARREADY (arready),
        .S_AXI_RDATA   (rdata),
        .S_AXI_RRESP   (rresp),
        .S_AXI_RVALID  (rvalid),
        .S_AXI_RREADY  (rready),
        .irq            (irq)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    //=========================================================================
    // AXI4-Lite BFM Tasks
    //=========================================================================

    // AXI Write: drives AW + W channels, waits for B response
    task automatic axi_write(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data_in
    );
        // Drive AW and W simultaneously
        @(posedge clk);
        awaddr  <= addr;
        awprot  <= 3'b000;
        awvalid <= 1'b1;
        wdata   <= data_in;
        wstrb   <= 4'hF;
        wvalid  <= 1'b1;
        bready  <= 1'b1;

        // Wait for both handshakes
        fork
            begin
                // AW handshake
                do @(posedge clk); while (!awready);
                awvalid <= 1'b0;
            end
            begin
                // W handshake
                do @(posedge clk); while (!wready);
                wvalid <= 1'b0;
            end
        join

        // Wait for B response
        do @(posedge clk); while (!bvalid);
        if (bresp != 2'b00)
            $display("  [WARN] AXI write to 0x%04h got BRESP=%0b", addr, bresp);
        bready <= 1'b0;
    endtask

    // AXI Read: drives AR channel, waits for R response
    task automatic axi_read(
        input  logic [AXI_ADDR_WIDTH-1:0] addr,
        output logic [AXI_DATA_WIDTH-1:0] data_out
    );
        @(posedge clk);
        araddr  <= addr;
        arprot  <= 3'b000;
        arvalid <= 1'b1;
        rready  <= 1'b1;

        // AR handshake
        do @(posedge clk); while (!arready);
        arvalid <= 1'b0;

        // Wait for R response
        do @(posedge clk); while (!rvalid);
        data_out = rdata;
        if (rresp != 2'b00)
            $display("  [WARN] AXI read from 0x%04h got RRESP=%0b", addr, rresp);
        rready <= 1'b0;
    endtask

    //=========================================================================
    // Test Helper Tasks
    //=========================================================================

    // Compute SW reference
    task automatic compute_reference();
        for (int i = 0; i < MATRIX_DIM; i++)
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_expected[i][j] = 0;
                for (int k = 0; k < MATRIX_DIM; k++)
                    mat_expected[i][j] += ACC_WIDTH'(mat_a[i][k]) * ACC_WIDTH'(mat_b[k][j]);
            end
    endtask

    // Write matrices to accelerator via AXI
    task automatic write_matrices();
        for (int i = 0; i < MATRIX_DIM; i++) begin
            for (int j = 0; j < MATRIX_DIM; j++) begin
                // Sign-extend to 32-bit
                axi_write(ADDR_MAT_A_BASE + (i * MATRIX_DIM + j) * 4,
                          {{(32-DATA_WIDTH){mat_a[i][j][DATA_WIDTH-1]}}, mat_a[i][j]});
                axi_write(ADDR_MAT_B_BASE + (i * MATRIX_DIM + j) * 4,
                          {{(32-DATA_WIDTH){mat_b[i][j][DATA_WIDTH-1]}}, mat_b[i][j]});
            end
        end
    endtask

    // Start computation and wait for done
    task automatic start_and_wait();
        logic [31:0] status;

        // Write START
        axi_write(ADDR_CTRL_REG, 32'h0000_0001);

        // Poll STATUS until DONE
        for (int i = 0; i < 10000; i++) begin
            axi_read(ADDR_STATUS_REG, status);
            if (status[1]) begin  // DONE bit
                $display("  Computation complete (status=0x%08h)", status);
                return;
            end
            wait_cycles(5);
        end
        $display("  [ERROR] Computation timeout!");
    endtask

    // Read results and compare
    task automatic verify_results(input string test_name);
        logic [31:0] rval;
        logic signed [ACC_WIDTH-1:0] result;
        logic [31:0] cycles;
        int errors;

        // Read cycle count
        axi_read(ADDR_CYCLE_COUNT, cycles);
        $display("  Cycle count: %0d", cycles);

        errors = 0;
        $display("  Result matrix:");
        for (int i = 0; i < MATRIX_DIM; i++) begin
            $write("    [");
            for (int j = 0; j < MATRIX_DIM; j++) begin
                axi_read(ADDR_MAT_R_BASE + (i * MATRIX_DIM + j) * 4, rval);
                result = $signed(rval);
                $write(" %6d", result);

                if (result !== mat_expected[i][j]) begin
                    errors++;
                end
            end
            $display(" ]");
        end

        $display("  Expected matrix:");
        for (int i = 0; i < MATRIX_DIM; i++) begin
            $write("    [");
            for (int j = 0; j < MATRIX_DIM; j++)
                $write(" %6d", mat_expected[i][j]);
            $display(" ]");
        end

        if (errors == 0) begin
            $display("  [PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — %0d mismatches", test_name, errors);
            fail_count++;
        end
        test_num++;

        // Clear done
        axi_write(ADDR_CTRL_REG, 32'h0000_0002);
        wait_cycles(5);
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("============================================");
        $display("  Full System AXI Testbench — Starting");
        $display("  MATRIX_DIM=%0d", MATRIX_DIM);
        $display("============================================");

        test_num   = 1;
        pass_count = 0;
        fail_count = 0;

        // Initialize AXI signals
        awaddr  = '0; awprot = '0; awvalid = 0;
        wdata   = '0; wstrb  = '0; wvalid  = 0;
        bready  = 0;
        araddr  = '0; arprot = '0; arvalid = 0;
        rready  = 0;
        resetn  = 1'b0;

        wait_cycles(10);
        resetn = 1'b1;
        wait_cycles(5);

        // ---- Read ID Registers ----
        $display("\n--- Register Read Tests ---");
        begin
            logic [31:0] version, capability, status;

            axi_read(ADDR_VERSION_REG, version);
            $display("  VERSION: 0x%08h (expected 0x4D4D0100)", version);
            if (version == 32'h4D4D_0100) begin
                $display("  [PASS] Version register");
                pass_count++;
            end else begin
                $display("  [FAIL] Version register");
                fail_count++;
            end
            test_num++;

            axi_read(ADDR_CAPABILITY_REG, capability);
            $display("  CAPABILITY: 0x%08h", capability);
            $display("    MAX_DIM=%0d, DATA_WIDTH=%0d, ACC_WIDTH=%0d",
                     capability[7:0], capability[15:8], capability[23:16]);

            axi_read(ADDR_STATUS_REG, status);
            $display("  STATUS: 0x%08h (IDLE=%b)", status, status[0]);
            if (status[0]) begin
                $display("  [PASS] Initial IDLE status");
                pass_count++;
            end else begin
                $display("  [FAIL] Initial IDLE status");
                fail_count++;
            end
            test_num++;
        end

        // ---- Test 1: Identity multiplication ----
        $display("\n--- Test: A * Identity = A ---");
        for (int i = 0; i < MATRIX_DIM; i++)
            for (int j = 0; j < MATRIX_DIM; j++) begin
                mat_a[i][j] = DATA_WIDTH'(i * MATRIX_DIM + j + 1);
                mat_b[i][j] = (i == j) ? 16'sd1 : 16'sd0;
            end
        compute_reference();
        write_matrices();
        start_and_wait();
        verify_results("A * Identity = A");

        // ---- Test 2: General multiplication ----
        $display("\n--- Test: General 4x4 ---");
        mat_a[0][0]=1;  mat_a[0][1]=2;  mat_a[0][2]=3;  mat_a[0][3]=4;
        mat_a[1][0]=5;  mat_a[1][1]=6;  mat_a[1][2]=7;  mat_a[1][3]=8;
        mat_a[2][0]=9;  mat_a[2][1]=10; mat_a[2][2]=11; mat_a[2][3]=12;
        mat_a[3][0]=13; mat_a[3][1]=14; mat_a[3][2]=15; mat_a[3][3]=16;

        mat_b[0][0]=1;  mat_b[0][1]=0;  mat_b[0][2]=2;  mat_b[0][3]=0;
        mat_b[1][0]=0;  mat_b[1][1]=1;  mat_b[1][2]=0;  mat_b[1][3]=2;
        mat_b[2][0]=2;  mat_b[2][1]=0;  mat_b[2][2]=1;  mat_b[2][3]=0;
        mat_b[3][0]=0;  mat_b[3][1]=2;  mat_b[3][2]=0;  mat_b[3][3]=1;
        compute_reference();
        write_matrices();
        start_and_wait();
        verify_results("General 4x4 multiplication");

        // ---- Test 3: Negative values ----
        $display("\n--- Test: Negative values ---");
        mat_a[0][0]=1;   mat_a[0][1]=-2;  mat_a[0][2]=3;   mat_a[0][3]=-4;
        mat_a[1][0]=-5;  mat_a[1][1]=6;   mat_a[1][2]=-7;  mat_a[1][3]=8;
        mat_a[2][0]=9;   mat_a[2][1]=-10; mat_a[2][2]=11;  mat_a[2][3]=-12;
        mat_a[3][0]=-1;  mat_a[3][1]=2;   mat_a[3][2]=-3;  mat_a[3][3]=4;

        mat_b[0][0]=2;   mat_b[0][1]=-1;  mat_b[0][2]=0;   mat_b[0][3]=3;
        mat_b[1][0]=-3;  mat_b[1][1]=2;   mat_b[1][2]=1;   mat_b[1][3]=-2;
        mat_b[2][0]=0;   mat_b[2][1]=1;   mat_b[2][2]=-2;  mat_b[2][3]=4;
        mat_b[3][0]=1;   mat_b[3][1]=-3;  mat_b[3][2]=2;   mat_b[3][3]=-1;
        compute_reference();
        write_matrices();
        start_and_wait();
        verify_results("Negative values");

        // ---- Summary ----
        $display("\n============================================");
        $display("  Full System AXI Testbench — Complete");
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
        #(CLK_PERIOD * 500000);
        $display("[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
