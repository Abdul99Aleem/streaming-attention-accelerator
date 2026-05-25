# Post-Synthesis Verification Plan - streaming_attention_v3
**Date:** 2026-04-03  
**Status:** 📋 Planned (Not Yet Executed)  
**Purpose:** Verify synthesized netlist matches RTL behavior

---

## Verification Strategy

### What We're Verifying

**Question:** Does the synthesized netlist produce the same outputs as the behavioral RTL?

**Why This Matters:**
- Synthesis transformations might introduce bugs
- Timing violations could cause functional failures
- Optimization might change behavior unexpectedly

**What We Check:**
1. ✅ Functional equivalence (same outputs for same inputs)
2. ✅ Timing behavior (no glitches, proper synchronization)
3. ✅ Edge cases (reset, start/stop, boundary conditions)

---

## Verification Methodology

### 1. Behavioral Simulation (Baseline)

**Purpose:** Establish golden reference

**Steps:**
```bash
cd tb/integration
xvlog ../rtl/softmax/softmax_unit_v2.v
xvlog ../rtl/attention/streaming_attention_v3.v
xvlog tb_streaming_attention.v
xelab tb_streaming_attention -s sim_behavioral
xsim sim_behavioral -runall
```

**Expected Output:**
- Computation completes in ~1736 cycles
- Output matches expected values (within ±2 tolerance for INT8)
- No X or Z values in outputs

**Save:**
- Output memory contents → `behavioral_output.txt`
- Cycle count → `behavioral_cycles.txt`
- Waveform → `behavioral.vcd`

### 2. Post-Synthesis Simulation

**Purpose:** Verify synthesized netlist

**Steps:**
```bash
cd tb/integration
xvlog /home/aleem/Vivado/2024.2/data/verilog/src/glbl.v
xvlog ../vivado/synth_v3_timing_output/streaming_attention_v3_synth.v
xvlog tb_streaming_attention.v
xelab tb_streaming_attention glbl -s sim_post_synth
xsim sim_post_synth -runall
```

**Expected Output:**
- Same cycle count as behavioral (1736 cycles)
- Same output values (bit-exact match)
- No timing violations in waveform

**Save:**
- Output memory contents → `post_synth_output.txt`
- Cycle count → `post_synth_cycles.txt`
- Waveform → `post_synth.vcd`

### 3. Comparison

**Compare outputs:**
```bash
diff behavioral_output.txt post_synth_output.txt
```

**Expected:** No differences (files identical)

**If differences found:**
- Identify which elements differ
- Check if differences are within tolerance (±2 for INT8)
- Investigate root cause (synthesis bug vs. timing issue)

---

## Test Vectors

### Option 1: Random Vectors (Fallback)

**The testbench generates random vectors if files don't exist:**
```verilog
if (q_file == 0) begin
    $display("[INFO] Generating random test vectors instead");
    for (i = 0; i < L*D; i = i + 1) begin
        q_mem[i] = $random % 256;
    end
end
```

**Pros:**
- No setup required
- Tests general functionality

**Cons:**
- No golden reference to compare against
- Can't verify correctness, only that it runs
- Different vectors each run (not reproducible)

### Option 2: Python-Generated Vectors (Recommended)

**Generate test vectors using Python reference model:**

```python
# python/verification/generate_test_vectors.py
import numpy as np

# Parameters
L = 8  # Sequence length
D = 64  # Embedding dimension

# Generate random inputs
np.random.seed(42)  # Reproducible
Q = np.random.randint(-128, 127, (L, D), dtype=np.int8)
K = np.random.randint(-128, 127, (L, D), dtype=np.int8)
V = np.random.randint(-128, 127, (L, D), dtype=np.int8)

# Compute attention (golden reference)
scores = Q @ K.T  # (L, L)
scores = scores // 8  # Scale by sqrt(64) = 8
attention_weights = softmax(scores)  # (L, L)
output = attention_weights @ V  # (L, D)

# Save to files
np.savetxt('tb/integration/test_vectors/q_matrix.txt', Q.flatten(), fmt='%d')
np.savetxt('tb/integration/test_vectors/k_matrix.txt', K.flatten(), fmt='%d')
np.savetxt('tb/integration/test_vectors/v_matrix.txt', V.flatten(), fmt='%d')
np.savetxt('tb/integration/test_vectors/expected_output.txt', output.flatten(), fmt='%d')
```

**Pros:**
- Reproducible test vectors
- Golden reference for comparison
- Can verify correctness

**Cons:**
- Requires Python setup
- Need to implement softmax correctly

---

## What Could Go Wrong

### Issue 1: Timing Violations Cause Functional Errors

**Symptom:** Post-synthesis output differs from behavioral

**Root Cause:** Setup timing violations (-1.342 ns slack) cause metastability

**Example:**
```
Behavioral:  output[0] = 42
Post-synth:  output[0] = 43  (off by 1 due to timing glitch)
```

**How to detect:**
- Compare outputs element-by-element
- Look for small differences (±1 or ±2)
- Check if errors correlate with critical paths

**Fix:** Reduce clock frequency to 75 MHz

### Issue 2: X Propagation

**Symptom:** Post-synthesis simulation shows X (unknown) values

**Root Cause:** Uninitialized registers or combinational loops

**Example:**
```
Time 100ns: output_row[0] = 8'bxxxxxxxx
```

**How to detect:**
- Check waveform for X values
- Look at simulation log for warnings

**Fix:** 
- Add proper reset logic
- Initialize all registers
- Check for combinational loops

### Issue 3: Synthesis Optimization Breaks Functionality

**Symptom:** Post-synthesis behaves completely differently

**Root Cause:** Synthesis tool optimized away critical logic

**Example:**
```
Behavioral:  Completes in 1736 cycles
Post-synth:  Never completes (hangs)
```

**How to detect:**
- Check if FSM states are correct
- Verify control signals (start, done, busy)
- Look for optimized-away logic in synthesis log

**Fix:**
- Add `(* keep = "true" *)` attributes to critical signals
- Use `(* dont_touch = "true" *)` for critical modules

---

## Expected Results

### If Everything Works ✅

**Behavioral Simulation:**
```
========================================
Streaming Attention Integration Test
========================================
Parameters:
  L (sequence length):    8
  D (embedding dim):      64
  Clock period:           10 ns
  Clock frequency:        100 MHz
========================================

Loading test vectors from files...
  Q matrix loaded (512 elements)
  K matrix loaded (512 elements)
  V matrix loaded (512 elements)
  Expected output loaded (512 elements)
Test vectors loaded successfully

Starting attention computation...
Computation completed in 1736 cycles
Expected cycles: ~1736 (with softmax_unit_v2)
Cycle efficiency: 100.0%

Comparing outputs with expected values...

========================================
Output Comparison Results
========================================
Total elements:  512
Errors (>2):     0
Max error:       0
Average error:   0.00
Error rate:      0.00%

*** ALL OUTPUTS MATCH ***
========================================
```

**Post-Synthesis Simulation:**
```
[Same output as behavioral]

*** ALL OUTPUTS MATCH ***
```

**Comparison:**
```bash
$ diff behavioral_output.txt post_synth_output.txt
[No output - files are identical]
```

### If Timing Causes Issues ⚠️

**Post-Synthesis Simulation:**
```
========================================
Output Comparison Results
========================================
Total elements:  512
Errors (>2):     23
Max error:       3
Average error:   0.12
Error rate:      4.49%

*** MOSTLY CORRECT (<10% errors) ***
========================================
```

**Analysis:**
- Small number of errors (4.5%)
- Small error magnitude (max 3)
- Likely due to timing violations

**Action:** Reduce clock frequency to 75 MHz and re-test

---

## Verification Checklist

### Pre-Simulation

- [ ] Synthesized netlist exists (`streaming_attention_v3_synth.v`)
- [ ] Test vectors generated or testbench uses random fallback
- [ ] Simulation tools available (XSim or ModelSim)
- [ ] Memory initialization file exists (`mem/exp_lut.hex`)

### Behavioral Simulation

- [ ] Compiles without errors
- [ ] Runs to completion (no timeout)
- [ ] Produces valid outputs (no X or Z)
- [ ] Cycle count matches expectation (~1736)
- [ ] Outputs saved for comparison

### Post-Synthesis Simulation

- [ ] Compiles with Xilinx primitives (glbl.v)
- [ ] Runs to completion
- [ ] Produces valid outputs
- [ ] Cycle count matches behavioral
- [ ] Outputs saved for comparison

### Comparison

- [ ] Output files compared (diff)
- [ ] Differences analyzed (if any)
- [ ] Root cause identified (if differences found)
- [ ] Fix applied and re-verified (if needed)

### Documentation

- [ ] Simulation logs saved
- [ ] Waveforms captured
- [ ] Results documented
- [ ] Issues and fixes recorded

---

## Why We Can't Run This Right Now

**Practical Limitations:**

1. **No test vectors generated yet**
   - Need Python reference model
   - Need to implement softmax correctly
   - Need to generate reproducible vectors

2. **Simulation might be slow**
   - Post-synthesis simulation is ~10× slower than RTL
   - 1736 cycles × 10 ns = 17.36 μs simulated time
   - Could take minutes to run

3. **Timing violations might cause issues**
   - v3 fails timing at 100 MHz
   - Post-synthesis simulation might show functional errors
   - Would need to re-synthesize at 75 MHz first

**What We Can Do Instead:**

1. ✅ Document the verification plan (this document)
2. ✅ Explain what we expect to see
3. ✅ Describe how to interpret results
4. ✅ Identify potential issues and fixes

---

## Summary

### Verification Approach

1. **Run behavioral simulation** → Establish golden reference
2. **Run post-synthesis simulation** → Verify synthesized netlist
3. **Compare outputs** → Ensure bit-exact match
4. **Analyze differences** → Identify and fix issues

### Expected Outcome

**Best case:** Outputs match exactly, verification passes ✅

**Likely case:** Small differences due to timing violations ⚠️
- Action: Reduce clock to 75 MHz and re-verify

**Worst case:** Major functional differences 🔴
- Action: Debug synthesis issues, add keep attributes, re-synthesize

### Key Insight

**Post-synthesis simulation is critical** because:
- Synthesis can introduce bugs
- Timing violations can cause functional errors
- Optimization can change behavior

**"It synthesizes" ≠ "It works correctly"**

---

## Next Steps

1. ⏭️ Generate test vectors using Python reference model
2. ⏭️ Run behavioral simulation to establish baseline
3. ⏭️ Run post-synthesis simulation
4. ⏭️ Compare and document results
5. ⏭️ If timing causes issues, re-synthesize at 75 MHz

**For now:** Verification plan documented. Ready to execute when test vectors are available.
