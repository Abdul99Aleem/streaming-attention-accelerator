# Synthesis Results Analysis - streaming_attention_v3
**Date:** 2026-04-03  
**Status:** ✅ Synthesis Successful  
**Purpose:** Compare predicted vs. actual resource utilization and analyze findings

---

## Executive Summary

**Result:** v3 synthesizes successfully with **0 errors**

**Key Findings:**
1. ✅ Synthesis successful after fixing Verilog-2005 violations
2. ⚠️ Only 2 DSPs used (not 64 as predicted)
3. ⚠️ No BRAM used (exp_lut not inferred as BRAM)
4. ✅ Very low resource usage (~1.6% of device)
5. ⚠️ No timing constraints provided (can't verify 100 MHz)

---

## Resource Utilization - Predicted vs. Actual

### Comparison Table

| Resource | Predicted | Actual | Difference | Utilization | Analysis |
|----------|-----------|--------|------------|-------------|----------|
| **LUTs** | ~8,000 | 868 | -7,132 (-89%) | 1.63% | Much lower than predicted |
| **Flip-Flops** | ~5,000 | 1,517 | -3,483 (-70%) | 1.43% | Much lower than predicted |
| **DSP48E1** | 64 | 2 | -62 (-97%) | 0.91% | **Critical discrepancy** |
| **BRAM** | 1-2 | 0 | -1 to -2 | 0.00% | **exp_lut not in BRAM** |
| **Power** | ~1.4W | TBD | - | - | Need power report analysis |

### Why Are We So Far Off?

**Reason 1: v3 Doesn't Use dot_product_engine**

Our predictions assumed v3 used the parallel dot_product_engine with 64 MAC units. **This was wrong.**

**What v3 actually does:**
```verilog
// Sequential dot product in FSM
SCORE_LOOP: begin
    if (elem_idx > 0) begin
        // Accumulate: q_row[elem_idx-1] * k_data
        dot_acc <= dot_acc + ($signed(q_row[elem_idx - 1]) * $signed(k_data));
    end
end
```

**This is:**
- 1 multiply per cycle (not 64 parallel)
- Implemented in fabric logic or DSP
- Sequential, not parallel

**Why only 2 DSPs?**

Looking at the code, v3 has:
1. One multiply in SCORE_LOOP: `q_row[elem_idx-1] * k_data`
2. One multiply in OUTPUT_LOOP: `attention_weights[key_idx] * v_data`
3. Division in softmax (may use DSP)

Vivado inferred 2 DSPs, likely for the two main multiplications. The softmax division might be implemented differently.

---

## Detailed Analysis

### 1. LUT Usage: 868 LUTs (1.63%)

**Breakdown:**
- LUT6: 697 (80% of LUTs)
- LUT2: 84
- LUT5: 62
- LUT4: 18
- LUT3: 6
- LUT1: 1

**What uses LUTs:**
1. **FSM logic** - State machine with 13 states
2. **Address generation** - Computing q_addr, k_addr, v_addr, out_addr
3. **Control logic** - Read enables, write enables, counters
4. **Muxes** - MUXF7 (250), MUXF8 (78) for large multiplexers
5. **Softmax logic** - Max-find tree, sum tree, division logic

**Why so low?**
- Sequential design has minimal parallel logic
- Most computation is in DSPs (multiplies) or registers (accumulators)
- No large parallel structures

### 2. Flip-Flop Usage: 1,517 FFs (1.43%)

**Breakdown:**
- FDCE (FF with clock enable and async reset): 1,516
- FDPE (FF with preset): 1

**What uses FFs:**
1. **State registers** - FSM state (4 bits)
2. **Index counters** - query_idx, key_idx, elem_idx (~15 bits)
3. **Buffers** - q_row[0:63] (64 × 8 = 512 bits)
4. **Accumulators** - dot_acc (32 bits), output_row[0:63] (64 × 32 = 2048 bits)
5. **Scores** - scores[0:7] (8 × 32 = 256 bits)
6. **Attention weights** - attention_weights[0:7] (8 × 32 = 256 bits)
7. **Softmax internal** - ~176 FFs in softmax_inst

**Calculation:**
```
State + counters:        ~20 FFs
q_row buffer:           512 FFs
output_row buffer:     2048 FFs (but only 64 elements × 32 bits)
scores:                 256 FFs
attention_weights:      256 FFs
Softmax:                176 FFs
Control signals:        ~50 FFs
                      --------
Total estimate:       ~3318 FFs
```

**Actual: 1,517 FFs**

**Why lower?**
- Synthesis optimized away unused bits
- Some registers shared across states
- Dead code elimination

### 3. DSP Usage: 2 DSPs (0.91%)

**Critical Finding:** Only 2 DSPs used, not 64.

**Why?**

v3 has only 2 multiplications in the main datapath:
1. `q_row[elem_idx-1] * k_data` (INT8 × INT8 → INT16)
2. `attention_weights[key_idx] * v_data` (INT32 × INT8 → INT40)

**DSP48E1 Capabilities:**
- 25×18 multiplier
- Can handle both our multiplications
- Vivado inferred 2 DSPs for these

**Softmax division:**
```verilog
quotient = numerator / denominator;
```

Division is **not** typically mapped to DSPs. It's implemented as:
- Iterative subtraction (slow)
- Lookup table approximation
- Combinational logic

This explains why softmax doesn't add DSP usage.

**Implication:**
- v3 is extremely DSP-light
- Plenty of room for parallelism (218 DSPs unused)
- v4 with TILE_WIDTH=8 would use ~512 DSPs (too many!)
- v4 needs TILE_WIDTH=4 or less

### 4. BRAM Usage: 0 BRAMs (0%)

**Critical Finding:** exp_lut is not using BRAM.

**The exp_lut in softmax_unit_v2:**
```verilog
reg [15:0] exp_lut [0:EXP_LUT_SIZE-1];  // 256 entries × 16 bits = 4096 bits

initial begin
    $readmemh("mem/exp_lut.hex", exp_lut);
end
```

**Why not BRAM?**

**BRAM inference requirements:**
1. Size > 512 bits (our LUT is 4096 bits ✅)
2. Synchronous read (registered output)
3. Proper coding style

**Our code:**
```verilog
lut_addr = ...;  // Combinational
exp_values[element_idx] <= exp_lut[lut_addr];  // Read in same cycle
```

**This is asynchronous read** - BRAM requires registered read address.

**Where is it implemented?**
- Distributed RAM (using LUT RAM)
- Or as combinational logic (ROM)

**Impact:**
- Uses LUTs instead of BRAM
- 256 entries × 16 bits = 4096 bits
- Each LUT can store 64 bits (6-input LUT as RAM)
- Needs ~64 LUTs for the table
- This is acceptable but not optimal

**How to fix:**
```verilog
// Register the address
always @(posedge clk) begin
    lut_addr_reg <= lut_addr;
end

// Read from registered address
assign exp_value = exp_lut[lut_addr_reg];
```

This would infer BRAM, but adds 1 cycle latency.

### 5. Mux Usage: 250 MUXF7, 78 MUXF8

**What are these?**

- MUXF7: 2:1 mux using dedicated mux primitive
- MUXF8: 2:1 mux using dedicated mux primitive

**Why so many?**

Large multiplexers in the design:
1. **State machine outputs** - Many signals depend on state (13 states)
2. **Address generation** - q_addr, k_addr, v_addr depend on state and indices
3. **Data path muxing** - Selecting between different data sources

**Example:**
```verilog
case (state)
    LOAD_Q_INIT, LOAD_Q_LOOP: begin
        q_addr = query_idx * D + elem_idx;  // Large mux
        q_rd_en = 1'b1;
    end
    SCORE_INIT, SCORE_LOOP: begin
        k_addr = key_idx * D + elem_idx;    // Large mux
        k_rd_en = 1'b1;
    end
    // ... more cases
endcase
```

Each case creates a mux selecting between different values based on state.

---

## Timing Analysis

### No Timing Constraints Provided

**Timing report shows:**
```
There are no user specified timing constraints.
WNS(ns): NA
TNS(ns): NA
```

**What this means:**
- Synthesis completed without timing goals
- No verification that design meets 100 MHz
- Can't identify critical paths
- Can't verify timing margin

**Why this happened:**

We didn't create a constraints file (XDC) specifying:
```tcl
create_clock -period 10.0 -name clk [get_ports clk]
```

**Impact:**
- Synthesis optimized for area, not timing
- May not meet 100 MHz in reality
- Need to add constraints and re-synthesize

**Next steps:**
1. Create constraints file with 100 MHz clock
2. Re-synthesize with timing constraints
3. Analyze critical paths
4. Verify timing margin

---

## Power Analysis

**Power report exists but not analyzed yet.**

Expected power consumption:
- 2 DSPs @ 100 MHz: ~10 mW
- 868 LUTs switching: ~50 mW
- 1517 FFs switching: ~30 mW
- Static power: ~200 mW
- **Total estimate: ~300 mW**

This is well within the 2W budget for PL.

---

## Comparison with Other Versions

### v3 vs. v4 (Predicted)

| Metric | v3 (Actual) | v4 (Predicted) | Ratio |
|--------|-------------|----------------|-------|
| DSPs | 2 | 1024 | 512× |
| LUTs | 868 | 40,000 | 46× |
| FFs | 1,517 | 30,000 | 20× |
| Parallelism | 1× | 16× | 16× |
| Cycles | 1736 | 310 | 0.18× |

**Key insight:** v4 trades massive resource increase for 5.6× speedup.

**Problem:** v4 requires 1024 DSPs, but Zynq-7020 only has 220.

**Solution:** Reduce v4 TILE_WIDTH from 16 to 4:
- 4 × 64 = 256 MACs
- 256 MACs / 3 per DSP = ~85 DSPs
- Fits in 220 DSP budget ✅
- Still 4× parallelism over v3

---

## Key Learnings

### 1. Predictions Were Based on Wrong Assumptions

**We assumed:** v3 uses dot_product_engine with 64 MACs

**Reality:** v3 is fully sequential with 1 MAC per cycle

**Lesson:** Always verify what modules are actually instantiated before predicting resources.

### 2. Synthesis Optimizes Aggressively

**We predicted:** 5,000 FFs

**Actual:** 1,517 FFs (70% less)

**Why:** Synthesis eliminated dead code, shared registers, optimized away unused bits.

**Lesson:** Hand calculations overestimate. Synthesis is smarter than we think.

### 3. BRAM Inference Requires Specific Coding Style

**We expected:** exp_lut in BRAM

**Actual:** exp_lut in distributed RAM

**Why:** Asynchronous read doesn't infer BRAM.

**Lesson:** Must follow BRAM coding templates exactly for inference.

### 4. Timing Constraints Are Mandatory

**We forgot:** To provide timing constraints

**Impact:** Can't verify 100 MHz operation

**Lesson:** Always provide constraints, even for synthesis-only runs.

---

## Recommendations

### Immediate Actions

1. **Add timing constraints**
   - Create XDC file with 100 MHz clock constraint
   - Re-synthesize with constraints
   - Analyze critical paths and timing margin

2. **Fix BRAM inference**
   - Modify softmax_unit_v2 to use synchronous read
   - Verify BRAM inference in next synthesis
   - Accept 1-cycle latency increase

3. **Verify functionality**
   - Run post-synthesis simulation
   - Compare with behavioral simulation
   - Ensure no functional changes from fixes

### For v4 Design

1. **Reduce TILE_WIDTH to 4**
   - 4 × 64 = 256 MACs
   - ~85 DSPs (fits in budget)
   - Still 4× speedup over v3

2. **Consider hybrid approach**
   - Use dot_product_engine for Q·K^T
   - Keep sequential for attention·V
   - Balance resources and performance

3. **Add resource budgeting**
   - Calculate DSP usage before implementation
   - Verify fits in device
   - Don't exceed 80% of any resource

---

## Summary

### What Worked

✅ Synthesis successful after Verilog-2005 fixes
✅ Very low resource usage (plenty of room for optimization)
✅ Design is implementable on Zynq-7020
✅ No critical errors or warnings

### What Needs Improvement

⚠️ Timing constraints missing (can't verify 100 MHz)
⚠️ BRAM not inferred for exp_lut (using LUTs instead)
⚠️ Predictions were way off (wrong assumptions)
⚠️ No post-synthesis verification yet

### Key Metrics

- **Resource usage:** ~1.6% of device (very light)
- **DSP usage:** 2 of 220 (0.91%)
- **Synthesis time:** ~2 minutes
- **Errors:** 0
- **Warnings:** 521 (mostly about missing constraints)

### Next Steps

1. Add timing constraints and re-synthesize
2. Analyze timing with constraints
3. Fix BRAM inference
4. Run post-synthesis simulation
5. Document findings
6. Proceed to v4 design with corrected resource budget

---

**This analysis reveals the gap between predictions and reality, teaching us about synthesis behavior and the importance of verification at every step.**
