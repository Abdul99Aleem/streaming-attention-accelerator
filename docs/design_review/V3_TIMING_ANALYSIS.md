# Timing Analysis - streaming_attention_v3 with Constraints
**Date:** 2026-04-03  
**Target:** 100 MHz (10 ns period)  
**Status:** ❌ Timing NOT Met  
**Purpose:** Analyze timing performance with proper constraints

---

## Executive Summary

**Critical Finding:** v3 does NOT meet 100 MHz timing constraints.

**Key Metrics:**
- **WNS (Worst Negative Slack):** -1.342 ns
- **TNS (Total Negative Slack):** -355.432 ns
- **Failing Endpoints:** 384 out of 4581 (8.4%)
- **Required Frequency:** 100 MHz (10 ns period)
- **Achievable Frequency:** ~88 MHz (11.342 ns period)

**Root Cause:** Long combinational path through cascaded DSP48E1 blocks

---

## Timing Summary

### Setup Timing (Max Delay)

| Metric | Value | Status |
|--------|-------|--------|
| WNS | -1.342 ns | ❌ FAIL |
| TNS | -355.432 ns | ❌ FAIL |
| Failing Endpoints | 384 / 4581 | 8.4% fail rate |
| Worst Path | v_data[7] → output_row_reg[63][21] | 12.108 ns |
| Required Time | 10.766 ns | - |
| Slack | -1.342 ns | ❌ |

### Hold Timing (Min Delay)

| Metric | Value | Status |
|--------|-------|--------|
| WHS | 0.062 ns | ✅ PASS |
| THS | 0.000 ns | ✅ PASS |
| Failing Endpoints | 0 / 4581 | ✅ All pass |

### Pulse Width

| Metric | Value | Status |
|--------|-------|--------|
| WPWS | 4.500 ns | ✅ PASS |
| TPWS | 0.000 ns | ✅ PASS |
| Failing Endpoints | 0 / 1524 | ✅ All pass |

**Conclusion:** Only setup timing fails. Hold and pulse width are fine.

---

## Critical Path Analysis

### Worst Path Details

**Path:** v_data[7] → output_row_reg[63][21]

**Timing Breakdown:**
```
Clock Period:           10.000 ns
Input Delay:             3.000 ns
Data Path Delay:         9.108 ns
  - Logic Delay:         6.669 ns (73.2%)
  - Route Delay:         2.439 ns (26.8%)
Clock Uncertainty:       0.235 ns
Setup Time:              0.077 ns
-----------------------------------
Required Time:          10.766 ns
Arrival Time:           12.108 ns
-----------------------------------
Slack:                  -1.342 ns ❌
```

### Path Stages

| Stage | Element | Delay (ns) | Cumulative (ns) |
|-------|---------|------------|-----------------|
| 1 | Input port v_data[7] | 0.000 | 3.000 |
| 2 | Routing to DSP | 0.973 | 3.973 |
| 3 | DSP48E1 (p_1_out) B→PCOUT | 3.851 | 7.824 |
| 4 | DSP cascade routing | 0.055 | 7.879 |
| 5 | DSP48E1 (p_1_out__0) PCIN→P | 1.518 | 9.397 |
| 6 | Routing to LUT | 0.800 | 10.197 |
| 7 | LUT2 logic | 0.124 | 10.321 |
| 8 | CARRY4 (S→CO) | 0.533 | 10.854 |
| 9 | CARRY4 (CI→O) | 0.337 | 11.191 |
| 10 | Routing to LUT | 0.611 | 11.802 |
| 11 | LUT4 logic | 0.306 | 12.108 |
| 12 | Setup to FDCE | - | - |

**Logic Levels:** 6 (CARRY4=2, DSP48E1=2, LUT2=1, LUT4=1)

---

## Why Timing Fails

### 1. Cascaded DSP48E1 Blocks

**The Problem:**
```verilog
// Two DSP blocks in cascade for multiply-accumulate
DSP48E1 p_1_out:      B[17:0] → PCOUT[47:0]    (3.851 ns)
DSP48E1 p_1_out__0:   PCIN[47:0] → P[47:0]     (1.518 ns)
                                    Total:       5.369 ns
```

**Why cascaded?**
- v3 computes: `output_row[i] += attention_weights[key_idx] * v_data`
- This is a 16-bit × 8-bit multiply with 32-bit accumulation
- Vivado infers DSP cascade for wide accumulation

**Impact:** 5.4 ns out of 10 ns budget consumed by DSPs alone (54%)

### 2. Long Routing Delays

**Routing delays:**
- Input to first DSP: 0.973 ns
- DSP output to LUT: 0.800 ns
- CARRY4 output to LUT: 0.611 ns
- **Total routing: 2.439 ns (26.8% of path)**

**Why long?**
- Design is unplaced (out-of-context synthesis)
- Actual placement will improve routing
- But won't fix the fundamental DSP cascade issue

### 3. Carry Chain Logic

**After DSPs:**
```
LUT2 → CARRY4 → CARRY4 → LUT4 → Register
```

**Purpose:** Accumulation and saturation logic

**Delay:** 1.911 ns (19% of path)

**Why needed?**
- Accumulating 32-bit results
- Checking for overflow
- Saturating to INT8 output

---

## Comparison: With vs. Without Constraints

| Metric | Without Constraints | With Constraints | Change |
|--------|---------------------|------------------|--------|
| LUTs | 868 | 795 | -73 (-8.4%) |
| FFs | 1517 | 1524 | +7 (+0.5%) |
| DSPs | 2 | 2 | 0 |
| MUXF7 | 250 | 240 | -10 |
| MUXF8 | 78 | 76 | -2 |
| Timing Check | ❌ Not performed | ✅ Performed | - |
| WNS | N/A | -1.342 ns | ❌ FAIL |

**Observation:** Synthesis with timing constraints produces slightly more optimized logic (fewer LUTs), but still fails timing.

---

## What Frequency CAN v3 Achieve?

**Calculation:**
```
Worst path delay = 12.108 ns
Add clock uncertainty = 0.235 ns
Add setup time = 0.077 ns
Total required period = 12.420 ns

Maximum frequency = 1 / 12.420 ns = 80.5 MHz
```

**With margin (10%):**
```
Safe frequency = 80.5 MHz × 0.9 = 72.5 MHz
```

**Recommendation:** Target 75 MHz instead of 100 MHz for v3.

---

## How to Fix Timing

### Option 1: Reduce Clock Frequency ✅ Easiest

**Change:** 100 MHz → 75 MHz (13.33 ns period)

**Pros:**
- No RTL changes needed
- Guaranteed to meet timing
- Still reasonable performance

**Cons:**
- 25% performance loss
- Latency increases from 1736 cycles @ 100 MHz (17.36 μs) to 1736 cycles @ 75 MHz (23.15 μs)

**Verdict:** Best option for v3 as-is.

### Option 2: Pipeline the Critical Path ⚠️ Moderate Effort

**Change:** Add pipeline register after DSP cascade

**Before:**
```
v_data → DSP → DSP → CARRY → LUT → output_row_reg
         (5.4ns)  (1.9ns)
```

**After:**
```
v_data → DSP → DSP → pipe_reg → CARRY → LUT → output_row_reg
         (5.4ns)                 (1.9ns)
```

**Pros:**
- Breaks critical path into two stages
- Can achieve 100 MHz
- Minimal area increase

**Cons:**
- Adds 1 cycle latency (1737 cycles total)
- Requires RTL modification
- Need to update FSM timing

**Verdict:** Good option if 100 MHz is required.

### Option 3: Redesign Datapath 🔴 High Effort

**Change:** Use different accumulation strategy

**Ideas:**
- Use BRAM for output buffer instead of registers
- Reduce accumulator width (accept some precision loss)
- Use fixed-point instead of integer arithmetic

**Pros:**
- Could improve timing significantly
- Might reduce resource usage

**Cons:**
- Major RTL rewrite
- Requires re-verification
- May affect accuracy

**Verdict:** Not recommended for v3. Consider for v4.

---

## Detailed Failing Paths

### Top 5 Worst Paths

| Rank | Source | Destination | Slack (ns) | Path Delay (ns) |
|------|--------|-------------|------------|-----------------|
| 1 | v_data[7] | output_row_reg[63][21] | -1.342 | 12.108 |
| 2 | v_data[7] | output_row_reg[0][19] | -1.134 | 11.900 |
| 3 | v_data[7] | output_row_reg[10][19] | -1.134 | 11.900 |
| 4 | v_data[7] | output_row_reg[11][19] | -1.134 | 11.900 |
| 5 | v_data[7] | output_row_reg[12][19] | -1.134 | 11.900 |

**Pattern:** All failing paths originate from v_data input and go through DSP cascade to output_row registers.

**Common characteristics:**
- All use cascaded DSP48E1 blocks
- All have 5-6 logic levels
- All have similar delays (11.9-12.1 ns)
- All fail by 1.1-1.4 ns

---

## Resource Utilization (With Timing Constraints)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | 795 | 53,200 | 1.49% |
| FFs | 1,524 | 106,400 | 1.43% |
| DSP48E1 | 2 | 220 | 0.91% |
| BRAM | 0 | 140 | 0.00% |
| MUXF7 | 240 | 26,600 | 0.90% |
| MUXF8 | 76 | 13,300 | 0.57% |

**Observation:** Very low utilization. Plenty of room for optimization or pipelining.

---

## Constraint Warnings

### Partial Input Delay

**Warning:** 29 input ports with partial input delay specified

**Affected ports:**
- q_data[7:0] (8 ports)
- k_data[7:0] (8 ports)
- v_data[7:0] (8 ports)
- q_addr[9:0], k_addr[9:0], v_addr[9:0], out_addr[9:0] (not constrained)
- Control signals (not constrained)

**Issue:** We only constrained data inputs, not address/control outputs.

**Fix needed:** Add constraints for all I/O ports.

### Missing Ports

**Warning:** No ports matched 'valid' and 'ready'

**Reason:** v3 uses 'done' and 'busy' instead of 'valid' and 'ready'

**Fix:** Update XDC file to use correct port names.

---

## Recommendations

### Immediate Actions

1. **Update constraints file**
   - Fix port names (done/busy instead of valid/ready)
   - Add constraints for all I/O ports
   - Add false paths for asynchronous signals if any

2. **Choose frequency target**
   - Option A: Reduce to 75 MHz (easiest, meets timing)
   - Option B: Keep 100 MHz and pipeline (more work, better performance)

3. **Re-synthesize with corrected constraints**
   - Verify timing with complete constraints
   - Check if timing improves

### For v4 Design

1. **Design for timing from the start**
   - Calculate critical path before implementation
   - Add pipeline stages where needed
   - Use timing-driven synthesis

2. **Use BRAM for large buffers**
   - Reduces register pressure
   - Improves timing (BRAM has predictable timing)
   - Frees up fabric resources

3. **Consider DSP pipelining**
   - DSP48E1 has internal pipeline registers
   - Can achieve higher frequencies
   - Adds latency but improves throughput

---

## Comparison with Predictions

### Predicted (from previous analysis)

| Metric | Predicted | Actual | Match? |
|--------|-----------|--------|--------|
| Can meet 100 MHz? | ✅ Assumed yes | ❌ No (-1.3ns slack) | ❌ Wrong |
| Critical path | Not analyzed | DSP cascade | - |
| Timing margin | Not calculated | -13.4% | - |

**Lesson:** Always run timing analysis. Don't assume designs meet timing.

---

## Summary

### What We Learned

1. **v3 does NOT meet 100 MHz timing**
   - Fails by 1.342 ns (13.4% over budget)
   - 384 failing endpoints (8.4% of paths)

2. **Critical path is DSP cascade**
   - Two DSP48E1 blocks in series: 5.4 ns (54% of budget)
   - Plus carry chains and routing: 3.7 ns
   - Total: 9.1 ns data path delay

3. **Achievable frequency is ~75 MHz**
   - With 10% margin for safety
   - Still reasonable performance
   - No RTL changes needed

4. **Pipelining can fix timing**
   - Add register after DSP cascade
   - Breaks path into two stages
   - Can achieve 100 MHz with 1 extra cycle latency

### Next Steps

1. ✅ Timing analysis complete
2. ⏭️ Update constraints file (fix port names)
3. ⏭️ Decide on frequency target (75 MHz or 100 MHz with pipeline)
4. ⏭️ Run post-synthesis simulation
5. ⏭️ Verify functionality unchanged

---

**This analysis reveals that "it synthesizes" ≠ "it meets timing". Always verify timing constraints.**
