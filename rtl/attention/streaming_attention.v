`timescale 1ns / 1ps

//==============================================================================
// Module: streaming_attention
// Description: Top-level streaming attention module
//
// Implements scaled dot-product attention with streaming computation:
//   Attention(Q, K, V) = softmax(Q·K^T / √d_k) · V
//
// Streaming approach:
//   - Process one query at a time
//   - Compute attention scores for all keys
//   - Apply softmax
//   - Compute weighted sum of values
//   - Memory usage: O(L) instead of O(L²)
//
// Parameters:
//   L = 8:  Sequence length
//   D = 64: Embedding dimension
//   TILE_WIDTH = 16: Parallel processing width
//
// Timing:
//   - Per query: ~114 cycles (predicted)
//   - Total (L=8): ~912 cycles
//   - At 100 MHz: ~9.12 μs
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-01
//==============================================================================

module streaming_attention #(
    parameter L = 8,           // Sequence length
    parameter D = 64,          // Embedding dimension
    parameter TILE_WIDTH = 16  // Parallel processing width
)(
    // Clock and reset
    input  wire        clk,
    input  wire        rst_n,

    // Control interface
    input  wire        start,
    output reg         done,
    output reg         busy,

    // Q matrix input (L×D, INT8)
    output reg  [9:0]  q_addr,
    output reg         q_rd_en,
    input  wire [7:0]  q_data,

    // K matrix input (L×D, INT8)
    output reg  [9:0]  k_addr,
    output reg         k_rd_en,
    input  wire [7:0]  k_data,

    // V matrix input (L×D, INT8)
    output reg  [9:0]  v_addr,
    output reg         v_rd_en,
    input  wire [7:0]  v_data,

    // Output matrix (L×D, INT8)
    output reg  [9:0]  out_addr,
    output reg  [7:0]  out_data,
    output reg         out_wr_en,

    // Configuration
    input  wire [2:0]  scale_shift  // Right-shift for √d_k scaling (default: 3)
);

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam IDLE           = 4'd0;
    localparam LOAD_Q         = 4'd1;
    localparam COMPUTE_SCORES = 4'd2;
    localparam SOFTMAX        = 4'd3;
    localparam COMPUTE_OUTPUT = 4'd4;
    localparam WRITE_OUTPUT   = 4'd5;
    localparam NEXT_QUERY     = 4'd6;

    reg [3:0] state, state_next;
    reg [3:0] query_idx;        // Current query index [0, L-1]
    reg [3:0] key_idx;          // Current key index [0, L-1]
    reg [6:0] element_idx;      // Current element index [0, D-1]
    reg [3:0] tile_idx;         // Current tile index [0, D/TILE_WIDTH-1]

    //==========================================================================
    // Internal Buffers
    //==========================================================================
    reg [7:0] q_buffer [0:D-1];      // Current query row
    reg [7:0] k_buffer [0:D-1];      // Current key row
    reg [7:0] v_buffer [0:D-1];      // Current value row
    reg signed [31:0] scores [0:L-1];        // Attention scores for current query
    reg [15:0] attention_weights [0:L-1];    // Softmax output (Q15)
    reg signed [31:0] output_acc [0:D-1];    // Output accumulator

    //==========================================================================
    // Dot Product Engine Signals
    //==========================================================================
    reg dp_start;
    wire dp_ready;
    wire dp_valid;
    wire signed [31:0] dp_result;
    reg [7:0] dp_a [0:TILE_WIDTH-1];
    reg [7:0] dp_b [0:TILE_WIDTH-1];

    dot_product_engine #(
        .D(D),
        .TILE_WIDTH(TILE_WIDTH)
    ) dot_product_inst (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (dp_start),
        .a      (dp_a),
        .b      (dp_b),
        .result (dp_result),
        .valid  (dp_valid),
        .ready  (dp_ready)
    );

    //==========================================================================
    // Softmax Unit Signals
    //==========================================================================
    reg sm_start;
    wire sm_ready;
    wire sm_valid;
    wire [15:0] sm_weights [0:L-1];

    softmax_unit #(
        .L(L)
    ) softmax_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (sm_start),
        .scores  (scores),
        .weights (sm_weights),
        .valid   (sm_valid),
        .ready   (sm_ready)
    );

    //==========================================================================
    // State Machine
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
                if (start) state_next = LOAD_Q;
            end

            LOAD_Q: begin
                if (element_idx == D - 1) state_next = COMPUTE_SCORES;
            end

            COMPUTE_SCORES: begin
                if (key_idx == L - 1 && dp_valid) state_next = SOFTMAX;
            end

            SOFTMAX: begin
                if (sm_valid) state_next = COMPUTE_OUTPUT;
            end

            COMPUTE_OUTPUT: begin
                if (key_idx == L - 1 && element_idx == D - 1) state_next = WRITE_OUTPUT;
            end

            WRITE_OUTPUT: begin
                if (element_idx == D - 1) state_next = NEXT_QUERY;
            end

            NEXT_QUERY: begin
                if (query_idx == L - 1) begin
                    state_next = IDLE;
                end else begin
                    state_next = LOAD_Q;
                end
            end
        endcase
    end

    //==========================================================================
    // Query Index Counter
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            query_idx <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    query_idx <= 4'd0;
                end

                NEXT_QUERY: begin
                    if (query_idx < L - 1) begin
                        query_idx <= query_idx + 1;
                    end else begin
                        query_idx <= 4'd0;
                    end
                end
            endcase
        end
    end

    //==========================================================================
    // Key/Value Index Counter
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_idx <= 4'd0;
        end else begin
            case (state)
                COMPUTE_SCORES: begin
                    if (dp_valid) begin
                        if (key_idx < L - 1) begin
                            key_idx <= key_idx + 1;
                        end else begin
                            key_idx <= 4'd0;
                        end
                    end
                end

                COMPUTE_OUTPUT: begin
                    if (element_idx == D - 1) begin
                        if (key_idx < L - 1) begin
                            key_idx <= key_idx + 1;
                        end else begin
                            key_idx <= 4'd0;
                        end
                    end
                end

                default: begin
                    key_idx <= 4'd0;
                end
            endcase
        end
    end

    //==========================================================================
    // Element Index Counter
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            element_idx <= 7'd0;
        end else begin
            case (state)
                LOAD_Q, WRITE_OUTPUT: begin
                    if (element_idx < D - 1) begin
                        element_idx <= element_idx + 1;
                    end else begin
                        element_idx <= 7'd0;
                    end
                end

                COMPUTE_OUTPUT: begin
                    if (element_idx < D - 1) begin
                        element_idx <= element_idx + 1;
                    end else begin
                        element_idx <= 7'd0;
                    end
                end

                default: begin
                    element_idx <= 7'd0;
                end
            endcase
        end
    end

    //==========================================================================
    // Load Q Buffer
    //==========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < D; i = i + 1) begin
                q_buffer[i] <= 8'd0;
            end
        end else if (state == LOAD_Q) begin
            q_buffer[element_idx] <= q_data;
        end
    end

    //==========================================================================
    // Compute Scores (Q·K^T)
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L; i = i + 1) begin
                scores[i] <= 32'sd0;
            end
        end else if (state == COMPUTE_SCORES && dp_valid) begin
            // Scale and store score
            scores[key_idx] <= dp_result >>> scale_shift;
        end
    end

    //==========================================================================
    // Store Softmax Weights
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L; i = i + 1) begin
                attention_weights[i] <= 16'd0;
            end
        end else if (sm_valid) begin
            for (i = 0; i < L; i = i + 1) begin
                attention_weights[i] <= sm_weights[i];
            end
        end
    end

    //==========================================================================
    // Compute Weighted Output (A·V)
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < D; i = i + 1) begin
                output_acc[i] <= 32'sd0;
            end
        end else if (state == SOFTMAX) begin
            // Clear accumulator when starting new output computation
            for (i = 0; i < D; i = i + 1) begin
                output_acc[i] <= 32'sd0;
            end
        end else if (state == COMPUTE_OUTPUT) begin
            // Accumulate: output[element_idx] += attention_weights[key_idx] * v_buffer[element_idx]
            output_acc[element_idx] <= output_acc[element_idx] +
                ($signed(attention_weights[key_idx]) * $signed(v_buffer[element_idx]));
        end
    end

    //==========================================================================
    // Memory Interface Control
    //==========================================================================
    always @(*) begin
        // Default values
        q_addr = 10'd0;
        q_rd_en = 1'b0;
        k_addr = 10'd0;
        k_rd_en = 1'b0;
        v_addr = 10'd0;
        v_rd_en = 1'b0;

        case (state)
            LOAD_Q: begin
                q_addr = query_idx * D + element_idx;
                q_rd_en = 1'b1;
            end

            COMPUTE_SCORES: begin
                k_addr = key_idx * D + element_idx;
                k_rd_en = 1'b1;
            end

            COMPUTE_OUTPUT: begin
                v_addr = key_idx * D + element_idx;
                v_rd_en = 1'b1;
            end
        endcase
    end

    //==========================================================================
    // Output Write
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_addr <= 10'd0;
            out_data <= 8'd0;
            out_wr_en <= 1'b0;
        end else if (state == WRITE_OUTPUT) begin
            out_addr <= query_idx * D + element_idx;
            // Requantize INT32 to INT8 (divide by 32768 for Q15, then clip)
            out_data <= output_acc[element_idx] >>> 15;  // Right-shift by 15 for Q15
            out_wr_en <= 1'b1;
        end else begin
            out_wr_en <= 1'b0;
        end
    end

    //==========================================================================
    // Control Signals
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            busy <= (state != IDLE);
            done <= (state == NEXT_QUERY && query_idx == L - 1);
        end
    end

    // Dot product start signal
    always @(*) begin
        dp_start = (state == COMPUTE_SCORES && dp_ready);
    end

    // Softmax start signal
    always @(*) begin
        sm_start = (state == COMPUTE_SCORES && key_idx == L - 1 && dp_valid);
    end

endmodule
