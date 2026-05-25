//==============================================================================
// Testbench: tb_dot_product_engine
// Description: Unit test for dot_product_engine module
//
// Tests parallel dot product computation with various test cases:
//   1. Simple uniform vectors → known result
//   2. Zero vectors → result = 0
//   3. Negative values → proper signed arithmetic
//   4. Maximum values → no overflow
//   5. Orthogonal vectors → result = 0
//
// Verification methodology:
//   - Feed 16 elements per cycle for 4 cycles (64 elements total)
//   - Wait for valid signal
//   - Compare result with expected value
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-03
//==============================================================================

`timescale 1ns / 1ps

module tb_dot_product_engine;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz clock
    parameter D = 64;           // Vector dimension
    parameter TILE_WIDTH = 16;  // Parallel MAC units

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [7:0]  a [0:TILE_WIDTH-1];
    reg  [7:0]  b [0:TILE_WIDTH-1];
    wire [31:0] result;
    wire        valid;
    wire        ready;

    //==========================================================================
    // Test Storage
    //==========================================================================
    reg signed [7:0] vec_a [0:D-1];
    reg signed [7:0] vec_b [0:D-1];

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    dot_product_engine #(
        .D(D),
        .TILE_WIDTH(TILE_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a(a),
        .b(b),
        .result(result),
        .valid(valid),
        .ready(ready)
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
    integer i, j;
    integer test_num;
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer cycle_count;
    integer chunk_idx;
    reg signed [31:0] expected_result;
    reg signed [31:0] computed_result;

    //==========================================================================
    // Tasks
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            start = 0;
            for (i = 0; i < TILE_WIDTH; i = i + 1) begin
                a[i] = 8'd0;
                b[i] = 8'd0;
            end
            repeat(5) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task compute_expected_result;
        begin
            expected_result = 0;
            for (i = 0; i < D; i = i + 1) begin
                expected_result = expected_result + ($signed(vec_a[i]) * $signed(vec_b[i]));
            end
        end
    endtask

    task run_dot_product;
        begin
            cycle_count = 0;

            // Start computation
            start = 1;
            @(posedge clk);
            start = 0;

            // Feed data in chunks of 16 elements
            for (chunk_idx = 0; chunk_idx < D / TILE_WIDTH; chunk_idx = chunk_idx + 1) begin
                for (i = 0; i < TILE_WIDTH; i = i + 1) begin
                    a[i] = vec_a[chunk_idx * TILE_WIDTH + i];
                    b[i] = vec_b[chunk_idx * TILE_WIDTH + i];
                end
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            // Wait for valid signal
            while (!valid) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;

                // Timeout check
                if (cycle_count > 20) begin
                    $display("  [ERROR] Timeout after %0d cycles", cycle_count);
                    failed_tests = failed_tests + 1;
                    return;
                end
            end

            computed_result = $signed(result);
        end
    endtask

    task check_result;
        input signed [31:0] expected;
        input signed [31:0] actual;
        input integer tolerance;
        begin
            if ((actual >= expected - tolerance) && (actual <= expected + tolerance)) begin
                $display("  [PASS] Result: %0d (expected %0d ± %0d)",
                         actual, expected, tolerance);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  [FAIL] Result: %0d (expected %0d ± %0d)",
                         actual, expected, tolerance);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    task print_vectors;
        input integer num_elements;
        begin
            $write("  Vector A (first %0d): ", num_elements);
            for (i = 0; i < num_elements; i = i + 1) begin
                $write("%0d ", $signed(vec_a[i]));
            end
            $write("\n");

            $write("  Vector B (first %0d): ", num_elements);
            for (i = 0; i < num_elements; i = i + 1) begin
                $write("%0d ", $signed(vec_b[i]));
            end
            $write("\n");
        end
    endtask

    //==========================================================================
    // Test Cases
    //==========================================================================

    // Test 1: Uniform vectors (all ones)
    task test_uniform_vectors;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Uniform Vectors", test_num);
            $display("========================================");
            $display("Input: A = [1, 1, ..., 1], B = [1, 1, ..., 1]");
            $display("Expected: 1×1 × 64 = 64");

            for (i = 0; i < D; i = i + 1) begin
                vec_a[i] = 8'sd1;
                vec_b[i] = 8'sd1;
            end

            compute_expected_result();
            run_dot_product();

            $display("Completed in %0d cycles", cycle_count);
            $display("Expected: %0d", expected_result);
            $display("Computed: %0d", computed_result);
            check_result(expected_result, computed_result, 0);
        end
    endtask

    // Test 2: Zero vectors
    task test_zero_vectors;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Zero Vectors", test_num);
            $display("========================================");
            $display("Input: A = [0, 0, ..., 0], B = [1, 2, ..., 64]");
            $display("Expected: 0");

            for (i = 0; i < D; i = i + 1) begin
                vec_a[i] = 8'sd0;
                vec_b[i] = i + 1;
            end

            compute_expected_result();
            run_dot_product();

            $display("Completed in %0d cycles", cycle_count);
            $display("Expected: %0d", expected_result);
            $display("Computed: %0d", computed_result);
            check_result(expected_result, computed_result, 0);
        end
    endtask

    // Test 3: Negative values
    task test_negative_values;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Negative Values", test_num);
            $display("========================================");
            $display("Input: A = [1, -1, 1, -1, ...], B = [1, 1, 1, 1, ...]");
            $display("Expected: 32 × 1 + 32 × (-1) = 0");

            for (i = 0; i < D; i = i + 1) begin
                vec_a[i] = (i % 2 == 0) ? 8'sd1 : -8'sd1;
                vec_b[i] = 8'sd1;
            end

            compute_expected_result();
            run_dot_product();

            $display("Completed in %0d cycles", cycle_count);
            print_vectors(8);
            $display("Expected: %0d", expected_result);
            $display("Computed: %0d", computed_result);
            check_result(expected_result, computed_result, 0);
        end
    endtask

    // Test 4: Maximum values
    task test_maximum_values;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Maximum Values", test_num);
            $display("========================================");
            $display("Input: A = [127, 127, ..., 127], B = [127, 127, ..., 127]");
            $display("Expected: 127×127 × 64 = 1,032,256");

            for (i = 0; i < D; i = i + 1) begin
                vec_a[i] = 8'sd127;
                vec_b[i] = 8'sd127;
            end

            compute_expected_result();
            run_dot_product();

            $display("Completed in %0d cycles", cycle_count);
            $display("Expected: %0d", expected_result);
            $display("Computed: %0d", computed_result);
            check_result(expected_result, computed_result, 0);
        end
    endtask

    // Test 5: Orthogonal vectors
    task test_orthogonal_vectors;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Orthogonal Vectors", test_num);
            $display("========================================");
            $display("Input: A = [1,0,1,0,...], B = [0,1,0,1,...]");
            $display("Expected: 0 (orthogonal)");

            for (i = 0; i < D; i = i + 1) begin
                vec_a[i] = (i % 2 == 0) ? 8'sd1 : 8'sd0;
                vec_b[i] = (i % 2 == 1) ? 8'sd1 : 8'sd0;
            end

            compute_expected_result();
            run_dot_product();

            $display("Completed in %0d cycles", cycle_count);
            print_vectors(8);
            $display("Expected: %0d", expected_result);
            $display("Computed: %0d", computed_result);
            check_result(expected_result, computed_result, 0);
        end
    endtask

    // Test 6: Random values
    task test_random_values;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Random Values", test_num);
            $display("========================================");
            $display("Input: Random INT8 values");

            for (i = 0; i < D; i = i + 1) begin
                vec_a[i] = $random % 256;
                vec_b[i] = $random % 256;
            end

            compute_expected_result();
            run_dot_product();

            $display("Completed in %0d cycles", cycle_count);
            print_vectors(8);
            $display("Expected: %0d", expected_result);
            $display("Computed: %0d", computed_result);
            check_result(expected_result, computed_result, 0);
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("========================================");
        $display("Dot Product Engine Unit Test");
        $display("========================================");
        $display("Module: dot_product_engine");
        $display("Parameters: D=%0d, TILE_WIDTH=%0d", D, TILE_WIDTH);
        $display("========================================\n");

        // Initialize counters
        test_num = 0;
        total_tests = 6;
        passed_tests = 0;
        failed_tests = 0;

        // Reset
        reset_dut();

        // Run tests
        test_uniform_vectors();
        test_zero_vectors();
        test_negative_values();
        test_maximum_values();
        test_orthogonal_vectors();
        test_random_values();

        // Summary
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", total_tests);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);
        $display("Pass rate:    %.1f%%", (passed_tests * 100.0) / total_tests);
        $display("========================================\n");

        if (failed_tests == 0) begin
            $display("*** ALL TESTS PASSED ***\n");
        end else begin
            $display("*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #100000;  // 100 μs timeout
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

    //==========================================================================
    // Waveform Dump
    //==========================================================================
    initial begin
        $dumpfile("tb_dot_product_engine.vcd");
        $dumpvars(0, tb_dot_product_engine);
    end

endmodule
