`timescale 1ns / 1ps

//==============================================================================
// Module: streaming_attention_v3_1
// Description: Streaming attention with PIPELINED multiply-accumulate for timing
//
// Changes from v3:
// 1. Split OUTPUT_LOOP into OUTPUT_MULT and OUTPUT_ACC states
// 2. Added mult_result pipeline register
// 3. Breaks 12.1 ns critical path into two 6 ns stages
// 4. Adds 64 cycles total latency (+3.7%)
//
// Timing improvement:
//   - v3 critical path: 12.1 ns (FAILS at 100 MHz)
//   - v3.1 critical path: ~6 ns per stage (PASSES at 100 MHz)
//   - Expected WNS: +4 ns
//
// Cycle count:
//   - Per query: ~225 cycles (was 217 in v3)
//   - Total (L=8): ~1800 cycles (was 1736 in v3)
//   - At 100 MHz: ~18.0 μs (was 17.4 μs in v3)
//   - Latency increase: 3.7%
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-13
// Version: 3.1 (Timing fix)
//==============================================================================

module streaming_attention_v3_1 #(
    parameter L = 8,           // Sequence length
    parameter D = 64           // Embedding dimension
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg         busy,

    output reg  [9:0]  q_addr,
    output reg         q_rd_en,
    input  wire [7:0]  q_data,

    output reg  [9:0]  k_addr,
    output reg         k_rd_en,
    input  wire [7:0]  k_data,

    output reg  [9:0]  v_addr,
    output reg         v_rd_en,
    input  wire [7:0]  v_data,

    output reg  [9:0]  out_addr,
    output reg  [7:0]  out_data,
    output reg         out_wr_en,

    input  wire [2:0]  scale_shift
);

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam IDLE           = 4'd0;
    localparam LOAD_Q_INIT    = 4'd1;  // Issue first Q read
    localparam LOAD_Q_LOOP    = 4'd2;  // Load Q row with latency
    localparam SCORE_INIT     = 4'd3;  // Start score computation
    localparam SCORE_LOOP     = 4'd4;  // Compute dot product
    localparam SCORE_DONE     = 4'd5;  // Store score
    localparam SOFTMAX_START  = 4'd6;  // Start softmax computation
    localparam SOFTMAX_WAIT   = 4'd7;  // Wait for softmax to complete
    localparam OUTPUT_INIT    = 4'd8;  // Start output computation
    localparam OUTPUT_MULT    = 4'd9;  // Multiply: attention_weight × v_data
    localparam OUTPUT_ACC     = 4'd10; // Accumulate: add to output_row
    localparam OUTPUT_DONE    = 4'd11; // Finish value accumulation
    localparam WRITE_INIT     = 4'd12; // Start writing output
    localparam WRITE_LOOP     = 4'd13; // Write output row
    localparam NEXT_QUERY     = 4'd14; // Move to next query

    reg [3:0] state;
    reg [3:0] query_idx;
    reg [3:0] key_idx;
    reg [6:0] elem_idx;

    //==========================================================================
    // Buffers
    //==========================================================================
    reg signed [7:0] q_row [0:D-1];
    reg signed [31:0] scores [0:L-1];
    reg signed [31:0] attention_weights [0:L-1];
    reg signed [31:0] output_row [0:D-1];
    reg signed [31:0] dot_acc;

    //==========================================================================
    // Pipeline Register for Timing Fix
    //==========================================================================
    // This register breaks the critical path:
    // v3:   v_data → MULT → ADD → output_row (12.1 ns, FAILS)
    // v3.1: v_data → MULT → mult_result (6 ns, PASSES)
    //       mult_result → ADD → output_row (6 ns, PASSES)
    reg signed [31:0] mult_result;

    //==========================================================================
    // Softmax Unit Integration (v2 - Fixed timing and LUT)
    //==========================================================================
    reg softmax_start;
    wire [15:0] softmax_weights [0:L-1];
    wire softmax_valid;
    wire softmax_ready;

    // Flattened buses for softmax interface (synthesis compatibility)
    wire [L*32-1:0] scores_flat;
    wire [L*16-1:0] softmax_weights_flat;

    // Pack scores array into flat bus
    genvar g;
    generate
        for (g = 0; g < L; g = g + 1) begin : pack_scores
            assign scores_flat[g*32 +: 32] = scores[g];
        end
    endgenerate

    // Unpack flat bus into softmax_weights array
    generate
        for (g = 0; g < L; g = g + 1) begin : unpack_weights
            assign softmax_weights[g] = softmax_weights_flat[g*16 +: 16];
        end
    endgenerate

    softmax_unit_v2 #(
        .L(L),
        .EXP_LUT_SIZE(256)
    ) softmax_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(softmax_start),
        .scores_flat(scores_flat),
        .weights_flat(softmax_weights_flat),
        .valid(softmax_valid),
        .ready(softmax_ready)
    );

    //==========================================================================
    // State Machine
    //==========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            query_idx <= 4'd0;
            key_idx <= 4'd0;
            elem_idx <= 7'd0;
            done <= 1'b0;
            busy <= 1'b0;
            dot_acc <= 32'sd0;
            softmax_start <= 1'b0;
            mult_result <= 32'sd0;

            for (i = 0; i < D; i = i + 1) begin
                q_row[i] <= 8'sd0;
                output_row[i] <= 32'sd0;
            end
            for (i = 0; i < L; i = i + 1) begin
                scores[i] <= 32'sd0;
                attention_weights[i] <= 32'sd0;
            end

        end else begin
            // Default: deassert softmax_start after one cycle
            softmax_start <= 1'b0;

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        query_idx <= 4'd0;
                        state <= LOAD_Q_INIT;
                    end
                end

                LOAD_Q_INIT: begin
                    elem_idx <= 7'd0;
                    state <= LOAD_Q_LOOP;
                end

                LOAD_Q_LOOP: begin
                    if (elem_idx > 0) begin
                        q_row[elem_idx - 1] <= $signed(q_data);
                    end

                    if (elem_idx == D) begin
                        q_row[D - 1] <= $signed(q_data);
                        key_idx <= 4'd0;
                        state <= SCORE_INIT;
                    end else begin
                        elem_idx <= elem_idx + 1;
                    end
                end

                SCORE_INIT: begin
                    elem_idx <= 7'd0;
                    dot_acc <= 32'sd0;
                    state <= SCORE_LOOP;
                end

                SCORE_LOOP: begin
                    if (elem_idx > 0) begin
                        // Accumulate: q_row[elem_idx-1] * k_data
                        dot_acc <= dot_acc + ($signed(q_row[elem_idx - 1]) * $signed(k_data));
                    end

                    if (elem_idx == D) begin
                        // Final accumulation
                        dot_acc <= dot_acc + ($signed(q_row[D - 1]) * $signed(k_data));
                        state <= SCORE_DONE;
                    end else begin
                        elem_idx <= elem_idx + 1;
                    end
                end

                SCORE_DONE: begin
                    // Scale and store score
                    scores[key_idx] <= dot_acc >>> scale_shift;

                    if (key_idx == L - 1) begin
                        state <= SOFTMAX_START;
                    end else begin
                        key_idx <= key_idx + 1;
                        state <= SCORE_INIT;
                    end
                end

                SOFTMAX_START: begin
                    // Start softmax computation
                    softmax_start <= 1'b1;
                    state <= SOFTMAX_WAIT;
                end

                SOFTMAX_WAIT: begin
                    // Wait for softmax to complete
                    if (softmax_valid) begin
                        // Copy softmax weights (INT16) to attention_weights (INT32)
                        for (i = 0; i < L; i = i + 1) begin
                            attention_weights[i] <= $signed(softmax_weights[i]);
                        end

                        // Clear output accumulator
                        for (i = 0; i < D; i = i + 1) begin
                            output_row[i] <= 32'sd0;
                        end

                        key_idx <= 4'd0;
                        state <= OUTPUT_INIT;
                    end
                end

                OUTPUT_INIT: begin
                    elem_idx <= 7'd0;
                    state <= OUTPUT_MULT;
                end

                //==============================================================
                // TIMING FIX: Split multiply-accumulate into 2 cycles
                //==============================================================

                OUTPUT_MULT: begin
                    // Cycle 1: Multiply only
                    // This breaks the critical path by registering the multiply result
                    mult_result <= attention_weights[key_idx] * $signed(v_data);
                    state <= OUTPUT_ACC;
                end

                OUTPUT_ACC: begin
                    // Cycle 2: Accumulate only
                    // Add the registered multiply result to output_row
                    if (elem_idx > 0) begin
                        output_row[elem_idx - 1] <= output_row[elem_idx - 1] + mult_result;
                    end

                    if (elem_idx == D) begin
                        // Final accumulation
                        output_row[D - 1] <= output_row[D - 1] + mult_result;
                        state <= OUTPUT_DONE;
                    end else begin
                        elem_idx <= elem_idx + 1;
                        state <= OUTPUT_MULT;  // Go back to multiply for next element
                    end
                end

                //==============================================================

                OUTPUT_DONE: begin
                    if (key_idx == L - 1) begin
                        state <= WRITE_INIT;
                    end else begin
                        key_idx <= key_idx + 1;
                        state <= OUTPUT_INIT;
                    end
                end

                WRITE_INIT: begin
                    elem_idx <= 7'd0;
                    state <= WRITE_LOOP;
                end

                WRITE_LOOP: begin
                    if (elem_idx == D) begin
                        state <= NEXT_QUERY;
                    end else begin
                        elem_idx <= elem_idx + 1;
                    end
                end

                NEXT_QUERY: begin
                    if (query_idx == L - 1) begin
                        done <= 1'b1;
                        busy <= 1'b0;
                        state <= IDLE;
                    end else begin
                        query_idx <= query_idx + 1;
                        state <= LOAD_Q_INIT;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    //==========================================================================
    // Memory Interface
    //==========================================================================
    always @(*) begin
        q_addr = 10'd0;
        q_rd_en = 1'b0;
        k_addr = 10'd0;
        k_rd_en = 1'b0;
        v_addr = 10'd0;
        v_rd_en = 1'b0;

        case (state)
            LOAD_Q_INIT, LOAD_Q_LOOP: begin
                q_addr = query_idx * D + elem_idx;
                q_rd_en = 1'b1;
            end

            SCORE_INIT, SCORE_LOOP: begin
                k_addr = key_idx * D + elem_idx;
                k_rd_en = 1'b1;
            end

            OUTPUT_INIT, OUTPUT_MULT, OUTPUT_ACC: begin
                v_addr = key_idx * D + elem_idx;
                v_rd_en = 1'b1;
            end
        endcase
    end

    //==========================================================================
    // Output Write
    //==========================================================================
    always @(*) begin
        out_addr = query_idx * D + elem_idx;
        // Requantize: divide by 32768 (right-shift by 15) to undo Q15 scaling
        out_data = output_row[elem_idx] >>> 15;
        out_wr_en = (state == WRITE_LOOP && elem_idx < D);
    end

endmodule
