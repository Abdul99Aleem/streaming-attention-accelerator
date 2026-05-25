`timescale 1ns / 1ps

//==============================================================================
// Module: softmax_unit_v2
// Description: Fixed softmax computation in INT16 Q15 fixed-point
//
// Computes: output[i] = exp(input[i]) / Σ exp(input[j])
//
// Uses max-subtraction trick for numerical stability:
//   1. Find max_val = max(input[0..L-1])
//   2. Shift: shifted[i] = input[i] - max_val
//   3. Exp: exp_vals[i] = exp(shifted[i]) via LUT
//   4. Sum: sum = Σ exp_vals[i]
//   5. Normalize: output[i] = exp_vals[i] / sum
//
// Output format: INT16 Q15 fixed-point (range [0, 32767] representing [0, 1])
//
// Fixes from v1:
//   - Proper exp LUT values (loaded from generated file)
//   - Fixed max-find timing (combinational tree)
//   - Fixed shifted_scores timing (computed after max is stable)
//   - Fixed division (shift-based approximation)
//
// Synthesis fixes (2026-04-03):
//   - Converted array ports to flattened buses for Verilog-2005 compatibility
//   - Moved block-scoped variables to module scope
//   - Added pack/unpack logic for bus conversion
//
// Timing:
//   - FIND_MAX: 1 cycle (combinational tree)
//   - SHIFT: 1 cycle (compute shifted scores)
//   - COMPUTE_EXP: L cycles (sequential, 1 per element)
//   - SUM_EXP: 1 cycle (combinational tree)
//   - DIVIDE: L cycles (sequential, 1 per element)
//   - Total: 3 + 2L cycles
//   - For L=8: 3 + 16 = 19 cycles
//
// Author: Generated for streaming-attention-accelerator project
// Date: 2026-04-03
//==============================================================================

module softmax_unit_v2 #(
    parameter L = 8,               // Sequence length
    parameter EXP_LUT_SIZE = 256   // Exponentiation LUT size
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,     // Start softmax computation
    input  wire [L*32-1:0]  scores_flat,   // Input scores (INT32, scaled) - flattened
    output wire [L*16-1:0]  weights_flat,  // Output weights (INT16 Q15) - flattened
    output reg          valid,     // Output valid flag
    output wire         ready      // Ready for new computation
);

    //==========================================================================
    // Port Unpacking/Packing
    //==========================================================================
    // Internal arrays for easier indexing
    wire [31:0] scores [0:L-1];
    reg  [15:0] weights [0:L-1];

    // Unpack input bus into array
    genvar g;
    generate
        for (g = 0; g < L; g = g + 1) begin : unpack_scores
            assign scores[g] = scores_flat[g*32 +: 32];
        end
    endgenerate

    // Pack output array into bus
    generate
        for (g = 0; g < L; g = g + 1) begin : pack_weights
            assign weights_flat[g*16 +: 16] = weights[g];
        end
    endgenerate

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam IDLE       = 3'b000;
    localparam FIND_MAX   = 3'b001;
    localparam SHIFT      = 3'b010;
    localparam COMPUTE_EXP = 3'b011;
    localparam SUM_EXP    = 3'b100;
    localparam DIVIDE     = 3'b101;
    localparam DONE       = 3'b110;

    reg [2:0] state, state_next;
    reg [3:0] element_idx;  // Index for sequential operations

    //==========================================================================
    // Internal Storage
    //==========================================================================
    reg signed [31:0] max_score;
    reg signed [31:0] shifted_scores [0:L-1];
    reg [15:0] exp_values [0:L-1];  // Q15 format
    reg [31:0] sum_exp;             // Sum of exp values (Q15)
    reg [4:0] sum_shift;            // Shift amount for division approximation

    // Variables for COMPUTE_EXP state (moved to module scope for synthesis)
    reg [7:0] lut_addr;
    reg signed [31:0] shifted_val;

    // Variables for DIVIDE state (moved to module scope for synthesis)
    reg [31:0] numerator;
    reg [31:0] denominator;
    reg [31:0] quotient;

    //==========================================================================
    // Exponentiation LUT (ROM)
    //==========================================================================
    // Maps input range [-8, 0] to exp output in Q15 format
    // LUT[i] = exp(-8 + i*8/256) * 32768
    reg [15:0] exp_lut [0:EXP_LUT_SIZE-1];

    // Load LUT from generated file
    initial begin
        $readmemh("mem/exp_lut.hex", exp_lut);
    end

    //==========================================================================
    // Combinational Max-Find Tree
    //==========================================================================
    wire signed [31:0] max_level1 [0:L/2-1];
    wire signed [31:0] max_level2 [0:L/4-1];
    wire signed [31:0] max_level3;

    // Level 1: Compare pairs
    generate
        for (g = 0; g < L/2; g = g + 1) begin : max_tree_level1
            assign max_level1[g] = (scores[2*g] > scores[2*g+1]) ? scores[2*g] : scores[2*g+1];
        end
    endgenerate

    // Level 2: Compare pairs of level 1
    generate
        for (g = 0; g < L/4; g = g + 1) begin : max_tree_level2
            assign max_level2[g] = (max_level1[2*g] > max_level1[2*g+1]) ? max_level1[2*g] : max_level1[2*g+1];
        end
    endgenerate

    // Level 3: Final comparison
    assign max_level3 = (max_level2[0] > max_level2[1]) ? max_level2[0] : max_level2[1];

    //==========================================================================
    // Combinational Sum Tree
    //==========================================================================
    wire [31:0] sum_level1 [0:L/2-1];
    wire [31:0] sum_level2 [0:L/4-1];
    wire [31:0] sum_level3;

    // Level 1: Sum pairs
    generate
        for (g = 0; g < L/2; g = g + 1) begin : sum_tree_level1
            assign sum_level1[g] = exp_values[2*g] + exp_values[2*g+1];
        end
    endgenerate

    // Level 2: Sum pairs of level 1
    generate
        for (g = 0; g < L/4; g = g + 1) begin : sum_tree_level2
            assign sum_level2[g] = sum_level1[2*g] + sum_level1[2*g+1];
        end
    endgenerate

    // Level 3: Final sum
    assign sum_level3 = sum_level2[0] + sum_level2[1];

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
                if (start) state_next = FIND_MAX;
            end

            FIND_MAX: begin
                state_next = SHIFT;
            end

            SHIFT: begin
                state_next = COMPUTE_EXP;
            end

            COMPUTE_EXP: begin
                if (element_idx == L - 1) state_next = SUM_EXP;
            end

            SUM_EXP: begin
                state_next = DIVIDE;
            end

            DIVIDE: begin
                if (element_idx == L - 1) state_next = DONE;
            end

            DONE: begin
                state_next = IDLE;
            end
        endcase
    end

    //==========================================================================
    // Element Index Counter
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            element_idx <= 4'd0;
        end else begin
            case (state)
                IDLE, FIND_MAX, SHIFT: begin
                    element_idx <= 4'd0;
                end

                COMPUTE_EXP: begin
                    if (element_idx < L - 1) begin
                        element_idx <= element_idx + 1;
                    end else begin
                        element_idx <= 4'd0;
                    end
                end

                DIVIDE: begin
                    if (element_idx < L - 1) begin
                        element_idx <= element_idx + 1;
                    end else begin
                        element_idx <= 4'd0;
                    end
                end

                default: begin
                    element_idx <= 4'd0;
                end
            endcase
        end
    end

    //==========================================================================
    // Register Max Score
    //==========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_score <= 32'sd0;
        end else if (state == FIND_MAX) begin
            max_score <= max_level3;
        end
    end

    //==========================================================================
    // Compute Shifted Scores
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L; i = i + 1) begin
                shifted_scores[i] <= 32'sd0;
            end
        end else if (state == SHIFT) begin
            // Now max_score is stable from previous cycle
            for (i = 0; i < L; i = i + 1) begin
                shifted_scores[i] <= scores[i] - max_score;
            end
        end
    end

    //==========================================================================
    // Compute Exp Values via LUT
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L; i = i + 1) begin
                exp_values[i] <= 16'd0;
            end
            lut_addr <= 8'd0;
            shifted_val <= 32'sd0;
        end else if (state == COMPUTE_EXP) begin
            // Lookup exp value for current element
            shifted_val = shifted_scores[element_idx];

            // Map shifted_val to LUT index [0, 255]
            // Input range: [-8, 0] in Q0 format (integer)
            // LUT range: [0, 255]

            if (shifted_val <= -32'sd8) begin
                lut_addr = 8'd0;  // exp(-8) ≈ 0
            end else if (shifted_val >= 32'sd0) begin
                lut_addr = 8'd255;  // exp(0) = 1
            end else begin
                // Linear mapping: shifted_val in [-8, 0] → [0, 255]
                // lut_addr = (shifted_val + 8) * 32
                // Simplified: lut_addr = 255 + (shifted_val * 32)
                lut_addr = 8'd255 + (shifted_val[7:0] << 5);
            end

            exp_values[element_idx] <= exp_lut[lut_addr];
        end
    end

    //==========================================================================
    // Register Sum
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_exp <= 32'd0;
            sum_shift <= 5'd0;
        end else if (state == SUM_EXP) begin
            sum_exp <= sum_level3;

            // Find leading bit position for division approximation
            // This gives us the shift amount for normalization
            if (sum_level3[31:16] != 0) begin
                sum_shift <= 5'd16;  // Sum is large, shift right
            end else if (sum_level3[15:8] != 0) begin
                sum_shift <= 5'd8;
            end else begin
                sum_shift <= 5'd0;   // Sum is small, no shift
            end
        end
    end

    //==========================================================================
    // Division: weights[i] = exp_values[i] / sum_exp
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L; i = i + 1) begin
                weights[i] <= 16'd0;
            end
            numerator <= 32'd0;
            denominator <= 32'd0;
            quotient <= 32'd0;
        end else if (state == DIVIDE) begin
            // Approximate division using shifts
            // weights[i] = (exp_values[i] << 15) / sum_exp
            // Approximation: weights[i] = (exp_values[i] << (15 - sum_shift)) / (sum_exp >> sum_shift)

            numerator = exp_values[element_idx] << 15;
            denominator = sum_exp;

            // Simple division approximation
            // For better accuracy, we'd use Newton-Raphson, but this is simpler
            if (denominator != 0) begin
                quotient = numerator / denominator;
                weights[element_idx] <= (quotient > 32767) ? 16'd32767 : quotient[15:0];
            end else begin
                weights[element_idx] <= 16'd0;
            end
        end
    end

    //==========================================================================
    // Valid Output
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 1'b0;
        end else begin
            valid <= (state == DONE);
        end
    end

    //==========================================================================
    // Ready Signal
    //==========================================================================
    assign ready = (state == IDLE);

endmodule
