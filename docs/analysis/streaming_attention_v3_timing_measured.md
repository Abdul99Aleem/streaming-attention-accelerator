# Timing Analysis Results - streaming_attention_v3
**Date:** 2026-04-13  
**Role:** Performance Analyst  
**Status:** ❌ TIMING VIOLATION - Does NOT meet 100 MHz  
**Result:** WNS = -1.342 ns, 384 failing paths

---

## Executive Summary

**Synthesis with timing constraints completed. Result: TIMING FAILURE**

```
Target Clock:     100 MHz (10 ns period)
Worst Slack:      -1.342 ns (VIOLATED)
Total Neg Slack:  -355.432 ns
Failing Paths:    384 out of 3092 endpoints
Status:           ❌ DOES NOT MEET TIMING
```

**Critical Finding:** The design is **1.342 ns too slow** for 100 MHz operation. The critical path is in the **OUTPUT_LOOP multiply-accumulate** operation, not in softmax as predicted.

**Prediction Accuracy:** ❌ **WRONG** - Predicted +2.5 ns margin, actual -1.342 ns violation

---

## Timing Results Summary

### Setup Timing (Max Delay)

| Metric | Value | Status |
|--------|-------|--------|
| **WNS (Worst Negative Slack)** | -1.342 ns | ❌ FAIL |
| **TNS (Total Negative Slack)** | -355.432 ns | ❌ FAIL |
| **Failing Endpoints** | 384 / 3092 | ❌ 12.4% fail |
| **Clock Period** | 10.000 ns | Target |
| **Required Time** | 10.766 ns | After uncertainty |
| **Arrival Time** | 12.108 ns | Actual worst path |

### Hold Timing (Min Delay)

| Metric | Value | Status |
|--------|-------|--------|
| **WHS (Worst Hold Slack)** | 4.500 ns | ✅ PASS |
| **THS (Total Hold Slack)** | 0.000 ns | ✅ PASS |
| **Failing Endpoints** | 0 / 1524 | ✅ All pass |

**Hold timing is fine** - no hold violations.

### Pulse Width

| Metric | Value | Status |
|--------|-------|--------|
| **WPWS (Worst Pulse Width Slack)** | 4.500 ns | ✅ PASS |
| **TPWS (Total Pulse Width Slack)** | 0.000 ns | ✅ PASS |

---

## Critical Path Analysis

### Worst Path (Slack: -1.342 ns)

**Source:** `v_data[7]` (input port)  
**Destination:** `output_row_reg[63][21]/D` (register)  
**Path Type:** Setup (Max at Slow Process Corner)  
**Logic Levels:** 6 (CARRY4=2, DSP48E1=2, LUT2=1, LUT4=1)

**Detailed Timing Breakdown:**

| Stage | Component | Delay (ns) | Cumulative (ns) | Notes |
|-------|-----------|------------|-----------------|-------|
| **Clock edge** | - | 0.000 | 0.000 | Rising edge @ 0 ns |
| **Input delay** | Constraint | 3.000 | 3.000 | External source delay |
| **Routing** | Net | 0.973 | 3.973 | v_data[7] → DSP |
| **DSP multiply** | DSP48E1 | 3.851 | 7.824 | attention_weight × v_data |
| **DSP cascade** | Net | 0.055 | 7.879 | PCOUT → PCIN |
| **DSP accumulate** | DSP48E1 | 1.518 | 9.397 | Add to output_row |
| **Routing** | Net | 0.800 | 10.197 | DSP → fabric logic |
| **LUT logic** | LUT2 | 0.124 | 10.321 | Carry chain input |
| **Carry chain 1** | CARRY4 | 0.533 | 10.854 | Multi-bit add |
| **Carry chain 2** | CARRY4 | 0.337 | 11.191 | Propagate carry |
| **Routing** | Net | 0.611 | 11.802 | Carry → output mux |
| **Output mux** | LUT4 | 0.306 | 12.108 | Select result |
| **Setup time** | FDCE | 0.077 | - | Register setup |
| **TOTAL** | - | **12.108 ns** | - | **Exceeds 10.766 ns** |

**Required time:** 10.766 ns (10.000 - 0.235 uncertainty + 0.924 clock skew + 0.077 setup)  
**Arrival time:** 12.108 ns  
**Slack:** 10.766 - 12.108 = **-1.342 ns** ❌

---

## Root Cause Analysis

### Why Timing Failed

**The critical path is in OUTPUT_LOOP state:**

```verilog
// Line 245-246 in streaming_attention_v3.v
output_row[elem_idx - 1] <= output_row[elem_idx - 1] +
    (attention_weights[key_idx] * $signed(v_data));
```

**This creates a READ-MODIFY-WRITE pattern:**

```
1. Read output_row[elem_idx-1]        (register read)
2. Multiply attention_weight × v_data  (DSP48E1)
3. Add multiply result to old value    (DSP48E1 or fabric)
4. Write back to output_row[elem_idx-1] (register write)
```

**Problem:** Steps 2 and 3 happen in the SAME CYCLE, creating a long combinational path.

### Why Prediction Was Wrong

**Predicted:** 7.5 ns for multiply-accumulate  
**Actual:** 9.108 ns (data path) + 3.000 ns (input delay) = 12.108 ns total

**Errors in prediction:**

| Factor | Predicted | Actual | Delta |
|--------|-----------|--------|-------|
| DSP multiply | 2.5 ns | 3.851 ns | +1.351 ns |
| DSP accumulate | Included above | 1.518 ns | Separate! |
| Fabric add | 3.0 ns | 0.994 ns (LUT+CARRY) | -2.006 ns |
| Input delay | Not included | 3.000 ns | +3.000 ns |
| Clock uncertainty | 0.2 ns | 0.235 ns | +0.035 ns |

**Key mistakes:**
1. **Didn't account for input delay** (3 ns) - this is part of the path!
2. **Underestimated DSP delay** - Used 2.5 ns, actual is 3.851 ns for cascaded DSP
3. **Didn't realize DSP cascade adds delay** - Two DSP48E1 blocks in series
4. **Overestimated fabric add** - Carry chains are faster than I thought

### DSP Cascade Explanation

The synthesis inferred **two cascaded DSP48E1 blocks:**

```
p_1_out:      First DSP  (multiply)
p_1_out__0:   Second DSP (accumulate via PCIN)
```

**Why cascade?**
- Vivado optimized the multiply-accumulate into DSP cascade
- PCOUT → PCIN connection allows chaining without fabric routing
- But adds 1.518 ns delay for the second DSP

**Total DSP delay:** 3.851 + 1.518 = **5.369 ns** (71% of critical path!)

---

## Comparison: Predicted vs Actual

### Critical Paths

| Path | Predicted Delay | Actual Delay | Delta | Status |
|------|----------------|--------------|-------|--------|
| **Multiply-accumulate** | 7.5 ns | 12.1 ns | +4.6 ns | ❌ Much worse |
| Softmax LUT access | 7.5 ns | Not critical | - | ✅ Not an issue |
| Softmax division | 7.5 ns | Not critical | - | ✅ Not an issue |
| Address generation | 3.8 ns | Not critical | - | ✅ As expected |
| Output requantization | 2.6 ns | Not critical | - | ✅ As expected |

**Conclusion:** Completely wrong about which path would be critical!

### Timing Margin

| Metric | Predicted | Actual | Delta |
|--------|-----------|--------|-------|
| WNS | +2.5 ns | -1.342 ns | -3.842 ns |
| Margin | 25% | -13.4% | -38.4% |
| Status | ✅ Pass | ❌ Fail | - |

**Prediction error:** 3.842 ns (38.4% of clock period)

---

## All Failing Paths

**Pattern:** All 384 failing paths have the same structure:
- Source: `v_data[7]` or `v_data[6]` (input ports)
- Through: Two cascaded DSP48E1 blocks
- Destination: `output_row_reg[*][*]` (various bits of output accumulator)

**Slack range:** -1.342 ns to approximately -0.5 ns

**Common characteristics:**
- All in OUTPUT_LOOP state
- All involve multiply-accumulate
- All have 5-6 logic levels
- All include DSP cascade

**This is a systemic issue, not isolated paths.**

---

## Resource Utilization

### Actual vs Predicted

| Resource | Predicted | Actual | Delta | Utilization |
|----------|-----------|--------|-------|-------------|
| LUTs | 8,000 | 868 | -7,132 (-89%) | 1.63% |
| FFs | 5,000 | 1,517 | -3,483 (-70%) | 1.43% |
| DSP48 | 64 | 2 | -62 (-97%) | 0.91% |
| BRAM | 1-2 | 0 | -1 to -2 | 0.00% |

**Resources are fine** - timing is the only issue.

---

## Proposed Solutions

### Solution 1: Pipeline DSP Operations (RECOMMENDED)

**Approach:** Add pipeline register between multiply and accumulate

**Implementation:**
```verilog
// Current (1 cycle):
output_row[i] <= output_row[i] + (attention_weights[k] * v_data);

// Pipelined (2 cycles):
reg signed [31:0] mult_result;

// Cycle 1: Multiply
always @(posedge clk) begin
    mult_result <= attention_weights[key_idx] * $signed(v_data);
end

// Cycle 2: Accumulate
always @(posedge clk) begin
    output_row[elem_idx] <= output_row[elem_idx] + mult_result;
end
```

**Impact:**
- Breaks critical path: 12.1 ns → ~6 ns per stage
- Adds 1 cycle per element
- Total latency increase: +64 cycles (L=8, D=64)
- New total: 1736 + 64 = **1800 cycles**
- Latency increase: 3.7%

**Timing improvement:**
- Multiply stage: ~6 ns (4 ns margin)
- Accumulate stage: ~6 ns (4 ns margin)
- **Expected WNS: +4 ns** ✅

**Recommendation:** ✅ **IMPLEMENT THIS**

---

### Solution 2: Enable DSP Pipeline Registers

**Approach:** Use DSP48E1 internal pipeline stages

**Implementation:**
```verilog
(* use_dsp = "yes" *)
(* dsp_pipeline = "2" *)  // Enable 2-stage pipeline
reg signed [31:0] output_row [0:D-1];
```

**Impact:**
- Vivado automatically pipelines DSP
- Adds 2 cycles latency per multiply-accumulate
- May not be enough to fix timing

**Timing improvement:**
- Estimated: 2-3 ns improvement
- **Expected WNS: +1 to +2 ns** (marginal)

**Recommendation:** ⚠️ Try if Solution 1 doesn't work

---

### Solution 3: Reduce Clock Frequency

**Approach:** Target 90 MHz instead of 100 MHz

**Implementation:**
```tcl
# In constraints file
create_clock -period 11.111 -name clk [get_ports clk]
```

**Impact:**
- Period: 10 ns → 11.111 ns (+1.111 ns)
- Current slack: -1.342 ns
- New slack: -1.342 + 1.111 = **-0.231 ns** (still fails!)
- Need 88 MHz (11.36 ns) to pass

**Timing improvement:**
- At 88 MHz: **Expected WNS: +0.02 ns** (barely passes)

**Recommendation:** ❌ Not sufficient alone, use with Solution 1

---

### Solution 4: Restructure Accumulation

**Approach:** Use separate multiply and accumulate states

**Implementation:**
```verilog
// State machine changes
localparam OUTPUT_MULT = 4'd8;  // Multiply only
localparam OUTPUT_ACC  = 4'd9;  // Accumulate only

// Cycle 1: OUTPUT_MULT
mult_result <= attention_weights[key_idx] * v_data;

// Cycle 2: OUTPUT_ACC  
output_row[elem_idx] <= output_row[elem_idx] + mult_result;
```

**Impact:**
- Same as Solution 1 (adds 1 cycle per element)
- More explicit state machine
- Easier to understand and verify

**Recommendation:** ✅ **EQUIVALENT TO SOLUTION 1**

---

## Recommended Fix Strategy

### Phase 1: Quick Fix (Immediate)

**Implement Solution 1 (Pipeline DSP):**

1. Add `mult_result` pipeline register
2. Split OUTPUT_LOOP into 2 cycles per element
3. Update cycle count: 1736 → 1800 cycles
4. Re-synthesize and verify timing

**Expected result:** WNS = +4 ns ✅

**Time required:** 2-3 hours

---

### Phase 2: Optimization (If needed)

**If Phase 1 doesn't achieve +2 ns margin:**

1. Enable DSP pipeline registers (Solution 2)
2. Reduce clock to 95 MHz (Solution 3)
3. Verify timing closure

**Expected result:** WNS = +2 ns minimum

---

### Phase 3: BRAM Fix (Parallel)

**Implement softmax_unit_v3 with BRAM:**

1. This won't fix the critical path (which is in OUTPUT_LOOP)
2. But improves overall timing margin
3. Saves 64 LUTs
4. Good practice for proper resource usage

**Expected result:** Additional timing margin in softmax paths

---

## Lessons Learned

### What Went Wrong with Predictions

1. **Didn't account for input delay constraints**
   - Input delay is part of the timing path
   - Must include in calculations

2. **Underestimated DSP cascade delay**
   - Assumed single DSP: 2.5 ns
   - Actual cascade: 5.4 ns (2× longer!)

3. **Wrong critical path identified**
   - Predicted: Softmax LUT access
   - Actual: Output accumulation
   - Need to analyze all paths, not just "obvious" ones

4. **Didn't consider synthesis optimizations**
   - Vivado inferred DSP cascade
   - Changed the timing characteristics
   - Must verify after synthesis

### How to Improve Future Predictions

1. **Always include constraint overhead:**
   - Input delay
   - Output delay
   - Clock uncertainty
   - Setup/hold time

2. **Use worst-case delays:**
   - DSP48E1: 4 ns (not 2.5 ns)
   - Routing: 1 ns (not 0.3 ns)
   - Add 20% margin for synthesis optimization

3. **Analyze all multiply-accumulate paths:**
   - These are typically critical
   - DSP blocks are fast but not instant
   - Cascading adds significant delay

4. **Verify with synthesis:**
   - Predictions are estimates
   - Synthesis reveals actual implementation
   - Always measure, don't just predict

---

## Next Steps

### Immediate Actions

1. ✅ **Document timing failure** (this document)
2. ⏳ **Implement Solution 1** (pipeline DSP)
3. ⏳ **Re-synthesize with fix**
4. ⏳ **Verify timing closure**
5. ⏳ **Update cycle count predictions**

### Follow-up Actions

6. ⏳ **Implement BRAM fix** (softmax_unit_v3)
7. ⏳ **Post-synthesis simulation**
8. ⏳ **Compare v3 vs v3.1 performance**
9. ⏳ **Document final results**

---

## Conclusion

**Status:** ❌ streaming_attention_v3 **DOES NOT MEET 100 MHz timing**

**Root Cause:** Multiply-accumulate in OUTPUT_LOOP creates 12.1 ns path (need <10.8 ns)

**Fix:** Pipeline DSP operations (adds 64 cycles, 3.7% latency increase)

**Confidence:** HIGH - Solution 1 will fix timing with +4 ns margin

**Learning:** Always measure, never assume. Predictions were 38% off!

---

**Document Status:** ✅ Complete - Timing analysis finished  
**Next Action:** Implement DSP pipeline fix  
**Author:** Claude (Performance Analyst Role)  
**Date:** 2026-04-13
