//==============================================================================
// Testbench: tb_softmax_unit
// Description: Unit test for softmax_unit_v2 module
//
// Tests softmax computation in isolation with various test cases:
//   1. Uniform scores → uniform weights (1/8 each)
//   2. One dominant score → one weight ≈ 1, others ≈ 0
//   3. Two equal high scores → two weights ≈ 0.5, others ≈ 0
//   4. Negative scores → proper handling
//   5. Large score range → numerical stability
//
// Verification methodology:
//   - Apply test vectors
//   - Wait for valid signal
//   - Check that weights sum to ~1.0 (32768 in Q15)
//   - Check individual weight values against expected ranges
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-03
//==============================================================================

`timescale 1ns / 1ps

module tb_softmax_unit;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz clock
    parameter L = 8;            // Sequence length

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [31:0] scores [0:L-1];
    wire [15:0] weights [0:L-1];
    wire        valid;
    wire        ready;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    softmax_unit_v2 #(
        .L(L),
        .EXP_LUT_SIZE(256)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .scores(scores),
        .weights(weights),
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
    integer i;
    integer test_num;
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer cycle_count;
    integer sum_weights;
    real sum_float;

    //==========================================================================
    // Tasks
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            start = 0;
            for (i = 0; i < L; i = i + 1) begin
                scores[i] = 32'sd0;
            end
            repeat(5) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task run_softmax;
        begin
            cycle_count = 0;

            // Start computation
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for completion
            while (!valid) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;

                // Timeout check
                if (cycle_count > 100) begin
                    $display("  [ERROR] Timeout after %0d cycles", cycle_count);
                    failed_tests = failed_tests + 1;
                    return;
                end
            end

            @(posedge clk);
        end
    endtask

    task check_weights_sum;
        input integer expected_sum;
        input integer tolerance;
        begin
            sum_weights = 0;
            for (i = 0; i < L; i = i + 1) begin
                sum_weights = sum_weights + weights[i];
            end

            sum_float = sum_weights / 32768.0;

            if ((sum_weights >= expected_sum - tolerance) &&
                (sum_weights <= expected_sum + tolerance)) begin
                $display("  [PASS] Weights sum: %0d (%.4f) - within tolerance",
                         sum_weights, sum_float);
            end else begin
                $display("  [FAIL] Weights sum: %0d (%.4f) - expected %0d ± %0d",
                         sum_weights, sum_float, expected_sum, tolerance);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    task print_weights;
        begin
            $write("  Weights: ");
            for (i = 0; i < L; i = i + 1) begin
                $write("%.4f ", weights[i] / 32768.0);
            end
            $write("\n");
        end
    endtask

    task check_weight_range;
        input integer idx;
        input integer min_val;
        input integer max_val;
        input [255:0] description;
        begin
            if ((weights[idx] >= min_val) && (weights[idx] <= max_val)) begin
                $display("  [PASS] %s: weight[%0d] = %0d (%.4f) - in range [%0d, %0d]",
                         description, idx, weights[idx], weights[idx]/32768.0,
                         min_val, max_val);
            end else begin
                $display("  [FAIL] %s: weight[%0d] = %0d (%.4f) - expected [%0d, %0d]",
                         description, idx, weights[idx], weights[idx]/32768.0,
                         min_val, max_val);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    //==========================================================================
    // Test Cases
    //==========================================================================

    // Test 1: Uniform scores → uniform weights
    task test_uniform_scores;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Uniform Scores", test_num);
            $display("========================================");
            $display("Input: All scores = 100");
            $display("Expected: All weights ≈ 1/8 = 0.125 (4096 in Q15)");

            // Set all scores to same value
            for (i = 0; i < L; i = i + 1) begin
                scores[i] = 32'sd100;
            end

            run_softmax();

            $display("Completed in %0d cycles", cycle_count);
            print_weights();
            check_weights_sum(32768, 100);

            // Each weight should be ~4096 (1/8 in Q15)
            for (i = 0; i < L; i = i + 1) begin
                check_weight_range(i, 3900, 4200, "Uniform weight");
            end

            passed_tests = passed_tests + 1;
        end
    endtask

    // Test 2: One dominant score
    task test_dominant_score;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: One Dominant Score", test_num);
            $display("========================================");
            $display("Input: scores[0] = 1000, others = 0");
            $display("Expected: weights[0] ≈ 1.0, others ≈ 0");

            scores[0] = 32'sd1000;
            for (i = 1; i < L; i = i + 1) begin
                scores[i] = 32'sd0;
            end

            run_softmax();

            $display("Completed in %0d cycles", cycle_count);
            print_weights();
            check_weights_sum(32768, 100);

            // First weight should be close to 1.0 (32768 in Q15)
            check_weight_range(0, 30000, 32768, "Dominant weight");

            // Other weights should be small
            for (i = 1; i < L; i = i + 1) begin
                check_weight_range(i, 0, 2000, "Small weight");
            end

            passed_tests = passed_tests + 1;
        end
    endtask

    // Test 3: Two equal high scores
    task test_two_equal_scores;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Two Equal High Scores", test_num);
            $display("========================================");
            $display("Input: scores[0] = scores[1] = 500, others = 0");
            $display("Expected: weights[0] ≈ weights[1] ≈ 0.5, others ≈ 0");

            scores[0] = 32'sd500;
            scores[1] = 32'sd500;
            for (i = 2; i < L; i = i + 1) begin
                scores[i] = 32'sd0;
            end

            run_softmax();

            $display("Completed in %0d cycles", cycle_count);
            print_weights();
            check_weights_sum(32768, 100);

            // First two weights should be ~0.5 (16384 in Q15)
            check_weight_range(0, 15000, 17500, "Equal weight 1");
            check_weight_range(1, 15000, 17500, "Equal weight 2");

            // Other weights should be small
            for (i = 2; i < L; i = i + 1) begin
                check_weight_range(i, 0, 2000, "Small weight");
            end

            passed_tests = passed_tests + 1;
        end
    endtask

    // Test 4: Negative scores
    task test_negative_scores;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Negative Scores", test_num);
            $display("========================================");
            $display("Input: scores = [-100, -50, 0, 50, 100, 150, 200, 250]");
            $display("Expected: Increasing weights (softmax handles negatives)");

            scores[0] = -32'sd100;
            scores[1] = -32'sd50;
            scores[2] = 32'sd0;
            scores[3] = 32'sd50;
            scores[4] = 32'sd100;
            scores[5] = 32'sd150;
            scores[6] = 32'sd200;
            scores[7] = 32'sd250;

            run_softmax();

            $display("Completed in %0d cycles", cycle_count);
            print_weights();
            check_weights_sum(32768, 100);

            // Weights should be monotonically increasing
            for (i = 0; i < L-1; i = i + 1) begin
                if (weights[i] <= weights[i+1]) begin
                    $display("  [PASS] weights[%0d] <= weights[%0d]", i, i+1);
                end else begin
                    $display("  [FAIL] weights[%0d] > weights[%0d] (not monotonic)", i, i+1);
                    failed_tests = failed_tests + 1;
                end
            end

            passed_tests = passed_tests + 1;
        end
    endtask

    // Test 5: Large score range
    task test_large_range;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("Test %0d: Large Score Range", test_num);
            $display("========================================");
            $display("Input: scores = [0, 0, 0, 0, 0, 0, 0, 10000]");
            $display("Expected: Last weight ≈ 1.0, others ≈ 0 (numerical stability)");

            for (i = 0; i < L-1; i = i + 1) begin
                scores[i] = 32'sd0;
            end
            scores[L-1] = 32'sd10000;

            run_softmax();

            $display("Completed in %0d cycles", cycle_count);
            print_weights();
            check_weights_sum(32768, 100);

            // Last weight should be close to 1.0
            check_weight_range(L-1, 30000, 32768, "Large score weight");

            // Other weights should be very small
            for (i = 0; i < L-1; i = i + 1) begin
                check_weight_range(i, 0, 1000, "Small weight");
            end

            passed_tests = passed_tests + 1;
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("========================================");
        $display("Softmax Unit Test");
        $display("========================================");
        $display("Module: softmax_unit_v2");
        $display("Parameters: L=%0d", L);
        $display("========================================\n");

        // Initialize counters
        test_num = 0;
        total_tests = 5;
        passed_tests = 0;
        failed_tests = 0;

        // Reset
        reset_dut();

        // Run tests
        test_uniform_scores();
        test_dominant_score();
        test_two_equal_scores();
        test_negative_scores();
        test_large_range();

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
        $dumpfile("tb_softmax_unit.vcd");
        $dumpvars(0, tb_softmax_unit);
    end

endmodule
