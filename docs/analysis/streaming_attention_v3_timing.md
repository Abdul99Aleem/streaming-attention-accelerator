# Timing Analysis - streaming_attention_v3
**Date:** 2026-04-13  
**Role:** Performance Analyst  
**Status:** 🔄 In Progress - Predicting timing before measurement  
**Target:** 100 MHz (10 ns period) on Zynq-7020 (speed grade -1)

---

## Executive Summary

This document analyzes the timing characteristics of streaming_attention_v3 to:
1. **Predict critical paths** before synthesis with constraints
2. **Identify timing bottlenecks** in the sequential datapath
3. **Create proper timing constraints** for 100 MHz operation
4. **Measure actual timing** and compare with predictions
5. **Document timing closure strategy** if violations occur

**Current Status:** Previous synthesis had NO timing constraints applied. This analysis establishes baseline predictions before constrained synthesis.

---

## Design Overview

### Architecture Summary

streaming_attention_v3 is a **fully sequential** attention accelerator:

```
Cycle Budget: ~1736 cycles per attention operation
Clock Target: 100 MHz (10 ns period)
Latency Target: 17.36 μs per operation

Key Characteristics:
- Sequential FSM with 13 states
- 2 DSP48 slices (multiply operations)
- 868 LUTs, 1517 FFs
- No BRAM (exp_lut in distributed RAM)
- Softmax unit v2 integrated (19 cycles)
```

### Datapath Components

| Component | Function | Timing Sensitivity |
|-----------|----------|-------------------|
| FSM | State control | Low (simple decode) |
| Address generation | Memory addressing | Medium (arithmetic) |
| Multiply-accumulate | Dot products | **HIGH** (DSP + accumulator) |
| Softmax unit | Normalization | **HIGH** (LUT access + division) |
| Output requantization | Scale down | Medium (shift + truncate) |

---

## Critical Path Prediction

### Path 1: Multiply-Accumulate Chain (HIGHEST RISK)

**Location:** SCORE_LOOP and OUTPUT_LOOP states

**Datapath:**
```
Register → Multiplier → Adder → Accumulator Register
(q_row)   (DSP48)      (fabric) (dot_acc)
```

**Detailed Timing Breakdown:**

```verilog
// SCORE_LOOP state
dot_acc <= dot_acc + ($signed(q_row[elem_idx - 1]) * $signed(k_data));

// Path components:
// 1. Register read: q_row[elem_idx-1]
// 2. Multiply: q_row × k_data (INT8 × INT8 → INT16)
// 3. Add: multiply_result + dot_acc (INT16 + INT32 → INT32)
// 4. Register write: dot_acc
```

**Predicted Timing:**

| Stage | Delay (ns) | Component | Notes |
|-------|-----------|-----------|-------|
| Clock-to-Q | 0.5 | FF output | q_row register |
| Routing | 0.3 | Net delay | To DSP input |
| Multiply | 2.5 | DSP48E1 | INT8×INT8, pipelined mode OFF |
| Routing | 0.4 | Net delay | DSP to fabric adder |
| Add (32-bit) | 3.0 | Fabric LUTs | Carry chain propagation |
| Routing | 0.3 | Net delay | To accumulator |
| Setup time | 0.5 | FF input | dot_acc register |
| **TOTAL** | **7.5 ns** | | **75% of 10 ns budget** |

**Risk Assessment:** 🟡 MEDIUM
- 2.5 ns margin (25%)
- Acceptable for speed grade -1
- May fail in worst-case corner

**Mitigation Options:**
1. Enable DSP48 pipeline registers (adds 1 cycle latency)
2. Break into 2-cycle operation with intermediate register
3. Reduce clock to 90 MHz (11.1 ns period)

---

### Path 2: Softmax LUT Access (HIGH RISK)

**Location:** softmax_unit_v2 module

**Datapath:**
```
Score → Address Calc → LUT Read → Exp Value
(INT32) (clamp/offset) (dist RAM) (INT16)
```

**Detailed Timing Breakdown:**

```verilog
// Inside softmax_unit_v2
lut_addr = (scores[i] - max_score) + 128;  // Clamp to [0, 255]
exp_values[i] <= exp_lut[lut_addr];
```

**Predicted Timing:**

| Stage | Delay (ns) | Component | Notes |
|-------|-----------|-----------|-------|
| Clock-to-Q | 0.5 | FF output | scores register |
| Subtract | 1.5 | Fabric LUTs | 32-bit subtraction |
| Add offset | 0.8 | Fabric LUTs | Add 128 |
| Clamp logic | 1.2 | Fabric LUTs | Saturate to [0,255] |
| Routing | 0.5 | Net delay | To LUT RAM |
| LUT RAM read | 2.0 | Distributed RAM | Asynchronous read |
| Routing | 0.5 | Net delay | To output register |
| Setup time | 0.5 | FF input | exp_values register |
| **TOTAL** | **7.5 ns** | | **75% of 10 ns budget** |

**Risk Assessment:** 🟡 MEDIUM
- 2.5 ns margin (25%)
- Distributed RAM read is combinational (slow)
- Address calculation has long logic depth

**Mitigation Options:**
1. **Convert to BRAM** (synchronous read, adds 1 cycle latency)
2. Pipeline the address calculation
3. Pre-compute clamped addresses in previous cycle

**RECOMMENDATION:** Convert exp_lut to BRAM (Task #2)

---

### Path 3: Division in Softmax (UNKNOWN RISK)

**Location:** softmax_unit_v2 normalization

**Datapath:**
```
Sum → Reciprocal LUT → Multiply → Normalized Weight
(INT32) (dist RAM)     (DSP48)    (INT16)
```

**Issue:** Division implementation not visible in top-level code. Need to examine softmax_unit_v2 internals.

**Predicted Timing (if using reciprocal LUT):**

| Stage | Delay (ns) | Component | Notes |
|-------|-----------|-----------|-------|
| Sum calculation | 2.0 | Adder tree | 8 values → 1 sum |
| LUT address | 0.5 | Truncate/index | Map sum to LUT index |
| Reciprocal LUT | 2.0 | Distributed RAM | 1/sum lookup |
| Multiply | 2.5 | DSP48E1 | weight × reciprocal |
| Setup | 0.5 | FF input | Output register |
| **TOTAL** | **7.5 ns** | | **75% of 10 ns budget** |

**Risk Assessment:** 🟡 MEDIUM
- Similar to other paths
- Depends on actual softmax implementation

---

### Path 4: Address Generation (LOW RISK)

**Location:** Memory interface combinational logic

**Datapath:**
```
State + Indices → Address Calculation → Memory Address
(FSM)   (counters) (multiply + add)    (10-bit)
```

**Example:**
```verilog
q_addr = query_idx * D + elem_idx;  // query_idx * 64 + elem_idx
```

**Predicted Timing:**

| Stage | Delay (ns) | Component | Notes |
|-------|-----------|-----------|-------|
| State decode | 0.5 | LUT | FSM output |
| Index read | 0.5 | FF output | query_idx, elem_idx |
| Multiply by 64 | 1.5 | Fabric | Shift + add (64 = 2^6) |
| Add offset | 0.8 | Fabric | Add elem_idx |
| Routing | 0.5 | Net delay | To memory port |
| **TOTAL** | **3.8 ns** | | **38% of 10 ns budget** |

**Risk Assessment:** 🟢 LOW
- 6.2 ns margin (62%)
- Simple arithmetic
- Well within timing budget

---

### Path 5: Output Requantization (LOW RISK)

**Location:** Output write logic

**Datapath:**
```
Accumulator → Right Shift → Truncate → Output
(INT32)       (>>> 15)      (8-bit)    (INT8)
```

**Code:**
```verilog
out_data = output_row[elem_idx] >>> 15;
```

**Predicted Timing:**

| Stage | Delay (ns) | Component | Notes |
|-------|-----------|-----------|-------|
| Register read | 0.5 | FF output | output_row[elem_idx] |
| Barrel shifter | 1.5 | Fabric LUTs | 15-bit right shift |
| Truncate | 0.3 | Wire | Select bits [7:0] |
| Routing | 0.3 | Net delay | To output port |
| **TOTAL** | **2.6 ns** | | **26% of 10 ns budget** |

**Risk Assessment:** 🟢 LOW
- 7.4 ns margin (74%)
- Shift is relatively fast
- No timing concerns

---

## Predicted Critical Path Summary

**Top 3 Critical Paths (predicted):**

| Rank | Path | Predicted Delay | Margin | Risk |
|------|------|----------------|--------|------|
| 1 | Multiply-accumulate (SCORE_LOOP) | 7.5 ns | 2.5 ns | 🟡 Medium |
| 2 | Softmax LUT access | 7.5 ns | 2.5 ns | 🟡 Medium |
| 3 | Softmax division/normalization | 7.5 ns | 2.5 ns | 🟡 Medium |

**Overall Prediction:** ✅ **LIKELY TO MEET TIMING**
- All critical paths have 25% margin
- Speed grade -1 has additional margin
- No paths exceed 10 ns budget

**Confidence Level:** 70%
- Based on typical delays for Zynq-7020
- Actual routing delays may vary
- Worst-case corner may be tighter

---

## Timing Constraints Strategy

### Primary Clock Constraint

```tcl
# 100 MHz clock (10 ns period)
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# Clock uncertainty (jitter + skew)
set_clock_uncertainty 0.200 [get_clocks clk]
```

**Rationale:**
- 10 ns period for 100 MHz
- 200 ps uncertainty (2% of period, conservative)
- Waveform: 50% duty cycle (5 ns high, 5 ns low)

### Input Delay Constraints

```tcl
# Assume external source provides data with 2 ns setup/hold window
set_input_delay -clock clk -min 1.000 [get_ports {rst_n start q_data k_data v_data scale_shift}]
set_input_delay -clock clk -max 3.000 [get_ports {rst_n start q_data k_data v_data scale_shift}]
```

**Rationale:**
- Max delay: 3 ns (data arrives 3 ns after clock edge)
- Min delay: 1 ns (data stable 1 ns after clock edge)
- Provides 2 ns window for data validity
- Conservative for BRAM interface

### Output Delay Constraints

```tcl
# Assume external destination requires data 2 ns before next clock
set_output_delay -clock clk -min 1.000 [get_ports {done busy out_data out_wr_en out_addr q_addr q_rd_en k_addr k_rd_en v_addr v_rd_en}]
set_output_delay -clock clk -max 3.000 [get_ports {done busy out_data out_wr_en out_addr q_addr q_rd_en k_addr k_rd_en v_addr v_rd_en}]
```

**Rationale:**
- Max delay: 3 ns (data must be stable 3 ns after clock)
- Min delay: 1 ns (data can change 1 ns after clock)
- Leaves 7 ns for internal logic (10 - 3 = 7 ns)

### False Path Constraints

```tcl
# Asynchronous reset - don't time reset paths
set_false_path -from [get_ports rst_n] -to [all_registers]
```

**Rationale:**
- Reset is asynchronous (negedge rst_n)
- Reset paths don't need timing analysis
- Prevents false timing violations

### Multi-Cycle Path Constraints

**NOT NEEDED for v3** - all operations complete in 1 cycle

If we had multi-cycle operations:
```tcl
# Example: If division took 2 cycles
# set_multicycle_path -setup 2 -from [get_pins softmax_inst/div_start] -to [get_pins softmax_inst/div_done]
```

---

## Timing Closure Strategy

### If Timing Violations Occur

**Step 1: Analyze Failing Paths**
```tcl
report_timing -max_paths 10 -nworst 1 -delay_type max -sort_by slack
```

**Step 2: Identify Root Cause**
- Logic depth too deep?
- Routing congestion?
- DSP not pipelined?
- LUT RAM too slow?

**Step 3: Apply Fixes (in order of preference)**

**Option A: Pipeline Critical Paths**
```verilog
// Add pipeline stage to multiply-accumulate
reg signed [15:0] mult_result;
always @(posedge clk) begin
    mult_result <= q_row[elem_idx-1] * k_data;
    dot_acc <= dot_acc + mult_result;
end
```
- Adds 1 cycle latency per operation
- Total latency increases by ~64 cycles per query
- New total: ~1800 cycles (still acceptable)

**Option B: Enable DSP Pipeline Registers**
```verilog
// Use DSP48 internal pipeline
(* use_dsp = "yes" *)
(* dsp_cascade = "no" *)
reg signed [31:0] dot_acc;
```
- Vivado automatically pipelines DSP
- May add 1-2 cycle latency
- Improves timing by ~1-2 ns

**Option C: Convert LUT RAM to BRAM**
- Synchronous read adds 1 cycle latency
- Improves timing by ~2 ns
- Reduces LUT usage
- **RECOMMENDED** (Task #2)

**Option D: Reduce Clock Frequency**
- Last resort if all else fails
- 90 MHz (11.1 ns period) gives 15% more margin
- 80 MHz (12.5 ns period) gives 25% more margin
- Increases latency proportionally

---

## Measurement Plan

### Step 1: Synthesize with Constraints

```bash
cd vivado
vivado -mode batch -source synth_v3_with_timing.tcl
```

**Script contents:**
```tcl
# Read RTL
read_verilog rtl/primitives/mac_int8.v
read_verilog rtl/softmax/softmax_unit_v2.v
read_verilog rtl/attention/streaming_attention_v3.v

# Read constraints
read_xdc constraints/streaming_attention_v3.xdc

# Synthesize
synth_design -top streaming_attention_v3 -part xc7z020clg400-1

# Generate reports
report_timing_summary -file synth_v3_timing_output/timing_summary.rpt
report_timing -max_paths 10 -file synth_v3_timing_output/critical_paths.rpt
report_utilization -file synth_v3_timing_output/utilization.rpt
report_power -file synth_v3_timing_output/power.rpt
```

### Step 2: Analyze Results

**Key Metrics to Extract:**

| Metric | Symbol | Target | How to Read |
|--------|--------|--------|-------------|
| Worst Negative Slack | WNS | > 0 ns | Positive = timing met |
| Total Negative Slack | TNS | 0 ns | Sum of all violations |
| Worst Hold Slack | WHS | > 0 ns | Hold time margin |
| Critical path delay | - | < 10 ns | Actual longest path |
| Number of failing endpoints | - | 0 | Paths with violations |

**Success Criteria:**
- ✅ WNS > 0 ns (no setup violations)
- ✅ WHS > 0 ns (no hold violations)
- ✅ TNS = 0 ns (no accumulated violations)
- ✅ All endpoints meet timing

### Step 3: Compare Predicted vs. Actual

**Comparison Table (to be filled after synthesis):**

| Path | Predicted | Actual | Delta | Analysis |
|------|-----------|--------|-------|----------|
| Multiply-accumulate | 7.5 ns | ___ ns | ___ ns | ___ |
| Softmax LUT access | 7.5 ns | ___ ns | ___ ns | ___ |
| Softmax division | 7.5 ns | ___ ns | ___ ns | ___ |
| Address generation | 3.8 ns | ___ ns | ___ ns | ___ |
| Output requantization | 2.6 ns | ___ ns | ___ ns | ___ |

**Analysis Questions:**
1. Were predictions accurate within ±20%?
2. Which paths were underestimated?
3. Which paths were overestimated?
4. What caused the differences?

### Step 4: Document Findings

Update this document with:
- Actual timing results
- Critical path details from Vivado
- Comparison analysis
- Lessons learned
- Recommendations for v4

---

## Expected Outcomes

### Best Case: Timing Met with Margin

```
WNS: +2.5 ns
TNS: 0 ns
Critical path: 7.5 ns (multiply-accumulate)
Margin: 25%
```

**Action:** Document success, proceed to post-synthesis simulation

### Likely Case: Timing Met, Small Margin

```
WNS: +0.5 ns
TNS: 0 ns
Critical path: 9.5 ns (softmax LUT)
Margin: 5%
```

**Action:** Document results, consider BRAM conversion for robustness

### Worst Case: Timing Violations

```
WNS: -1.5 ns
TNS: -45 ns
Failing endpoints: 30
Critical path: 11.5 ns (multiply-accumulate)
```

**Action:** Apply fixes (pipeline DSP, convert to BRAM, reduce clock)

---

## Next Steps

1. ✅ **This document created** - Predictions documented
2. ⏳ **Create synthesis script** with timing constraints
3. ⏳ **Run constrained synthesis** and collect reports
4. ⏳ **Analyze actual timing** and compare with predictions
5. ⏳ **Update this document** with measured results
6. ⏳ **Document lessons learned** for v4 design

---

## References

### Zynq-7020 Timing Specifications

| Parameter | Value | Source |
|-----------|-------|--------|
| Speed grade | -1 | Device part number |
| DSP48E1 multiply delay | 2.5-3.5 ns | DS190 datasheet |
| LUT delay | 0.1-0.3 ns | DS190 datasheet |
| Routing delay | 0.3-1.0 ns | Typical for fabric |
| Clock-to-Q | 0.4-0.6 ns | DS190 datasheet |
| Setup time | 0.4-0.6 ns | DS190 datasheet |

### Vivado Timing Analysis Commands

```tcl
# Detailed timing report
report_timing -max_paths 10 -nworst 1 -delay_type max -sort_by slack

# Timing summary
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose

# Clock interaction
report_clock_interaction

# Datasheet timing
report_datasheet

# Methodology checks
report_methodology
```

---

**Document Status:** 📝 Predictions Complete, Awaiting Measurement  
**Next Update:** After constrained synthesis completes  
**Author:** Claude (Performance Analyst Role)  
**Date:** 2026-04-13
