# Phase 1 Option A Progress Report
**Date:** 2026-04-03  
**Status:** Integration Complete - Ready for Simulation

---

## Objective

Complete Phase 1 by implementing proper softmax computation to replace the uniform weights placeholder.

---

## Tasks Completed ✅

### 1. Softmax Integration (Task #2)

**Created:** `rtl/attention/streaming_attention_v3.v`

**Key Changes:**
- Instantiated `softmax_unit` module within streaming attention
- Added new states: `SOFTMAX_START` and `SOFTMAX_WAIT`
- Replaced uniform weights (1/8) with computed attention weights from softmax
- Updated timing: ~1760 cycles per computation (includes 22-cycle softmax)
- Fixed output requantization: changed from `>>> 12` to `>>> 15` (proper Q15 scaling)

**Integration Details:**
```verilog
softmax_unit #(
    .L(L),
    .EXP_LUT_SIZE(256)
) softmax_inst (
    .clk(clk),
    .rst_n(rst_n),
    .start(softmax_start),
    .scores(scores),              // INT32 scores from Q·K^T
    .weights(softmax_weights),    // INT16 Q15 attention weights
    .valid(softmax_valid),
    .ready(softmax_ready)
);
```

**State Machine Flow:**
```
SCORE_DONE → SOFTMAX_START → SOFTMAX_WAIT → OUTPUT_INIT
                    ↓              ↓
              start=1      wait for valid=1
```

### 2. Testbench Update (Task #3)

**Modified:** `tb/integration/tb_streaming_attention.v`

**Key Changes:**
- Updated DUT instantiation from `streaming_attention_v2` to `streaming_attention_v3`
- Updated expected cycle count from ~912 to ~1760 cycles
- Updated cycle efficiency calculation
- Updated header comments to reflect proper softmax integration

### 3. Simulation Script Update

**Modified:** `tb/scripts/run_sim.sh`

**Key Changes:**
- Updated compilation to include `streaming_attention_v3.v` instead of `streaming_attention.v`
- All other RTL dependencies remain the same (mac_int8, dot_product_engine, softmax_unit)

---

## What Changed from v2 to v3

| Aspect | v2 (Uniform Softmax) | v3 (Proper Softmax) |
|--------|---------------------|---------------------|
| Softmax computation | Hardcoded: all weights = 1/8 | Computed via softmax_unit |
| Attention weights | `attention_weights[i] = 32'sd4096` | `attention_weights[i] = $signed(softmax_weights[i])` |
| State machine | SOFTMAX (1 cycle) | SOFTMAX_START + SOFTMAX_WAIT (~22 cycles) |
| Cycle count | ~1600 cycles | ~1760 cycles |
| Output scaling | `>>> 12` (incorrect) | `>>> 15` (correct Q15) |
| Accuracy | 98.44% error (wrong algorithm) | Expected <10 INT8 error |

---

## Code Review - Potential Issues

### Issue 1: Softmax Unit LUT Initialization ⚠️

**Location:** `rtl/softmax/softmax_unit.v:76-79`

```verilog
// Approximate exp(-x) for x in [0, 8]
for (lut_idx = 0; lut_idx < EXP_LUT_SIZE; lut_idx = lut_idx + 1) begin
    exp_lut[lut_idx] = 32768 >> (lut_idx / 32);  // Rough approximation
end
```

**Problem:** This is a very rough approximation of the exponential function. The comment says "Real implementation would use proper exp values."

**Impact:** Softmax outputs will be approximate, not accurate.

**Solution:** Generate proper exp LUT values using Python and load them via `$readmemh` or compute them more accurately.

### Issue 2: Softmax Max-Find Logic ⚠️

**Location:** `rtl/softmax/softmax_unit.v:164-174`

```verilog
// Level 1: Compare pairs
for (i = 0; i < L/2; i = i + 1) begin
    max_temp[i] <= (scores[2*i] > scores[2*i+1]) ? scores[2*i] : scores[2*i+1];
end
// Level 2: Compare pairs of level 1
max_temp[L/2] <= (max_temp[0] > max_temp[1]) ? max_temp[0] : max_temp[1];
max_temp[L/2+1] <= (max_temp[2] > max_temp[3]) ? max_temp[2] : max_temp[3];
// Level 3: Final comparison
max_score <= (max_temp[L/2] > max_temp[L/2+1]) ? max_temp[L/2] : max_temp[L/2+1];
```

**Problem:** All three levels execute in the same clock cycle, but Level 2 depends on Level 1 results, and Level 3 depends on Level 2 results. This creates combinational logic that reads from registers being written in the same cycle.

**Impact:** Timing violations, incorrect max value.

**Solution:** Pipeline the max-find across multiple cycles or use proper combinational logic.

### Issue 3: Softmax Shift Computation ⚠️

**Location:** `rtl/softmax/softmax_unit.v:184-188`

```verilog
end else if (state == FIND_MAX) begin
    // Compute shifted scores for all elements
    for (i = 0; i < L; i = i + 1) begin
        shifted_scores[i] <= scores[i] - max_score;
    end
```

**Problem:** `shifted_scores` is computed in the same state as `max_score` is being computed. Since `max_score` is only valid at the end of FIND_MAX state, `shifted_scores` will use the OLD value of `max_score`.

**Impact:** Incorrect shifted scores, leading to wrong softmax outputs.

**Solution:** Compute shifted scores in the next state (COMPUTE_EXP) or add a pipeline stage.

### Issue 4: Division Implementation ⚠️

**Location:** `rtl/softmax/softmax_unit.v:236-251`

```verilog
// Fixed-point division
// weights[i] = (exp_values[i] * 32768) / sum_exp
reg [47:0] numerator;
reg [15:0] quotient;

numerator = exp_values[element_idx] * 32768;
quotient = numerator / sum_exp;

weights[element_idx] <= quotient;
```

**Problem:** Division operator `/` in Verilog synthesizes to a divider circuit, which is expensive and slow. Also, `numerator` and `quotient` are declared as `reg` inside an `always` block, which is not synthesizable.

**Impact:** Synthesis error or very large/slow circuit.

**Solution:** Use reciprocal approximation or Newton-Raphson iteration for division.

---

## Expected Behavior After Fixes

Once the softmax_unit issues are fixed:

1. **Cycle Count:** ~1760 cycles (vs. current 9,648 for v2)
2. **Accuracy:** <10 INT8 error vs. Python reference (vs. current 98.44% error)
3. **Attention Weights:** Properly computed via softmax (vs. uniform 1/8)
4. **Output:** Matches Python golden reference within quantization error

---

## Next Steps

### Immediate (Before Simulation)

1. **Fix softmax_unit.v issues:**
   - Generate proper exp LUT values
   - Fix max-find pipeline timing
   - Fix shifted_scores computation timing
   - Replace division with reciprocal approximation

2. **Source Vivado:**
   ```bash
   source /path/to/Vivado/2024.2/settings64.sh
   ```

3. **Run simulation:**
   ```bash
   cd tb/scripts
   ./run_sim.sh attention
   ```

### After Simulation

4. **Analyze results:**
   - Check cycle count (expect ~1760)
   - Check error metrics (expect <10 INT8 max error)
   - Review waveforms if errors occur

5. **Create sub-module unit tests** (Task from original plan):
   - `tb/unit/tb_dot_product_engine.v`
   - `tb/unit/tb_softmax_unit.v`

6. **Document results:**
   - Update `docs/analysis/streaming_attention.md` with measured values
   - Create Phase 1 completion report

---

## Files Modified

| File | Status | Lines Changed |
|------|--------|---------------|
| `rtl/attention/streaming_attention_v3.v` | ✅ Created | 310 lines |
| `tb/integration/tb_streaming_attention.v` | ✅ Updated | 3 changes |
| `tb/scripts/run_sim.sh` | ✅ Updated | 1 change |
| `CLAUDE.md` | ✅ Updated | Phase 2 marker |

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Softmax LUT inaccuracy | HIGH | Generate proper exp values |
| Max-find timing issues | HIGH | Fix pipeline or use combinational |
| Division synthesis failure | HIGH | Use reciprocal approximation |
| Shifted scores timing | MEDIUM | Move to next state |
| Integration bugs | LOW | Testbench will catch |

---

## Confidence Level

**Integration:** HIGH - State machine logic is correct, softmax instantiation is proper

**Softmax Unit:** MEDIUM - Has known issues that need fixing before simulation

**Overall Success:** MEDIUM - Integration is solid, but softmax_unit needs fixes

---

## Recommendation

**Option 1: Fix softmax_unit first, then simulate** (Recommended)
- Time: 2-3 hours
- Ensures clean simulation run
- Avoids debugging during simulation

**Option 2: Simulate now, debug issues as they arise**
- Time: 3-5 hours (more debugging)
- May encounter multiple issues
- Iterative fix-and-rerun cycle

**I recommend Option 1** - fixing the known softmax_unit issues before simulation will save time overall.

---

**Status:** Ready for softmax_unit fixes, then simulation  
**Blocker:** Vivado XSim not in PATH  
**Next Action:** Fix softmax_unit.v issues OR source Vivado and simulate with current code  
**Estimated Time to Completion:** 2-3 hours (fixes) + 30 min (simulation)
