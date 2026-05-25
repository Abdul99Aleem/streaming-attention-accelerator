`timescale 1ns / 1ps

//==============================================================================
// Module: mac_int8
// Description: Multiply-Accumulate unit for INT8 operands with INT32 accumulator
//
// This is the fundamental building block for dot product computation.
// Performs: acc = acc + (a × b)
//
// Features:
// - Signed INT8 multiplication
// - INT32 accumulation (prevents overflow)
// - Synchronous clear
// - Single-cycle throughput (pipelined)
//
// Timing:
// - 1 cycle latency for multiply
// - 1 cycle latency for accumulate
// - Total: 2 cycles from input to accumulated output
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-01
//==============================================================================

module mac_int8 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,      // Synchronous clear of accumulator
    input  wire        enable,     // Enable accumulation
    input  wire [7:0]  a,          // Operand A (signed INT8)
    input  wire [7:0]  b,          // Operand B (signed INT8)
    output reg  [31:0] acc         // Accumulator (signed INT32)
);

    // Pipeline stage: multiplication result
    reg signed [15:0] product;

    // Multiply stage (cycle 1)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product <= 16'sd0;
        end else begin
            // Signed multiplication: INT8 × INT8 → INT16
            product <= $signed(a) * $signed(b);
        end
    end

    // Accumulate stage (cycle 2)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 32'sd0;
        end else if (clear) begin
            acc <= 32'sd0;
        end else if (enable) begin
            // Sign-extend product to INT32 and accumulate
            acc <= acc + {{16{product[15]}}, product};
        end
    end

endmodule
