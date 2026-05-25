`timescale 1ns / 1ps

//==============================================================================
// Module: dot_product_engine
// Description: Parallel dot product computation using 16 MAC units
//
// Computes dot product of two INT8 vectors of length D (must be multiple of 16).
// Uses 16 parallel MAC units to process 16 elements per cycle.
//
// Operation:
//   result = Σ(i=0 to D-1) a[i] × b[i]
//
// Timing:
//   - Latency: 2 + (D/16) cycles
//     - 2 cycles: MAC pipeline latency
//     - D/16 cycles: Processing all elements in chunks of 16
//   - For D=64: 2 + 4 = 6 cycles total latency
//
// Resource usage:
//   - 16 MAC units (16 DSP48 slices)
//   - Adder tree for final summation
//
// Synthesis fixes (2026-04-03):
//   - Converted array ports to flattened buses for Verilog-2005 compatibility
//   - Added pack/unpack logic for bus conversion
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-01
//==============================================================================

module dot_product_engine #(
    parameter D = 64,              // Vector dimension (must be multiple of 16)
    parameter TILE_WIDTH = 16      // Number of parallel MAC units
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // Start computation
    input  wire [TILE_WIDTH*8-1:0]  a_flat,  // Input vector A (flattened)
    input  wire [TILE_WIDTH*8-1:0]  b_flat,  // Input vector B (flattened)
    output reg  [31:0] result,     // Dot product result (INT32)
    output reg         valid,      // Result valid flag
    output wire        ready       // Ready for new computation
);

    //==========================================================================
    // Port Unpacking
    //==========================================================================
    // Internal arrays for easier indexing
    wire [7:0] a [0:TILE_WIDTH-1];
    wire [7:0] b [0:TILE_WIDTH-1];

    // Unpack input buses into arrays
    genvar g;
    generate
        for (g = 0; g < TILE_WIDTH; g = g + 1) begin : unpack_inputs
            assign a[g] = a_flat[g*8 +: 8];
            assign b[g] = b_flat[g*8 +: 8];
        end
    endgenerate

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam IDLE       = 2'b00;
    localparam COMPUTING  = 2'b01;
    localparam SUMMING    = 2'b10;
    localparam DONE       = 2'b11;

    reg [1:0] state, state_next;
    reg [7:0] cycle_count;
    localparam CYCLES_NEEDED = D / TILE_WIDTH;  // 64/16 = 4 cycles

    //==========================================================================
    // MAC Unit Array
    //==========================================================================
    // MAC unit outputs
    wire [31:0] mac_acc [0:TILE_WIDTH-1];

    // MAC control signals
    reg mac_clear;
    reg mac_enable;

    // Generate 16 parallel MAC units
    generate
        for (g = 0; g < TILE_WIDTH; g = g + 1) begin : mac_array
            mac_int8 mac_inst (
                .clk    (clk),
                .rst_n  (rst_n),
                .clear  (mac_clear),
                .enable (mac_enable),
                .a      (a[g]),
                .b      (b[g]),
                .acc    (mac_acc[g])
            );
        end
    endgenerate

    //==========================================================================
    // State Machine Logic
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end

    // Next state logic
    always @(*) begin
        state_next = state;
        case (state)
            IDLE: begin
                if (start) begin
                    state_next = COMPUTING;
                end
            end

            COMPUTING: begin
                if (cycle_count == CYCLES_NEEDED - 1) begin
                    state_next = SUMMING;
                end
            end

            SUMMING: begin
                // Wait 2 cycles for MAC pipeline to flush
                if (cycle_count == 1) begin
                    state_next = DONE;
                end
            end

            DONE: begin
                state_next = IDLE;
            end
        endcase
    end

    //==========================================================================
    // Cycle Counter
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    cycle_count <= 8'd0;
                end

                COMPUTING: begin
                    if (cycle_count < CYCLES_NEEDED - 1) begin
                        cycle_count <= cycle_count + 1;
                    end else begin
                        cycle_count <= 8'd0;  // Reset for SUMMING state
                    end
                end

                SUMMING: begin
                    cycle_count <= cycle_count + 1;
                end

                DONE: begin
                    cycle_count <= 8'd0;
                end
            endcase
        end
    end

    //==========================================================================
    // MAC Control
    //==========================================================================
    always @(*) begin
        mac_clear = 1'b0;
        mac_enable = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    mac_clear = 1'b1;  // Clear accumulators when starting
                end
            end

            COMPUTING: begin
                mac_enable = 1'b1;  // Accumulate during computation
            end

            default: begin
                mac_enable = 1'b0;
            end
        endcase
    end

    //==========================================================================
    // Adder Tree for Final Summation
    //==========================================================================
    // This is a 4-level tree: 16 → 8 → 4 → 2 → 1
    reg signed [31:0] sum_level1 [0:7];   // 16 → 8
    reg signed [31:0] sum_level2 [0:3];   // 8 → 4
    reg signed [31:0] sum_level3 [0:1];   // 4 → 2
    reg signed [31:0] sum_final;          // 2 → 1

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 8; j = j + 1) sum_level1[j] <= 32'sd0;
            for (j = 0; j < 4; j = j + 1) sum_level2[j] <= 32'sd0;
            for (j = 0; j < 2; j = j + 1) sum_level3[j] <= 32'sd0;
            sum_final <= 32'sd0;
        end else if (state == SUMMING && cycle_count == 0) begin
            // Level 1: Add pairs
            for (j = 0; j < 8; j = j + 1) begin
                sum_level1[j] <= $signed(mac_acc[2*j]) + $signed(mac_acc[2*j+1]);
            end
        end else if (state == SUMMING && cycle_count == 1) begin
            // Level 2: Add pairs
            for (j = 0; j < 4; j = j + 1) begin
                sum_level2[j] <= sum_level1[2*j] + sum_level1[2*j+1];
            end
            // Level 3: Add pairs
            for (j = 0; j < 2; j = j + 1) begin
                sum_level3[j] <= sum_level2[2*j] + sum_level2[2*j+1];
            end
            // Final: Add last pair
            sum_final <= sum_level3[0] + sum_level3[1];
        end
    end

    //==========================================================================
    // Output Result
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 32'sd0;
            valid <= 1'b0;
        end else begin
            if (state == DONE) begin
                result <= sum_final;
                valid <= 1'b1;
            end else begin
                valid <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Ready Signal
    //==========================================================================
    assign ready = (state == IDLE);

endmodule
