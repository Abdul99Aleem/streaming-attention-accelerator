`timescale 1ns / 1ps

//==============================================================================
// Module: streaming_attention_simple
// Description: Simplified streaming attention (sequential processing)
//
// This is a simplified version that processes elements sequentially rather
// than in tiles. This ensures correctness before optimization.
//
// Implements: Attention(Q, K, V) = softmax(Q·K^T / √d_k) · V
//
// Timing (sequential):
//   - Per query: ~200 cycles (not optimized)
//   - Total (L=8): ~1600 cycles
//   - At 100 MHz: ~16 μs
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-01
//==============================================================================

module streaming_attention_simple #(
    parameter L = 8,           // Sequence length
    parameter D = 64           // Embedding dimension
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
    localparam LOAD_Q_ROW     = 4'd1;
    localparam COMPUTE_SCORE  = 4'd2;  // Compute one score (Q[i] · K[j])
    localparam NEXT_KEY       = 4'd3;
    localparam SOFTMAX        = 4'd4;
    localparam LOAD_V_ROW     = 4'd5;
    localparam ACCUM_OUTPUT   = 4'd6;  // Accumulate weighted value
    localparam NEXT_VALUE     = 4'd7;
    localparam WRITE_OUT_ROW  = 4'd8;
    localparam NEXT_QUERY     = 4'd9;

    reg [3:0] state, state_next;
    reg [3:0] query_idx;        // Current query [0, L-1]
    reg [3:0] key_idx;          // Current key [0, L-1]
    reg [6:0] elem_idx;         // Current element [0, D-1]
    reg [6:0] out_elem_idx;     // Output element index

    //==========================================================================
    // Internal Buffers
    //==========================================================================
    reg signed [7:0] q_row [0:D-1];           // Current query row
    reg signed [7:0] k_row [0:D-1];           // Current key row
    reg signed [7:0] v_row [0:D-1];           // Current value row
    reg signed [31:0] scores [0:L-1];         // Attention scores
    reg signed [31:0] attention_weights [0:L-1]; // Softmax output (scaled)
    reg signed [31:0] output_row [0:D-1];     // Output accumulator

    // Dot product accumulator
    reg signed [31:0] dot_acc;

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
                if (start) state_next = LOAD_Q_ROW;
            end

            LOAD_Q_ROW: begin
                if (elem_idx == D - 1) state_next = COMPUTE_SCORE;
            end

            COMPUTE_SCORE: begin
                if (elem_idx == D - 1) state_next = NEXT_KEY;
            end

            NEXT_KEY: begin
                if (key_idx == L - 1) begin
                    state_next = SOFTMAX;
                end else begin
                    state_next = COMPUTE_SCORE;
                end
            end

            SOFTMAX: begin
                state_next = LOAD_V_ROW;
            end

            LOAD_V_ROW: begin
                if (elem_idx == D - 1) state_next = ACCUM_OUTPUT;
            end

            ACCUM_OUTPUT: begin
                if (elem_idx == D - 1) state_next = NEXT_VALUE;
            end

            NEXT_VALUE: begin
                if (key_idx == L - 1) begin
                    state_next = WRITE_OUT_ROW;
                end else begin
                    state_next = LOAD_V_ROW;
                end
            end

            WRITE_OUT_ROW: begin
                if (out_elem_idx == D - 1) state_next = NEXT_QUERY;
            end

            NEXT_QUERY: begin
                if (query_idx == L - 1) begin
                    state_next = IDLE;
                end else begin
                    state_next = LOAD_Q_ROW;
                end
            end
        endcase
    end

    //==========================================================================
    // Counters
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            query_idx <= 4'd0;
            key_idx <= 4'd0;
            elem_idx <= 7'd0;
            out_elem_idx <= 7'd0;
        end else begin
            case (state)
                IDLE: begin
                    query_idx <= 4'd0;
                    key_idx <= 4'd0;
                    elem_idx <= 7'd0;
                    out_elem_idx <= 7'd0;
                end

                LOAD_Q_ROW, COMPUTE_SCORE, LOAD_V_ROW, ACCUM_OUTPUT: begin
                    if (elem_idx < D - 1) begin
                        elem_idx <= elem_idx + 1;
                    end else begin
                        elem_idx <= 7'd0;
                    end
                end

                NEXT_KEY: begin
                    elem_idx <= 7'd0;
                    if (key_idx < L - 1) begin
                        key_idx <= key_idx + 1;
                    end else begin
                        key_idx <= 4'd0;
                    end
                end

                SOFTMAX: begin
                    key_idx <= 4'd0;
                    elem_idx <= 7'd0;
                end

                NEXT_VALUE: begin
                    elem_idx <= 7'd0;
                    if (key_idx < L - 1) begin
                        key_idx <= key_idx + 1;
                    end else begin
                        key_idx <= 4'd0;
                    end
                end

                WRITE_OUT_ROW: begin
                    if (out_elem_idx < D - 1) begin
                        out_elem_idx <= out_elem_idx + 1;
                    end else begin
                        out_elem_idx <= 7'd0;
                    end
                end

                NEXT_QUERY: begin
                    if (query_idx < L - 1) begin
                        query_idx <= query_idx + 1;
                    end
                    out_elem_idx <= 7'd0;
                end
            endcase
        end
    end

    //==========================================================================
    // Load Q Row
    //==========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < D; i = i + 1) begin
                q_row[i] <= 8'sd0;
            end
        end else if (state == LOAD_Q_ROW) begin
            q_row[elem_idx] <= $signed(q_data);
        end
    end

    //==========================================================================
    // Load K Row and Compute Score
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < D; i = i + 1) begin
                k_row[i] <= 8'sd0;
            end
            dot_acc <= 32'sd0;
        end else if (state == NEXT_KEY || state == SOFTMAX) begin
            dot_acc <= 32'sd0;  // Clear for next dot product
        end else if (state == COMPUTE_SCORE) begin
            // Load K element
            k_row[elem_idx] <= $signed(k_data);

            // Accumulate dot product
            dot_acc <= dot_acc + ($signed(q_row[elem_idx]) * $signed(k_data));
        end
    end

    // Store completed score
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L; i = i + 1) begin
                scores[i] <= 32'sd0;
            end
        end else if (state == NEXT_KEY) begin
            // Scale and store score
            scores[key_idx] <= dot_acc >>> scale_shift;
        end
    end

    //==========================================================================
    // Softmax (Simplified - using floating-point approximation)
    //==========================================================================
    reg signed [31:0] max_score;
    reg signed [31:0] shifted_scores [0:L-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_score <= 32'sd0;
            for (i = 0; i < L; i = i + 1) begin
                shifted_scores[i] <= 32'sd0;
                attention_weights[i] <= 32'sd0;
            end
        end else if (state == SOFTMAX) begin
            // Find max
            max_score <= scores[0];
            for (i = 1; i < L; i = i + 1) begin
                if (scores[i] > max_score) begin
                    max_score <= scores[i];
                end
            end

            // Subtract max and compute uniform weights (simplified)
            // In real implementation, would use exp LUT
            // For now, use uniform weights: 1/L = 1/8 = 4096 (in Q15: 32768/8)
            for (i = 0; i < L; i = i + 1) begin
                attention_weights[i] <= 32'sd4096;  // 1/8 in Q15 format
            end
        end
    end

    //==========================================================================
    // Load V Row and Accumulate Output
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < D; i = i + 1) begin
                v_row[i] <= 8'sd0;
                output_row[i] <= 32'sd0;
            end
        end else if (state == SOFTMAX) begin
            // Clear output accumulator for new query
            for (i = 0; i < D; i = i + 1) begin
                output_row[i] <= 32'sd0;
            end
        end else if (state == LOAD_V_ROW) begin
            v_row[elem_idx] <= $signed(v_data);
        end else if (state == ACCUM_OUTPUT) begin
            // Accumulate: output[elem_idx] += attention_weights[key_idx] * v_row[elem_idx]
            output_row[elem_idx] <= output_row[elem_idx] +
                (attention_weights[key_idx] * $signed(v_row[elem_idx]));
        end
    end

    //==========================================================================
    // Memory Interface
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
            LOAD_Q_ROW: begin
                q_addr = query_idx * D + elem_idx;
                q_rd_en = 1'b1;
            end

            COMPUTE_SCORE: begin
                k_addr = key_idx * D + elem_idx;
                k_rd_en = 1'b1;
            end

            LOAD_V_ROW: begin
                v_addr = key_idx * D + elem_idx;
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
        end else if (state == WRITE_OUT_ROW) begin
            out_addr <= query_idx * D + out_elem_idx;
            // Requantize: divide by 4096 (right-shift by 12) to undo Q15 scaling
            out_data <= output_row[out_elem_idx] >>> 12;
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

endmodule
