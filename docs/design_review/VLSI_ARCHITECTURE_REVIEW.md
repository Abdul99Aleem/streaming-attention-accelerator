# VLSI Architecture Review - Streaming Attention Accelerator
**Date:** 2026-04-03  
**Reviewer Role:** VLSI Design Architect  
**Purpose:** Comprehensive architecture review with synthesis analysis

---

## Executive Summary

**Current Status:** Project does not synthesize successfully  
**Root Cause:** Fundamental Verilog coding violations in softmax_unit_v2.v  
**Impact:** All modules depending on softmax_unit_v2 (v3, v4) cannot be synthesized  
**Severity:** CRITICAL - Blocks all hardware validation

**Key Finding:** The project has excellent architectural documentation and design thinking, but the RTL implementation violates basic Verilog synthesis rules. This is a teaching moment about the gap between algorithmic design and synthesizable hardware.

---

## Part 1: Synthesis Error Analysis

### Error 1: Variable Declarations in Unnamed Blocks

**Location:** `softmax_unit_v2.v:238, 294`

**Error Message:**
```
ERROR: [Synth 8-10632] declarations are not allowed in an unnamed block
```

**Code at Line 238:**
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // ...
    end else if (state == COMPUTE_EXP) begin
        // Lookup exp value for current element
        reg [7:0] lut_addr;              // ← ILLEGAL
        reg signed [31:0] shifted_val;   // ← ILLEGAL
        
        shifted_val = shifted_scores[element_idx];
        // ...
    end
end
```

**Why This Fails:**

In Verilog (IEEE 1364-2005), variable declarations are NOT allowed inside procedural blocks (`always`, `initial`). This is a SystemVerilog (IEEE 1800) feature.

**Verilog vs. SystemVerilog:**

| Feature | Verilog-2005 | SystemVerilog |
|---------|--------------|---------------|
| Declare variables in always block | ❌ No | ✅ Yes |
| Array ports | Unpacked only | Packed/Unpacked |
| Automatic variables | No | Yes |

**Why This Matters for Synthesis:**

Synthesis tools (Vivado, Quartus, Design Compiler) primarily target Verilog-2005 for maximum compatibility. While they support some SystemVerilog features, mixing them incorrectly causes synthesis failures.

**The Correct Approach:**

All variables must be declared at module scope:

```verilog
module softmax_unit_v2 #(...) (...);
    // Module-level declarations
    reg [7:0] lut_addr;
    reg signed [31:0] shifted_val;
    
    // Now use them in always blocks
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lut_addr <= 8'd0;
            shifted_val <= 32'd0;
        end else if (state == COMPUTE_EXP) begin
            shifted_val = shifted_scores[element_idx];
            // ...
        end
    end
endmodule
```

**Architectural Implication:**

This error reveals a misunderstanding of hardware vs. software thinking:
- **Software:** Variables are scoped to blocks, created on stack
- **Hardware:** All registers/wires exist physically, declared once, used everywhere

---

### Error 2: Array Ports

**Location:** `softmax_unit_v2.v:44-45`

**Error Message:**
```
ERROR: [Synth 8-9917] port 'scores' must not be declared to be an array
ERROR: [Synth 8-9917] port 'weights' must not be declared to be an array
```

**Code:**
```verilog
module softmax_unit_v2 #(
    parameter L = 8
)(
    input  wire [31:0]  scores [0:L-1],   // ← ILLEGAL in Verilog
    output reg  [15:0]  weights [0:L-1]   // ← ILLEGAL in Verilog
);
```

**Why This Fails:**

Verilog-2005 does NOT support array ports directly. You cannot pass an array through a module port.

**The Fundamental Problem:**

In hardware, there's no such thing as "passing an array". What actually exists is:
- **Option A:** Multiple individual wires (one per array element)
- **Option B:** A single wide bus that you index into

**Correct Approaches:**

**Approach 1: Flattened Bus (Recommended for Synthesis)**
```verilog
module softmax_unit_v2 #(
    parameter L = 8
)(
    input  wire [L*32-1:0]  scores_flat,   // 256 bits for L=8
    output reg  [L*16-1:0]  weights_flat   // 128 bits for L=8
);

    // Internal arrays for easier indexing
    wire [31:0] scores [0:L-1];
    reg  [15:0] weights [0:L-1];
    
    // Unpack input
    genvar g;
    generate
        for (g = 0; g < L; g = g + 1) begin : unpack_scores
            assign scores[g] = scores_flat[g*32 +: 32];
        end
    endgenerate
    
    // Pack output
    generate
        for (g = 0; g < L; g = g + 1) begin : pack_weights
            assign weights_flat[g*16 +: 16] = weights[g];
        end
    endgenerate
    
    // Now use scores[] and weights[] internally as before
endmodule
```

**Approach 2: Memory Interface (Better for Large Arrays)**
```verilog
module softmax_unit_v2 #(
    parameter L = 8
)(
    // Memory-mapped interface
    output reg  [3:0]   score_addr,    // Address to read
    output reg          score_rd_en,   // Read enable
    input  wire [31:0]  score_data,    // Data from memory
    
    output reg  [3:0]   weight_addr,   // Address to write
    output reg          weight_wr_en,  // Write enable
    output reg  [15:0]  weight_data    // Data to memory
);
```

**Which Approach to Use?**

| Approach | Best For | Pros | Cons |
|----------|----------|------|------|
| Flattened Bus | Small arrays (L ≤ 16) | Simple, fast | Wide ports, routing congestion |
| Memory Interface | Large arrays (L > 16) | Scalable, clean | Sequential access, slower |

**For This Project (L=8):** Flattened bus is appropriate.

---

## Part 2: VLSI Architecture Analysis

### 2.1 Design Hierarchy Review

**Current Hierarchy:**
```
streaming_attention_v4
├── dot_product_engine (16 instances)
│   └── mac_int8 (64 instances each)
├── softmax_unit_v2
│   └── exp_lut (ROM)
└── control FSM
```

**Total MAC Units:** 16 × 64 = 1024 MAC units

**VLSI Architect's Perspective:**

This is an **extremely aggressive design** for a Zynq-7020:

| Resource | Zynq-7020 Available | v4 Estimated Usage | Utilization |
|----------|---------------------|-------------------|-------------|
| DSP48E1 | 220 | 1024 MACs | **465%** ❌ |
| LUTs | 53,200 | ~40,000 | 75% |
| FFs | 106,400 | ~30,000 | 28% |
| BRAM | 140 (4.9 Mb) | ~10 | 7% |

**Critical Issue:** The design requires 1024 MAC operations, but the Zynq-7020 only has 220 DSP slices.

**What This Means:**

1. **DSP Mapping:** Each DSP48E1 can perform one 25×18 multiply-accumulate per cycle
2. **Our MACs:** INT8 × INT8 = INT16, accumulate to INT32
3. **Packing:** We can fit 2-3 INT8 MACs per DSP48E1 with clever packing
4. **Best Case:** 220 DSPs × 3 MACs = 660 MACs maximum
5. **Our Design:** 1024 MACs required

**Conclusion:** v4 design is **not implementable** on Zynq-7020 as specified.

---

### 2.2 Resource Utilization Strategy

**The VLSI Trade-off Triangle:**

```
        Performance
           /\
          /  \
         /    \
        /      \
       /________\
    Area      Power
```

**Current Design Philosophy:** Maximize performance (parallelism) without considering area constraints.

**What a VLSI Architect Would Do:**

1. **Start with constraints:**
   - Target device: Zynq-7020 (220 DSPs)
   - Target frequency: 100 MHz
   - Power budget: ~2W for PL

2. **Work backwards:**
   - Available DSPs: 220
   - Reserve 20% for other logic: 176 usable DSPs
   - INT8 MAC packing: 3 MACs per DSP
   - **Maximum parallelism: 176 × 3 = 528 MACs**

3. **Design to fit:**
   - Tile width: 16 (requires 16 × 64 = 1024 MACs) ❌
   - Tile width: 8 (requires 8 × 64 = 512 MACs) ✅
   - **Recommendation: TILE_WIDTH = 8**

---

### 2.3 Timing Analysis (Predicted)

**Critical Path Analysis for v3 (Current Working Design):**

**Path 1: MAC Array → Accumulator**
```
Input Register → MAC Multiply → MAC Add → Accumulator → Output Register
    0.5 ns         2.5 ns        1.5 ns      1.0 ns        0.5 ns
                        Total: 6.0 ns
```

**Path 2: Softmax Max-Find Tree**
```
Input → Compare L1 → Compare L2 → Compare L3 → Register
 0.5ns     1.5ns        1.5ns        1.5ns       0.5ns
                    Total: 5.5 ns
```

**Path 3: Softmax Division**
```
Exp LUT → Divider → Normalize → Output
  1.0ns     4.0ns      1.0ns      0.5ns
              Total: 6.5 ns
```

**Critical Path:** Softmax division at 6.5 ns

**Maximum Frequency:** 1 / 6.5ns = 153 MHz

**Target Frequency:** 100 MHz

**Timing Margin:** (10ns - 6.5ns) / 10ns = 35% slack ✅

**Conclusion:** Design should meet timing at 100 MHz with comfortable margin.

---

## Part 3: Architectural Recommendations

### 3.1 Immediate Fixes (Critical)

**Priority 1: Fix Verilog Syntax Errors**

1. Move all variable declarations to module scope
2. Convert array ports to flattened buses
3. Re-synthesize and verify

**Priority 2: Validate v3 Before Proceeding to v4**

1. Fix softmax_unit_v2.v
2. Synthesize streaming_attention_v3
3. Analyze actual resource utilization
4. Measure actual timing
5. Compare with predictions

**Priority 3: Redesign v4 with Resource Constraints**

1. Reduce TILE_WIDTH from 16 to 8
2. Re-calculate performance predictions
3. Ensure DSP count < 220

---

### 3.2 Long-Term Architecture Improvements

**Improvement 1: Configurable Parallelism**

Instead of fixed TILE_WIDTH, make it a synthesis-time parameter:

```verilog
module streaming_attention_v4 #(
    parameter L = 8,
    parameter D = 64,
    parameter TILE_WIDTH = 8,  // Configurable: 1, 2, 4, 8, 16
    parameter MAX_DSP = 220    // Device constraint
)(
    // ...
);

    // Compile-time assertion
    initial begin
        if (TILE_WIDTH * D > MAX_DSP * 3) begin
            $error("TILE_WIDTH too large for target device");
            $finish;
        end
    end
endmodule
```

**Improvement 2: Memory Bandwidth Analysis**

Current design assumes infinite memory bandwidth. Reality:

| Memory Type | Bandwidth @ 100MHz | Latency |
|-------------|-------------------|---------|
| BRAM | 3.2 GB/s per port | 2 cycles |
| DDR3 (PS) | 1.6 GB/s | 50-100 cycles |
| AXI HP Port | 1.2 GB/s | 10-20 cycles |

**Required Bandwidth for v4:**
- Read Q: 8 × 64 × 1 byte = 512 bytes per attention
- Read K: 8 × 64 × 1 byte = 512 bytes per attention
- Read V: 8 × 64 × 1 byte = 512 bytes per attention
- Write O: 8 × 64 × 1 byte = 512 bytes per attention
- **Total: 2048 bytes per attention**

At 100 MHz with 1736 cycles per attention:
- Time per attention: 17.36 μs
- Bandwidth required: 2048 bytes / 17.36 μs = **118 MB/s**

**Conclusion:** Memory bandwidth is NOT the bottleneck. BRAM is sufficient.

**Improvement 3: Power Estimation**

**DSP Power:**
- DSP48E1 @ 100 MHz: ~5 mW per slice
- 176 DSPs: 176 × 5 mW = 880 mW

**BRAM Power:**
- BRAM @ 100 MHz: ~2 mW per block
- 10 BRAMs: 10 × 2 mW = 20 mW

**Logic Power:**
- LUTs/FFs: ~0.5 W (estimated)

**Total PL Power:** ~1.4 W (within 2W budget) ✅

---

## Part 4: Verification Strategy

### 4.1 What Went Wrong with Current Verification

**Claimed:** "v3 is tested and working"

**Reality:** 
- Testbench exists and runs in simulation
- Testbench tests v3 module
- **But v3 doesn't synthesize**
- Simulation uses behavioral Verilog (more permissive)
- Synthesis uses stricter subset

**The Gap:**

```
Behavioral Simulation ≠ Synthesizable RTL
```

**Why Simulation Passed:**
- Simulators (XSim, ModelSim) support full Verilog + SystemVerilog
- They allow array ports, block-scoped variables
- They don't check synthesizability

**Why Synthesis Failed:**
- Synthesis tools target Verilog-2005 subset
- They reject non-synthesizable constructs
- They enforce hardware realizability

---

### 4.2 Proper Verification Flow

**The Correct Flow:**

```
Step 1: Write RTL
Step 2: Lint check (Verilator --lint-only)
Step 3: Behavioral simulation
Step 4: Synthesis
Step 5: Post-synthesis simulation
Step 6: Place & Route
Step 7: Post-implementation simulation
Step 8: Hardware test
```

**What We Did:**
```
Step 1: Write RTL ✅
Step 2: Lint check ❌ SKIPPED
Step 3: Behavioral simulation ✅
Step 4: Synthesis ❌ FAILED
```

**What We Should Have Done:**

Run lint check immediately after writing RTL:
```bash
verilator --lint-only -Wall \
    rtl/softmax/softmax_unit_v2.v \
    --top-module softmax_unit_v2
```

This would have caught:
- Array port issues
- Block-scoped variable declarations
- Non-synthesizable constructs

**Lesson:** Simulation passing ≠ Design working

---

## Part 5: Action Plan

### Phase 1: Fix Synthesis Errors (1-2 hours)

**Task 1.1:** Fix softmax_unit_v2.v
- Move variable declarations to module scope
- Convert array ports to flattened buses
- Add pack/unpack logic

**Task 1.2:** Verify fix
- Run lint check
- Run behavioral simulation
- Confirm testbench still passes

**Task 1.3:** Synthesize v3
- Run Vivado synthesis
- Check for errors
- Generate resource utilization report

---

### Phase 2: Analyze v3 Synthesis Results (1 hour)

**Task 2.1:** Resource Utilization
- Compare predicted vs. actual
- Identify bottlenecks
- Document findings

**Task 2.2:** Timing Analysis
- Check critical paths
- Verify 100 MHz target met
- Document slack

**Task 2.3:** Update Documentation
- Update analysis docs with measured data
- Explain any discrepancies
- Learn from differences

---

### Phase 3: Redesign v4 (2-3 hours)

**Task 3.1:** Adjust TILE_WIDTH
- Calculate maximum feasible parallelism
- Set TILE_WIDTH = 8 (not 16)
- Update performance predictions

**Task 3.2:** Implement v4 with Constraints
- Write synthesizable RTL
- Run lint check before simulation
- Verify with testbench

**Task 3.3:** Synthesize v4
- Generate resource report
- Compare with v3
- Validate speedup claims

---

## Part 6: Learning Outcomes

### What This Review Teaches

**Lesson 1: Simulation ≠ Synthesis**

Just because your testbench passes doesn't mean your design works. You must:
1. Lint check for synthesizability
2. Synthesize early and often
3. Verify post-synthesis behavior

**Lesson 2: Constraints Drive Design**

VLSI design is about working within constraints:
- Area (LUTs, FFs, DSPs, BRAM)
- Timing (critical path, clock frequency)
- Power (dynamic + static)
- I/O bandwidth

You can't just maximize parallelism and hope it fits.

**Lesson 3: Hardware ≠ Software**

Software thinking:
- Variables are scoped to blocks
- Arrays are first-class objects
- Memory is "infinite"

Hardware thinking:
- All registers exist physically
- Arrays are collections of wires
- Every resource has a cost

**Lesson 4: Verification is Multi-Level**

You need verification at every stage:
1. Lint (syntax, synthesizability)
2. Behavioral sim (functionality)
3. Post-synthesis sim (with real delays)
4. Post-implementation sim (with routing delays)
5. Hardware test (real world)

Skipping any level risks late-stage failures.

---

## Conclusion

**Current State:**
- Excellent architectural thinking and documentation
- Fundamental RTL coding errors prevent synthesis
- Performance claims are unvalidated

**Path Forward:**
1. Fix Verilog syntax errors (immediate)
2. Synthesize and analyze v3 (validate baseline)
3. Redesign v4 with resource constraints (realistic)
4. Follow proper verification flow (rigorous)

**Estimated Time to Complete:**
- Fix and validate v3: 3-4 hours
- Redesign and validate v4: 4-5 hours
- Full documentation: 2-3 hours
- **Total: 10-12 hours of focused work**

**This is NOT resume noise.** This is real learning about the gap between algorithmic design and hardware implementation.

---

**Next Step:** Fix softmax_unit_v2.v and re-synthesize v3.

Shall we proceed?
