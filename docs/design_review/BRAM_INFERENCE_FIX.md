# BRAM Inference Fix - softmax_unit_v2
**Date:** 2026-04-13  
**Role:** Design Engineer  
**Status:** 🔄 Design Complete, Implementation Pending  
**Purpose:** Convert exp_lut from distributed RAM to BRAM for better timing and resource usage

---

## Executive Summary

The exp_lut lookup table in softmax_unit_v2 is currently implemented in **distributed RAM** (LUT-based storage) instead of **BRAM** (Block RAM). This wastes LUT resources and creates a long combinational path that impacts timing.

**Problem:** Asynchronous LUT read prevents BRAM inference  
**Solution:** Add pipeline stage for synchronous BRAM read  
**Cost:** +8 cycles latency (L=8), +1 cycle per element  
**Benefit:** Saves ~64 LUTs, improves timing by ~2 ns, uses proper BRAM

**Recommendation:** Implement fix - the latency increase is acceptable (27 vs 19 cycles)

---

## Problem Analysis

### Current Implementation

**Location:** `rtl/softmax/softmax_unit_v2.v`, lines 110-119, 306

```verilog
// LUT declaration
reg [15:0] exp_lut [0:EXP_LUT_SIZE-1];  // 256 entries × 16 bits = 4096 bits

initial begin
    $readmemh("mem/exp_lut.hex", exp_lut);
end

// LUT access (in COMPUTE_EXP state)
always @(posedge clk) begin
    if (state == COMPUTE_EXP) begin
        // Compute address combinationally
        shifted_val = shifted_scores[element_idx];
        if (shifted_val <= -32'sd8) begin
            lut_addr = 8'd0;
        end else if (shifted_val >= 32'sd0) begin
            lut_addr = 8'd255;
        end else begin
            lut_addr = 8'd255 + (shifted_val[7:0] << 5);
        end
        
        // Read LUT in same cycle (ASYNCHRONOUS READ)
        exp_values[element_idx] <= exp_lut[lut_addr];
    end
end
```

### Why BRAM Inference Fails

**BRAM Inference Requirements:**

| Requirement | Current Code | Status |
|-------------|--------------|--------|
| Size > 512 bits | 4096 bits (256×16) | ✅ Pass |
| Synchronous read | Asynchronous | ❌ **FAIL** |
| Registered address | Combinational | ❌ **FAIL** |
| Single clock domain | Yes | ✅ Pass |
| Proper coding style | Yes | ✅ Pass |

**The Critical Issue:**

```verilog
// Cycle N: Compute address and read in SAME cycle
lut_addr = ...;                        // Combinational
exp_values[element_idx] <= exp_lut[lut_addr];  // Same cycle read
```

This is an **asynchronous read** - the address is computed and used in the same clock cycle. BRAM requires:

```verilog
// Cycle N: Register address
lut_addr_reg <= ...;

// Cycle N+1: Read from registered address
exp_values[element_idx] <= exp_lut[lut_addr_reg];
```

### Current Resource Usage

**From synthesis report (V3_SYNTHESIS_ANALYSIS.md):**

```
LUTs:  868 (1.63% of 53,200)
BRAMs: 0   (0% of 140)
```

**Estimated LUT usage for exp_lut:**
- 256 entries × 16 bits = 4096 bits
- Each LUT6 can store 64 bits (as distributed RAM)
- Required LUTs: 4096 / 64 = **64 LUTs**
- This is ~7% of total LUT usage

**If converted to BRAM:**
- Uses 1 BRAM18 (18 Kb = 18,432 bits, plenty for 4096 bits)
- Frees up 64 LUTs
- Net LUT usage: 868 - 64 = **804 LUTs (1.51%)**

### Timing Impact

**Current critical path (from timing analysis):**

```
Score → Address Calc → LUT Read → Exp Value
        (1.5 ns)       (2.0 ns)    (0.5 ns)
        
Total: ~7.5 ns (75% of 10 ns budget)
```

**With BRAM (synchronous read):**

```
Cycle N:   Score → Address Calc → Register
                   (1.5 ns)        (0.5 ns)
                   Total: 2.0 ns

Cycle N+1: Register → BRAM Read → Exp Value
           (0.5 ns)   (1.5 ns)    (0.5 ns)
           Total: 2.5 ns
```

**Timing improvement:**
- Breaks long combinational path (7.5 ns → 2.5 ns max)
- Each cycle has more margin
- Better timing closure
- Reduces risk of timing violations

---

## Proposed Solution

### Design Changes

**Add pipeline stage for LUT address:**

```verilog
// New state machine (add 1 state)
localparam COMPUTE_EXP_ADDR = 3'b011;  // Compute LUT address
localparam COMPUTE_EXP_READ = 3'b100;  // Read LUT value
localparam SUM_EXP          = 3'b101;  // (renumbered)
localparam DIVIDE           = 3'b110;  // (renumbered)
localparam DONE             = 3'b111;  // (renumbered)

// Pipeline registers
reg [7:0] lut_addr_reg;  // Registered LUT address

// State: COMPUTE_EXP_ADDR
always @(posedge clk) begin
    if (state == COMPUTE_EXP_ADDR) begin
        // Compute and register address
        shifted_val = shifted_scores[element_idx];
        if (shifted_val <= -32'sd8) begin
            lut_addr_reg <= 8'd0;
        end else if (shifted_val >= 32'sd0) begin
            lut_addr_reg <= 8'd255;
        end else begin
            lut_addr_reg <= 8'd255 + (shifted_val[7:0] << 5);
        end
    end
end

// State: COMPUTE_EXP_READ
always @(posedge clk) begin
    if (state == COMPUTE_EXP_READ) begin
        // Read from registered address (SYNCHRONOUS READ)
        exp_values[element_idx] <= exp_lut[lut_addr_reg];
    end
end
```

### State Machine Changes

**Before (v2):**

```
IDLE → FIND_MAX → SHIFT → COMPUTE_EXP (L cycles) → SUM_EXP → DIVIDE (L cycles) → DONE
                           ^^^^^^^^^^^
                           1 cycle per element
```

**After (v3):**

```
IDLE → FIND_MAX → SHIFT → COMPUTE_EXP_ADDR → COMPUTE_EXP_READ → ... (repeat L times)
                           → SUM_EXP → DIVIDE (L cycles) → DONE
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                           2 cycles per element
```

**Cycle count change:**

| Stage | v2 Cycles | v3 Cycles | Delta |
|-------|-----------|-----------|-------|
| IDLE | 1 | 1 | 0 |
| FIND_MAX | 1 | 1 | 0 |
| SHIFT | 1 | 1 | 0 |
| COMPUTE_EXP | L (8) | 2L (16) | +L (+8) |
| SUM_EXP | 1 | 1 | 0 |
| DIVIDE | L (8) | L (8) | 0 |
| DONE | 1 | 1 | 0 |
| **Total** | **19** | **27** | **+8** |

**Impact on streaming_attention_v3:**

```
v3 with softmax_v2: ~1736 cycles
v3 with softmax_v3: ~1736 + (8 cycles × 8 queries) = 1800 cycles

Latency increase: 64 cycles = 0.64 μs @ 100 MHz
Percentage increase: 3.7%
```

**Acceptable?** ✅ Yes - 3.7% latency increase for better timing and resource usage

---

## Implementation Plan

### Step 1: Create softmax_unit_v3.v

**Changes from v2:**

1. Add `lut_addr_reg` pipeline register
2. Split COMPUTE_EXP into two states:
   - COMPUTE_EXP_ADDR: Calculate and register address
   - COMPUTE_EXP_READ: Read from BRAM
3. Update state machine transitions
4. Update element_idx counter logic
5. Update cycle count documentation

**File:** `rtl/softmax/softmax_unit_v3.v`

### Step 2: Verify BRAM Inference

**Synthesis check:**

```tcl
# After synthesis
report_utilization -hierarchical

# Look for:
# RAMB18E1 or RAMB36E1 instances in softmax_unit_v3
# Should see: 1 BRAM18 used
```

**Expected result:**

```
Hierarchy: softmax_unit_v3
  RAMB18E1: 1
  LUT:      ~800 (down from 868)
```

### Step 3: Update streaming_attention_v3

**Option A: Create streaming_attention_v3.1**
- Keep v3 with softmax_v2 (for comparison)
- Create v3.1 with softmax_v3
- Document performance difference

**Option B: Update v3 in place**
- Replace softmax_v2 with softmax_v3
- Update cycle count predictions
- Re-run synthesis

**Recommendation:** Option A - preserve v3 for comparison

### Step 4: Verification

**Testbench updates:**

1. Update expected cycle count (19 → 27)
2. Verify functional correctness unchanged
3. Verify BRAM inference in synthesis
4. Compare timing reports

**Success criteria:**

- ✅ Functional correctness: Output matches v2
- ✅ BRAM inference: 1 BRAM18 used
- ✅ LUT reduction: ~64 fewer LUTs
- ✅ Timing improvement: Critical path < 7.5 ns
- ✅ Cycle count: 27 cycles (as predicted)

---

## Trade-off Analysis

### Benefits

| Benefit | Quantified Impact |
|---------|------------------|
| **LUT savings** | 64 LUTs freed (7% reduction) |
| **Timing improvement** | Critical path: 7.5 ns → 2.5 ns |
| **Proper resource usage** | Uses BRAM for intended purpose |
| **Scalability** | Easier to increase LUT size if needed |
| **Timing margin** | More robust to PVT variations |

### Costs

| Cost | Quantified Impact |
|------|------------------|
| **Latency increase** | +8 cycles per softmax (42% increase) |
| **Total latency increase** | +64 cycles per attention (3.7% increase) |
| **BRAM usage** | 1 BRAM18 (0.7% of 140 BRAMs) |
| **Code complexity** | Slightly more complex state machine |

### Decision Matrix

**Weighting:**
- Timing closure: HIGH priority (critical for 100 MHz)
- Resource efficiency: MEDIUM priority (plenty of resources)
- Latency: LOW priority (3.7% increase acceptable)

**Conclusion:** ✅ **Benefits outweigh costs**

The 3.7% latency increase is negligible compared to:
- Improved timing margin (critical for meeting 100 MHz)
- Proper resource usage (BRAM vs LUT)
- Better scalability for future optimizations

---

## Alternative Approaches Considered

### Alternative 1: Keep Distributed RAM, Pipeline Address

**Approach:**
```verilog
// Cycle N: Register address
lut_addr_reg <= ...;

// Cycle N+1: Read distributed RAM
exp_values[element_idx] <= exp_lut[lut_addr_reg];
```

**Result:**
- Still uses distributed RAM (no LUT savings)
- Improves timing (breaks combinational path)
- Same latency increase as BRAM solution

**Verdict:** ❌ Worse than BRAM - no resource savings

### Alternative 2: Use Reciprocal LUT Instead

**Approach:**
- Pre-compute reciprocals: `recip_lut[i] = 1/exp(i)`
- Multiply instead of divide

**Result:**
- Requires 2 LUTs (exp + reciprocal)
- More complex addressing
- Doesn't solve timing issue

**Verdict:** ❌ More complex, doesn't address root cause

### Alternative 3: Reduce LUT Size

**Approach:**
- Use 128-entry LUT instead of 256
- Reduces to 2048 bits (32 LUTs)

**Result:**
- Still in distributed RAM (< 512 bits threshold)
- Reduced accuracy
- Doesn't solve timing issue

**Verdict:** ❌ Worse accuracy, doesn't help timing

### Alternative 4: Use DSP for Interpolation

**Approach:**
- Smaller LUT with linear interpolation
- Use DSP48 for multiply-add

**Result:**
- More complex logic
- Uses DSP resources
- Longer latency

**Verdict:** ❌ Over-engineered for this application

---

## Verification Strategy

### Functional Verification

**Test 1: Identical Output**
```
Input: Same 8 scores as v2 testbench
Expected: Identical weights output (within 1 LSB)
Method: Compare v2 vs v3 outputs
```

**Test 2: Cycle Count**
```
Input: Start signal
Expected: Valid asserted after exactly 27 cycles
Method: Count cycles from start to valid
```

**Test 3: Edge Cases**
```
Test cases:
- All scores equal (uniform distribution)
- One score much larger (peaked distribution)
- All scores negative
- Scores near overflow
```

### Synthesis Verification

**Check 1: BRAM Inference**
```bash
grep -i "RAMB" synth_output/utilization.rpt
# Expected: 1 RAMB18E1 in softmax_unit_v3
```

**Check 2: LUT Reduction**
```bash
# Compare v2 vs v3 LUT usage
# Expected: ~64 fewer LUTs in v3
```

**Check 3: Timing Improvement**
```bash
# Compare critical paths
# Expected: No paths > 7.5 ns through softmax
```

### Integration Verification

**Test: streaming_attention_v3.1**
```
Input: Full attention computation
Expected: 
- Correct output (matches v3 with v2)
- Cycle count: 1800 cycles (vs 1736 for v3)
- Timing: Meets 100 MHz
```

---

## Documentation Updates Required

### Files to Update

1. **rtl/softmax/softmax_unit_v3.v** (NEW)
   - Implement BRAM-friendly design
   - Document cycle count change
   - Add synthesis directives if needed

2. **rtl/attention/streaming_attention_v3.1.v** (NEW)
   - Instantiate softmax_unit_v3
   - Update cycle count predictions
   - Update comments

3. **docs/design/softmax_unit_v3.md** (NEW)
   - Complete design specification
   - State machine diagrams
   - Timing analysis

4. **docs/analysis/streaming_attention_v3.1.md** (NEW)
   - Updated performance predictions
   - Resource utilization
   - Timing analysis

5. **docs/verification/softmax_unit_v3.md** (NEW)
   - Test plan
   - Expected results
   - Comparison with v2

6. **tb/unit/tb_softmax_unit_v3.v** (NEW)
   - Testbench for v3
   - Cycle count verification
   - Functional verification

---

## Implementation Checklist

- [ ] Create softmax_unit_v3.v with BRAM-friendly design
- [ ] Create design document (docs/design/softmax_unit_v3.md)
- [ ] Create testbench (tb/unit/tb_softmax_unit_v3.v)
- [ ] Run functional simulation
- [ ] Verify cycle count (27 cycles)
- [ ] Run synthesis
- [ ] Verify BRAM inference (1 BRAM18)
- [ ] Verify LUT reduction (~64 LUTs saved)
- [ ] Verify timing improvement
- [ ] Create streaming_attention_v3.1.v
- [ ] Update integration testbench
- [ ] Run full attention simulation
- [ ] Compare v3 vs v3.1 performance
- [ ] Document results
- [ ] Update README.md with v3.1 information

---

## Expected Results Summary

### Resource Utilization

| Resource | v3 (with v2) | v3.1 (with v3) | Delta |
|----------|--------------|----------------|-------|
| LUTs | 868 | ~804 | -64 (-7.4%) |
| FFs | 1,517 | ~1,520 | +3 (pipeline reg) |
| DSPs | 2 | 2 | 0 |
| BRAMs | 0 | 1 | +1 |

### Performance

| Metric | v3 (with v2) | v3.1 (with v3) | Delta |
|--------|--------------|----------------|-------|
| Softmax cycles | 19 | 27 | +8 (+42%) |
| Total cycles | 1,736 | 1,800 | +64 (+3.7%) |
| Latency @ 100MHz | 17.36 μs | 18.00 μs | +0.64 μs |
| Critical path | ~7.5 ns | ~2.5 ns | -5.0 ns |

### Timing Margin

| Path | v3 (with v2) | v3.1 (with v3) | Improvement |
|------|--------------|----------------|-------------|
| Softmax LUT | 7.5 ns (25% margin) | 2.5 ns (75% margin) | +50% margin |
| Overall WNS | TBD | TBD | Expected better |

---

## Conclusion

Converting exp_lut to BRAM is the **correct design choice** because:

1. ✅ **Improves timing** - Breaks critical path, adds 50% margin
2. ✅ **Saves resources** - Frees 64 LUTs for other logic
3. ✅ **Proper usage** - BRAMs designed for lookup tables
4. ✅ **Minimal cost** - Only 3.7% latency increase
5. ✅ **Better scalability** - Easy to increase LUT size if needed

**Recommendation:** Implement immediately as part of v3 validation

---

**Document Status:** 📝 Design Complete, Ready for Implementation  
**Next Step:** Implement softmax_unit_v3.v  
**Author:** Claude (Design Engineer Role)  
**Date:** 2026-04-13
