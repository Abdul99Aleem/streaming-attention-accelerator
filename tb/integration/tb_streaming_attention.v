//==============================================================================
// Testbench: tb_streaming_attention
// Description: Integration test for streaming attention module
//
// Tests the complete attention pipeline:
//   1. Load Q, K, V matrices
//   2. Compute attention: softmax(Q·K^T / √d_k) · V
//   3. Compare output with Python golden reference
//
// Test methodology:
//   - Generate test vectors using Python reference model
//   - Load vectors into memory
//   - Run RTL computation
//   - Compare outputs element-by-element
//   - Report error metrics
//
// Version: Updated for streaming_attention_v3 with proper softmax
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-03
//==============================================================================

`timescale 1ns / 1ps

module tb_streaming_attention;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz clock
    parameter L = 8;            // Sequence length
    parameter D = 64;           // Embedding dimension
    parameter TILE_WIDTH = 16;  // Parallel processing width

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    wire        done;
    wire        busy;

    wire [9:0]  q_addr;
    wire        q_rd_en;
    reg  [7:0]  q_data;

    wire [9:0]  k_addr;
    wire        k_rd_en;
    reg  [7:0]  k_data;

    wire [9:0]  v_addr;
    wire        v_rd_en;
    reg  [7:0]  v_data;

    wire [9:0]  out_addr;
    wire [7:0]  out_data;
    wire        out_wr_en;

    reg  [2:0]  scale_shift;

    //==========================================================================
    // Memory Arrays
    //==========================================================================
    reg [7:0] q_mem [0:L*D-1];  // Q matrix memory
    reg [7:0] k_mem [0:L*D-1];  // K matrix memory
    reg [7:0] v_mem [0:L*D-1];  // V matrix memory
    reg [7:0] out_mem [0:L*D-1]; // Output memory
    reg [7:0] expected_out [0:L*D-1]; // Expected output from Python

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    streaming_attention_v3 #(
        .L(L),
        .D(D)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .done        (done),
        .busy        (busy),
        .q_addr      (q_addr),
        .q_rd_en     (q_rd_en),
        .q_data      (q_data),
        .k_addr      (k_addr),
        .k_rd_en     (k_rd_en),
        .k_data      (k_data),
        .v_addr      (v_addr),
        .v_rd_en     (v_rd_en),
        .v_data      (v_data),
        .out_addr    (out_addr),
        .out_data    (out_data),
        .out_wr_en   (out_wr_en),
        .scale_shift (scale_shift)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Memory Read Logic
    //==========================================================================
    always @(posedge clk) begin
        if (q_rd_en) begin
            q_data <= q_mem[q_addr];
        end
    end

    always @(posedge clk) begin
        if (k_rd_en) begin
            k_data <= k_mem[k_addr];
        end
    end

    always @(posedge clk) begin
        if (v_rd_en) begin
            v_data <= v_mem[v_addr];
        end
    end

    //==========================================================================
    // Memory Write Logic
    //==========================================================================
    always @(posedge clk) begin
        if (out_wr_en) begin
            out_mem[out_addr] <= out_data;
        end
    end

    //==========================================================================
    // Test Variables
    //==========================================================================
    integer i, j;
    integer errors;
    integer max_error;
    integer total_error;
    real avg_error;
    integer cycle_count;

    //==========================================================================
    // File Handles
    //==========================================================================
    integer q_file, k_file, v_file, expected_file;
    integer scan_result;

    //==========================================================================
    // Tasks
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            start = 0;
            scale_shift = 3'd3;  // √64 = 8 = 2^3
            repeat(5) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task load_test_vectors;
        begin
            $display("Loading test vectors from files...");

            // Load Q matrix
            q_file = $fopen("test_vectors/q_matrix.txt", "r");
            if (q_file == 0) begin
                $display("[ERROR] Cannot open q_matrix.txt");
                $display("[INFO] Generating random test vectors instead");
                for (i = 0; i < L*D; i = i + 1) begin
                    q_mem[i] = $random % 256;
                end
            end else begin
                for (i = 0; i < L*D; i = i + 1) begin
                    scan_result = $fscanf(q_file, "%d\n", q_mem[i]);
                end
                $fclose(q_file);
                $display("  Q matrix loaded (%0d elements)", L*D);
            end

            // Load K matrix
            k_file = $fopen("test_vectors/k_matrix.txt", "r");
            if (k_file == 0) begin
                $display("[INFO] Generating random K matrix");
                for (i = 0; i < L*D; i = i + 1) begin
                    k_mem[i] = $random % 256;
                end
            end else begin
                for (i = 0; i < L*D; i = i + 1) begin
                    scan_result = $fscanf(k_file, "%d\n", k_mem[i]);
                end
                $fclose(k_file);
                $display("  K matrix loaded (%0d elements)", L*D);
            end

            // Load V matrix
            v_file = $fopen("test_vectors/v_matrix.txt", "r");
            if (v_file == 0) begin
                $display("[INFO] Generating random V matrix");
                for (i = 0; i < L*D; i = i + 1) begin
                    v_mem[i] = $random % 256;
                end
            end else begin
                for (i = 0; i < L*D; i = i + 1) begin
                    scan_result = $fscanf(v_file, "%d\n", v_mem[i]);
                end
                $fclose(v_file);
                $display("  V matrix loaded (%0d elements)", L*D);
            end

            // Load expected output
            expected_file = $fopen("test_vectors/expected_output.txt", "r");
            if (expected_file == 0) begin
                $display("[WARNING] Cannot open expected_output.txt");
                $display("[WARNING] Output comparison will be skipped");
                for (i = 0; i < L*D; i = i + 1) begin
                    expected_out[i] = 8'd0;
                end
            end else begin
                for (i = 0; i < L*D; i = i + 1) begin
                    scan_result = $fscanf(expected_file, "%d\n", expected_out[i]);
                end
                $fclose(expected_file);
                $display("  Expected output loaded (%0d elements)", L*D);
            end

            $display("Test vectors loaded successfully\n");
        end
    endtask

    task run_attention;
        begin
            $display("Starting attention computation...");
            cycle_count = 0;

            // Start computation
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for completion
            while (!done) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;

                // Timeout check
                if (cycle_count > 10000) begin
                    $display("[ERROR] Computation timeout after %0d cycles", cycle_count);
                    $finish;
                end
            end

            @(posedge clk);
            $display("Computation completed in %0d cycles", cycle_count);
            $display("Expected cycles: ~1736 (with softmax_unit_v2)");
            $display("Cycle efficiency: %.1f%%\n", (1736.0 / cycle_count) * 100.0);
        end
    endtask

    task compare_outputs;
        begin
            $display("Comparing outputs with expected values...");

            errors = 0;
            max_error = 0;
            total_error = 0;

            for (i = 0; i < L*D; i = i + 1) begin
                integer diff;
                diff = out_mem[i] - expected_out[i];
                if (diff < 0) diff = -diff;

                total_error = total_error + diff;

                if (diff > max_error) begin
                    max_error = diff;
                end

                if (diff > 2) begin  // Tolerance: ±2 for INT8
                    errors = errors + 1;
                    if (errors <= 10) begin  // Print first 10 errors
                        $display("  [ERROR] Element %0d: got %0d, expected %0d (diff=%0d)",
                                 i, $signed(out_mem[i]), $signed(expected_out[i]), diff);
                    end
                end
            end

            avg_error = total_error / (L * D * 1.0);

            $display("\n========================================");
            $display("Output Comparison Results");
            $display("========================================");
            $display("Total elements:  %0d", L*D);
            $display("Errors (>2):     %0d", errors);
            $display("Max error:       %0d", max_error);
            $display("Average error:   %.2f", avg_error);
            $display("Error rate:      %.2f%%", (errors * 100.0) / (L*D));

            if (errors == 0) begin
                $display("\n*** ALL OUTPUTS MATCH ***");
            end else if (errors < (L*D) / 10) begin
                $display("\n*** MOSTLY CORRECT (<%0d%% errors) ***", 10);
            end else begin
                $display("\n*** SIGNIFICANT ERRORS DETECTED ***");
            end
            $display("========================================\n");
        end
    endtask

    task print_matrix;
        input [255:0] name;
        input integer is_output;
        begin
            $display("%s:", name);
            for (i = 0; i < L; i = i + 1) begin
                $write("  Row %0d: ", i);
                for (j = 0; j < 8; j = j + 1) begin  // Print first 8 elements
                    if (is_output) begin
                        $write("%4d ", $signed(out_mem[i*D + j]));
                    end else begin
                        $write("%4d ", $signed(q_mem[i*D + j]));
                    end
                end
                $write("...\n");
            end
            $display("");
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("========================================");
        $display("Streaming Attention Integration Test");
        $display("========================================");
        $display("Parameters:");
        $display("  L (sequence length):    %0d", L);
        $display("  D (embedding dim):      %0d", D);
        $display("  TILE_WIDTH:             %0d", TILE_WIDTH);
        $display("  Clock period:           %0d ns", CLK_PERIOD);
        $display("  Clock frequency:        %0d MHz", 1000/CLK_PERIOD);
        $display("========================================\n");

        // Initialize
        reset_dut();

        // Load test vectors
        load_test_vectors();

        // Print sample of input (first row of Q)
        $display("Sample input (Q matrix, first row, first 8 elements):");
        $write("  ");
        for (i = 0; i < 8; i = i + 1) begin
            $write("%4d ", $signed(q_mem[i]));
        end
        $write("...\n\n");

        // Run attention computation
        run_attention();

        // Print sample of output (first row, first 8 elements)
        $display("Sample output (first row, first 8 elements):");
        $write("  ");
        for (i = 0; i < 8; i = i + 1) begin
            $write("%4d ", $signed(out_mem[i]));
        end
        $write("...\n\n");

        // Compare with expected output
        compare_outputs();

        // Performance summary
        $display("========================================");
        $display("Performance Summary");
        $display("========================================");
        $display("Latency:         %0d cycles", cycle_count);
        $display("Time:            %.2f μs", cycle_count * CLK_PERIOD / 1000.0);
        $display("Throughput:      %.0f attentions/sec", 1000000.0 / (cycle_count * CLK_PERIOD / 1000.0));
        $display("========================================\n");

        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #1000000;  // 1 ms timeout
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

    //==========================================================================
    // Waveform Dump
    //==========================================================================
    initial begin
        $dumpfile("tb_streaming_attention.vcd");
        $dumpvars(0, tb_streaming_attention);
    end

endmodule
