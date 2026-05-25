# Softmax Unit v2 - Synthesis Fixes
**Date:** 2026-04-03  
**Purpose:** Document all changes required to make softmax_unit_v2.v synthesizable

---

## Problem Summary

The original softmax_unit_v2.v contains **4 critical synthesis errors** that prevent it from being synthesized by Vivado:

1. Array input port `scores [0:L-1]` (line 44)
2. Array output port `weights [0:L-1]` (line 45)
3. Variable declaration in unnamed block (lines 238-239)
4. Variable declaration in unnamed block (lines 294-296)

---

## Fix 1: Array Ports → Flattened Buses

### Original Code (Non-Synthesizable)
```verilog
module softmax_unit_v2 #(
    parameter L = 8
)(
    input  wire [31:0]  scores [0:L-1],   // ❌ Array port
    output reg  [15:0]  weights [0:L-1]   // ❌ Array port
);
```

### Why This Fails

**Verilog-2005 Rule:** Module ports cannot be arrays. Only packed vectors are allowed.

**Hardware Reality:** There's no such thing as "passing an array" in hardware. What physically exists is:
- Multiple individual wires (one per element), OR
- A single wide bus that gets indexed

### Fixed Code (Synthesizable)
```verilog
module softmax_unit_v2 #(
    parameter L = 8
)(
    // Flattened buses (synthesizable)
    input  wire [L*32-1:0]  scores_flat,   // 256 bits for L=8
    output wire [L*16-1:0]  weights_flat   // 128 bits for L=8
);

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
    
    // Rest of module uses scores[] and weights[] as before
endmodule
```

### How This Works

**Input Path:**
```
scores_flat[255:0] → Unpack → scores[0] = bits [31:0]
                              scores[1] = bits [63:32]
                              scores[2] = bits [95:64]
                              ...
                              scores[7] = bits [255:224]
```

**Output Path:**
```
weights[0] → Pack → weights_flat[15:0]
weights[1] → Pack → weights_flat[31:16]
weights[2] → Pack → weights_flat[47:32]
...
weights[7] → Pack → weights_flat[127:112]
```

**Bit Slicing Syntax:**
- `[g*32 +: 32]` means "starting at bit g*32, take 32 bits upward"
- Equivalent to `[g*32+31 : g*32]` but more readable
- This is called "indexed part-select" (Verilog-2001 feature, widely supported)

---

## Fix 2: Block-Scoped Variables → Module-Scoped Variables

### Original Code (Non-Synthesizable)

**Location 1: Lines 238-239**
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // ...
    end else if (state == COMPUTE_EXP) begin
        reg [7:0] lut_addr;              // ❌ Illegal in Verilog-2005
        reg signed [31:0] shifted_val;   // ❌ Illegal in Verilog-2005
        
        shifted_val = shifted_scores[element_idx];
        // ...
    end
end
```

**Location 2: Lines 294-296**
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // ...
    end else if (state == DIVIDE) begin
        reg [31:0] numerator;    // ❌ Illegal in Verilog-2005
        reg [31:0] denominator;  // ❌ Illegal in Verilog-2005
        reg [31:0] quotient;     // ❌ Illegal in Verilog-2005
        
        numerator = exp_values[element_idx] << 15;
        // ...
    end
end
```

### Why This Fails

**Verilog-2005 Rule:** Variable declarations are only allowed at module scope, not inside procedural blocks.

**SystemVerilog Extension:** SystemVerilog (IEEE 1800) allows block-scoped variables with automatic lifetime, but this is NOT part of Verilog-2005.

**Hardware Reality:** All registers exist physically throughout the module's lifetime. There's no concept of "creating a register when entering a block" in hardware.

### Fixed Code (Synthesizable)

**Move all declarations to module scope:**
```verilog
module softmax_unit_v2 #(...) (...);
    
    // ... existing declarations ...
    
    // Variables for COMPUTE_EXP state
    reg [7:0] lut_addr;
    reg signed [31:0] shifted_val;
    
    // Variables for DIVIDE state
    reg [31:0] numerator;
    reg [31:0] denominator;
    reg [31:0] quotient;
    
    // Now use them in always blocks
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lut_addr <= 8'd0;
            shifted_val <= 32'sd0;
        end else if (state == COMPUTE_EXP) begin
            shifted_val = shifted_scores[element_idx];
            // ... rest of logic
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            numerator <= 32'd0;
            denominator <= 32'd0;
            quotient <= 32'd0;
        end else if (state == DIVIDE) begin
            numerator = exp_values[element_idx] << 15;
            // ... rest of logic
        end
    end
endmodule
```

### Important Note: Blocking vs. Non-Blocking

In the original code, these variables used **blocking assignments** (`=`):
```verilog
shifted_val = shifted_scores[element_idx];  // Blocking
numerator = exp_values[element_idx] << 15;  // Blocking
```

This is correct for **combinational logic** within a clocked always block. The pattern is:
1. Read inputs (blocking)
2. Compute intermediate values (blocking)
3. Write outputs (non-blocking `<=`)

We preserve this pattern in the fixed code.

---

## Fix 3: Output Port Type Change

### Original Code
```verilog
output reg  [15:0]  weights [0:L-1]
```

### Fixed Code
```verilog
output wire [L*16-1:0]  weights_flat
```

**Why `wire` instead of `reg`?**

The output is now driven by a continuous assignment (`assign weights_flat[...] = weights[...]`), not by a procedural block. Continuous assignments require `wire` type.

The internal `weights` array remains `reg` because it's assigned in an `always` block.

---

## Complete Fixed Module Interface

### Before (Non-Synthesizable)
```verilog
module softmax_unit_v2 #(
    parameter L = 8,
    parameter EXP_LUT_SIZE = 256
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [31:0]  scores [0:L-1],   // ❌
    output reg  [15:0]  weights [0:L-1],  // ❌
    output reg          valid,
    output wire         ready
);
```

### After (Synthesizable)
```verilog
module softmax_unit_v2 #(
    parameter L = 8,
    parameter EXP_LUT_SIZE = 256
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [L*32-1:0]  scores_flat,   // ✅ Flattened bus
    output wire [L*16-1:0]  weights_flat,  // ✅ Flattened bus
    output reg          valid,
    output wire         ready
);
```

---

## Impact on Parent Modules

### streaming_attention_v3.v

The parent module must also be updated to use flattened buses when instantiating softmax_unit_v2.

**Before:**
```verilog
softmax_unit_v2 #(.L(L)) softmax (
    .clk(clk),
    .rst_n(rst_n),
    .start(softmax_start),
    .scores(attention_scores),  // Array
    .weights(attention_weights), // Array
    .valid(softmax_valid),
    .ready(softmax_ready)
);
```

**After:**
```verilog
// Flatten arrays for softmax interface
wire [L*32-1:0] attention_scores_flat;
wire [L*16-1:0] attention_weights_flat;

genvar g;
generate
    for (g = 0; g < L; g = g + 1) begin : flatten_softmax_io
        assign attention_scores_flat[g*32 +: 32] = attention_scores[g];
        assign attention_weights[g] = attention_weights_flat[g*16 +: 16];
    end
endgenerate

softmax_unit_v2 #(.L(L)) softmax (
    .clk(clk),
    .rst_n(rst_n),
    .start(softmax_start),
    .scores_flat(attention_scores_flat),   // Flattened
    .weights_flat(attention_weights_flat), // Flattened
    .valid(softmax_valid),
    .ready(softmax_ready)
);
```

---

## Verification Strategy

After applying these fixes, we must verify that:

1. **Syntax is correct:** Run lint check
   ```bash
   verilator --lint-only -Wall rtl/softmax/softmax_unit_v2.v
   ```

2. **Behavior is unchanged:** Run existing testbench
   ```bash
   cd tb/unit
   xvlog ../rtl/softmax/softmax_unit_v2.v tb_softmax_unit.v
   xelab tb_softmax_unit
   xsim tb_softmax_unit -R
   ```

3. **Synthesis succeeds:** Run Vivado synthesis
   ```bash
   vivado -mode batch -source synth_softmax_v2.tcl
   ```

4. **Functionality matches:** Compare simulation results before/after fix

---

## Summary of Changes

| Issue | Location | Fix |
|-------|----------|-----|
| Array input port | Line 44 | Convert to flattened bus + unpack logic |
| Array output port | Line 45 | Convert to flattened bus + pack logic |
| Block-scoped variables | Lines 238-239 | Move to module scope |
| Block-scoped variables | Lines 294-296 | Move to module scope |

**Total lines changed:** ~30 lines  
**Functional changes:** None (pure refactoring for synthesizability)  
**Performance impact:** None (same hardware generated)

---

## Next Steps

1. Apply fixes to softmax_unit_v2.v
2. Update streaming_attention_v3.v to use new interface
3. Run testbench to verify behavior unchanged
4. Run synthesis to verify it now succeeds
5. Analyze synthesis results (resource utilization, timing)
6. Document findings in VLSI_ARCHITECTURE_REVIEW.md

---

**Ready to implement fixes.**
