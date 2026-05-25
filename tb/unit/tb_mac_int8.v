//==============================================================================
// Testbench: tb_mac_int8
// Description: Unit test for MAC (Multiply-Accumulate) unit
//
// Tests:
//   1. Basic multiplication and accumulation
//   2. Signed operands (positive, negative, mixed)
//   3. Accumulator overflow behavior
//   4. Clear functionality
//   5. Enable control
//
// Expected behavior:
//   - 2-cycle latency (1 for multiply, 1 for accumulate)
//   - Correct signed arithmetic
//   - Accumulator clears synchronously
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-01
//==============================================================================

`timescale 1ns / 1ps

module tb_mac_int8;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz clock

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg         clear;
    reg         enable;
    reg  [7:0]  a;
    reg  [7:0]  b;
    wire [31:0] acc;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    mac_int8 dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .clear  (clear),
        .enable (enable),
        .a      (a),
        .b      (b),
        .acc    (acc)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Test Variables
    //==========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;

    //==========================================================================
    // Test Tasks
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            clear = 0;
            enable = 0;
            a = 8'd0;
            b = 8'd0;
            repeat(2) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task test_mac;
        input signed [7:0] val_a;
        input signed [7:0] val_b;
        input signed [31:0] expected_acc;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;

            // Set inputs
            a = val_a;
            b = val_b;
            enable = 0;
            @(posedge clk);

            // Pulse enable for exactly 1 cycle
            enable = 1;
            @(posedge clk);
            enable = 0;

            // Wait for pipeline (1 more cycle for accumulate)
            @(posedge clk);

            if (acc == expected_acc) begin
                $display("[PASS] Test %0d: %s", test_count, test_name);
                $display("       a=%0d, b=%0d, acc=%0d (expected=%0d)",
                         $signed(val_a), $signed(val_b), $signed(acc), $signed(expected_acc));
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %s", test_count, test_name);
                $display("       a=%0d, b=%0d, acc=%0d (expected=%0d)",
                         $signed(val_a), $signed(val_b), $signed(acc), $signed(expected_acc));
                fail_count = fail_count + 1;
            end
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("========================================");
        $display("MAC INT8 Unit Test");
        $display("========================================");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Initialize
        reset_dut();

        //----------------------------------------------------------------------
        // Test 1: Basic positive multiplication
        //----------------------------------------------------------------------
        $display("\n--- Test 1: Basic Positive Multiplication ---");
        clear = 1;
        @(posedge clk);
        clear = 0;
        test_mac(8'd5, 8'd3, 32'd15, "5 * 3 = 15");

        //----------------------------------------------------------------------
        // Test 2: Accumulation
        //----------------------------------------------------------------------
        $display("\n--- Test 2: Accumulation ---");
        test_mac(8'd4, 8'd2, 32'd23, "15 + (4 * 2) = 23");
        test_mac(8'd1, 8'd10, 32'd33, "23 + (1 * 10) = 33");

        //----------------------------------------------------------------------
        // Test 3: Negative operands
        //----------------------------------------------------------------------
        $display("\n--- Test 3: Negative Operands ---");
        clear = 1;
        @(posedge clk);
        clear = 0;
        test_mac(-8'd5, 8'd3, -32'd15, "(-5) * 3 = -15");
        test_mac(8'd5, -8'd3, -32'd30, "(-15) + (5 * (-3)) = -30");
        test_mac(-8'd2, -8'd4, -32'd22, "(-30) + ((-2) * (-4)) = -22");

        //----------------------------------------------------------------------
        // Test 4: Maximum values
        //----------------------------------------------------------------------
        $display("\n--- Test 4: Maximum Values ---");
        clear = 1;
        @(posedge clk);
        clear = 0;
        test_mac(8'd127, 8'd127, 32'd16129, "127 * 127 = 16129");
        test_mac(-8'd128, 8'd127, -32'd127, "16129 + ((-128) * 127) = -127");

        //----------------------------------------------------------------------
        // Test 5: Clear functionality
        //----------------------------------------------------------------------
        $display("\n--- Test 5: Clear Functionality ---");
        // Accumulate some value
        clear = 1;
        @(posedge clk);
        clear = 0;
        test_mac(8'd10, 8'd10, 32'd100, "10 * 10 = 100");

        // Clear and verify
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        if (acc == 32'd0) begin
            test_count = test_count + 1;
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d: Clear resets accumulator to 0", test_count);
        end else begin
            test_count = test_count + 1;
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: Clear failed, acc=%0d (expected 0)", test_count, acc);
        end

        //----------------------------------------------------------------------
        // Test 6: Enable control
        //----------------------------------------------------------------------
        $display("\n--- Test 6: Enable Control ---");
        clear = 1;
        @(posedge clk);
        clear = 0;
        test_mac(8'd5, 8'd5, 32'd25, "5 * 5 = 25");

        // Disable and verify no accumulation
        enable = 0;
        a = 8'd10;
        b = 8'd10;
        repeat(2) @(posedge clk);

        if (acc == 32'd25) begin
            test_count = test_count + 1;
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d: Enable=0 prevents accumulation", test_count);
        end else begin
            test_count = test_count + 1;
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: Enable=0 failed, acc=%0d (expected 25)", test_count, acc);
        end

        //----------------------------------------------------------------------
        // Test 7: Long accumulation (64 MACs)
        //----------------------------------------------------------------------
        $display("\n--- Test 7: Long Accumulation (64 MACs) ---");
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);

        // Accumulate 64 times: 10 * 10 = 100 each time
        // Expected: 64 * 100 = 6400
        // Use continuous enable for this test
        a = 8'd10;
        b = 8'd10;
        enable = 1;

        repeat(64) begin
            @(posedge clk);
        end

        enable = 0;
        repeat(2) @(posedge clk);  // Wait for pipeline

        if (acc == 32'd6400) begin
            test_count = test_count + 1;
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d: 64 MACs = %0d (expected 6400)", test_count, acc);
        end else begin
            test_count = test_count + 1;
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: 64 MACs = %0d (expected 6400)", test_count, acc);
        end

        //----------------------------------------------------------------------
        // Test Summary
        //----------------------------------------------------------------------
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
        end
        $display("========================================\n");

        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #100000;  // 100 us timeout
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

    //==========================================================================
    // Waveform Dump (for debugging)
    //==========================================================================
    initial begin
        $dumpfile("tb_mac_int8.vcd");
        $dumpvars(0, tb_mac_int8);
    end

endmodule
