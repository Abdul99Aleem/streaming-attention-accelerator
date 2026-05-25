# Testing Methodology and Validation Criteria
**Project:** Streaming Transformer Attention Accelerator  
**Document:** Testing Methodology  
**Date:** 2026-04-01  
**Status:** Complete Reference

---

## Table of Contents

1. [Overview](#overview)
2. [Python Reference Model Testing](#python-reference-model-testing)
3. [Test Vector Generation](#test-vector-generation)
4. [RTL Simulation](#rtl-simulation)
5. [Validation Criteria](#validation-criteria)
6. [Setup Instructions](#setup-instructions)
7. [Troubleshooting](#troubleshooting)

---

## 1. Overview

This document describes the complete testing methodology for the streaming attention accelerator, including:
- How reference models are validated
- Criteria for test generation and acceptance
- RTL simulation procedures
- Error tolerance specifications

### Testing Hierarchy

```
Level 0: Python Reference Model Validation
  ├─ Self-consistency checks
  ├─ Mathematical property verification
  └─ Quantization error analysis

Level 1: Test Vector Generation
  ├─ Random input generation
  ├─ Golden output computation
  └─ File format conversion

Level 2: RTL Unit Testing
  ├─ Component-level verification
  └─ Functional correctness

Level 3: RTL Integration Testing
  ├─ System-level verification
  └─ Accuracy validation against Python reference
```

---

## 2. Python Reference Model Testing

### 2.1 Purpose

The Python reference model serves as the **golden reference** for RTL validation. It must be validated first to ensure correctness before generating test vectors.

### 2.2 Test Components

#### A. Floating-Point Reference (`AttentionReference`)

**Purpose:** Validate the attention algorithm implementation

**Test Cases:**
1. **Output shape verification**
   - Input: Q, K, V matrices (L×D)
   - Expected: Output shape = (L, D)
   - Criterion: Exact shape match

2. **Attention weights properties**
   - Expected: Each row sums to 1.0
   - Criterion: `|sum - 1.0| < 1e-6`
   - Expected: All values in [0, 1]
   - Criterion: `0 ≤ weights[i,j] ≤ 1`

3. **Numerical stability**
   - Test with extreme values (all max, all min)
   - Expected: No NaN or Inf in outputs
   - Criterion: `np.isfinite(output).all()`

**Validation Criteria:**
```python
# Attention weights must sum to 1.0 per row
assert np.allclose(weights.sum(axis=1), 1.0, atol=1e-6)

# All weights must be in valid range
assert np.all((weights >= 0) & (weights <= 1))

# Output must be finite
assert np.isfinite(output).all()
```

#### B. Quantized Reference (`QuantizedAttentionReference`)

**Purpose:** Match RTL quantization behavior exactly

**Quantization Scheme:**
```
Inputs (Q, K, V):     INT8,  scale = 0.01
Dot product scores:   INT32, accumulated from INT8×INT8
Scaled scores:        INT32, right-shifted by 3 (÷8 for √64)
Attention weights:    INT16, Q15 fixed-point [0, 32767] → [0, 1]
Output accumulator:   INT32, accumulated from INT16×INT8
Final output:         INT8,  requantized with scale = 0.01
```

**Test Cases:**
1. **Quantization round-trip**
   - Quantize float → INT8 → dequantize
   - Expected error: ±0.5 LSB = ±0.005 (for scale=0.01)
   - Criterion: `|reconstructed - original| ≤ 0.005`

2. **Dot product accumulation**
   - Compute Q·K^T with INT8 inputs, INT32 accumulator
   - Expected: No overflow for 64 INT8×INT8 products
   - Max value: 64 × 127 × 127 = 1,032,576 (fits in INT32)
   - Criterion: `|result| < 2^31`

3. **Softmax normalization**
   - Apply softmax to INT32 scores
   - Convert to INT16 Q15 format
   - Expected: Weights sum to ~1.0 (within Q15 precision)
   - Criterion: `|sum - 1.0| < 0.01` (Q15 resolution = 1/32768 ≈ 0.00003)

4. **Output requantization**
   - Accumulate INT16×INT8 products (64 times)
   - Right-shift by 15 to undo Q15 scaling
   - Clip to INT8 range [-128, 127]
   - Criterion: No overflow, valid INT8 range

**Validation Criteria:**
```python
# Attention weights sum (Q15 precision)
weights_sum = attention_weights.sum(axis=1)
assert np.allclose(weights_sum, 1.0, atol=0.01)

# Output range check
assert np.all((output_int8 >= -128) & (output_int8 <= 127))

# Accumulator overflow check
assert np.all(np.abs(output_acc) < 2**31)
```

### 2.3 Comparison: Floating-Point vs. Quantized

**Purpose:** Measure quantization error to set RTL tolerance

**Error Metrics:**
```python
abs_error = |output_fp - output_quant|
rel_error = abs_error / (|output_fp| + epsilon)

max_abs_error = max(abs_error)
mean_abs_error = mean(abs_error)
max_rel_error = max(rel_error)
mean_rel_error = mean(rel_error)
```

**Expected Error Levels:**

| Metric | Expected | Acceptable | Warning |
|--------|----------|------------|---------|
| Max absolute error | < 0.05 | < 0.10 | < 0.20 |
| Mean absolute error | < 0.02 | < 0.05 | < 0.10 |
| Max relative error | < 10% | < 20% | < 50% |
| Mean relative error | < 5% | < 10% | < 20% |

**Note:** High relative errors can occur for values near zero (division by small numbers). Focus on absolute error for small values.

**Acceptance Criteria:**
- Mean absolute error < 0.05 (5% of typical value range [-1, 1])
- Max absolute error < 0.20 (20% of range)
- No NaN or Inf values
- Attention weights sum to 1.0 within 1% tolerance

### 2.4 Running Python Tests

**Command:**
```bash
cd /home/aleem/Desktop/streaming-attention-accelerator
source .venv/bin/activate
cd python/reference
python3 attention.py
```

**Expected Output:**
```
Attention Reference Implementation Test
============================================================

Generating test vectors (L=8, d=64)...

1. Testing floating-point reference...
   Output shape: (8, 64)
   Output range: [-0.54, 0.53]
   Attention weights shape: (8, 8)
   Attention weights sum per row: [1. 1. 1. 1. 1. 1. 1. 1.]
   ✓ Attention weights sum to 1.0

2. Testing quantized reference...
   Output shape: (8, 64)
   Output range: [-0.52, 0.51]
   Attention weights shape: (8, 8)
   Attention weights sum per row: [1.00 1.00 1.00 1.00 1.00 1.00 1.00 1.00]

3. Comparing floating-point vs quantized...
============================================================
Comparison: Floating-point vs Quantized
============================================================
Max absolute error:  0.048
Mean absolute error: 0.019
Max relative error:  8.2%
Mean relative error: 3.1%
Elements exceeding 5.0% tolerance: 45/512
Status: ✓ PASSED
============================================================

*** ALL TESTS PASSED ***
```

**Interpretation:**
- **Max absolute error ~0.05:** Acceptable for INT8 quantization
- **Mean absolute error ~0.02:** Good, indicates most values are accurate
- **Max relative error ~10%:** Expected for values near zero
- **Mean relative error ~5%:** Acceptable quantization error
- **Elements exceeding 5%:** Should be < 20% of total (< 102/512)

---

## 3. Test Vector Generation

### 3.1 Purpose

Generate input matrices (Q, K, V) and expected outputs for RTL testbenches.

### 3.2 Generation Process

**Step 1: Random Input Generation**
```python
np.random.seed(42)  # Fixed seed for reproducibility
Q = np.random.uniform(-1.0, 1.0, (L, D))  # Range [-1, 1]
K = np.random.uniform(-1.0, 1.0, (L, D))
V = np.random.uniform(-1.0, 1.0, (L, D))
```

**Rationale:**
- Uniform distribution covers full input range
- Range [-1, 1] is typical for normalized embeddings
- Fixed seed ensures reproducible tests

**Step 2: Quantization to INT8**
```python
scale = 0.01
Q_int8 = np.clip(np.round(Q / scale), -128, 127).astype(np.int8)
K_int8 = np.clip(np.round(K / scale), -128, 127).astype(np.int8)
V_int8 = np.clip(np.round(V / scale), -128, 127).astype(np.int8)
```

**Rationale:**
- Scale = 0.01 maps [-1, 1] → [-100, 100] in INT8
- Leaves headroom for values outside [-1, 1]
- Clipping prevents overflow

**Step 3: Compute Expected Output**
```python
attn_ref = QuantizedAttentionReference(
    d_k=64,
    weight_scale=0.01,
    activation_scale=0.01,
    output_scale=0.01,
    scale_shift=3  # √64 = 8 = 2^3
)
output_fp, weights_fp = attn_ref.forward(Q, K, V)
output_int8 = np.clip(np.round(output_fp / scale), -128, 127).astype(np.int8)
```

**Rationale:**
- Use quantized reference (not floating-point) to match RTL behavior
- Requantize output to INT8 for comparison
- Store both output and attention weights for debugging

**Step 4: Write to Files**
```python
# Row-major order: element [i,j] at index i*D + j
for i in range(L):
    for j in range(D):
        f.write(f"{matrix[i,j]}\n")
```

**File Format:**
- One integer per line
- Signed decimal format (e.g., "-45", "127")
- Row-major order (row 0 elements, then row 1, etc.)
- Total lines: L × D = 8 × 64 = 512

**Output Files:**
```
test_vectors/
├── q_matrix.txt           # 512 INT8 values
├── k_matrix.txt           # 512 INT8 values
├── v_matrix.txt           # 512 INT8 values
├── expected_output.txt    # 512 INT8 values
├── attention_weights.txt  # 64 INT16 values (for debugging)
└── summary.txt            # Human-readable summary
```

### 3.3 Running Test Vector Generation

**Command:**
```bash
cd /home/aleem/Desktop/streaming-attention-accelerator
source .venv/bin/activate
cd python/verification
python3 generate_test_vectors.py
```

**Expected Output:**
```
============================================================
Test Vector Generation for RTL Testbench
============================================================

Parameters:
  Sequence length (L): 8
  Embedding dim (D):   64
  Quantization scale:  0.01
  Random seed:         42

Generating random test vectors...
  Q: (8, 64), range [-0.998, 0.996]
  K: (8, 64), range [-0.992, 0.998]
  V: (8, 64), range [-0.999, 0.997]

Quantizing to INT8...
  Q_int8: range [-100, 100]
  K_int8: range [-99, 100]
  V_int8: range [-100, 100]

Computing expected output using quantized reference model...
  Output: (8, 64), range [-0.52, 0.51]
  Attention weights: (8, 8)
  Attention weights sum per row: [1.00 1.00 1.00 1.00 1.00 1.00 1.00 1.00]
  Output_int8: range [-52, 51]

Writing test vectors to files...
  Written test_vectors/q_matrix.txt: 8×64 = 512 elements
  Written test_vectors/k_matrix.txt: 8×64 = 512 elements
  Written test_vectors/v_matrix.txt: 8×64 = 512 elements
  Written test_vectors/expected_output.txt: 8×64 = 512 elements
  Written test_vectors/attention_weights.txt (for debugging)
  Written test_vectors/summary.txt

============================================================
Test vector generation completed successfully!
============================================================
```

**Validation:**
- Check that all files exist
- Verify file sizes: 512 lines for matrices, 64 for weights
- Inspect summary.txt for sanity checks

---

## 4. RTL Simulation

### 4.1 Simulation Tools

**Primary Tool: Vivado XSim**
- Industry-standard Verilog simulator
- Part of Xilinx Vivado Design Suite
- Free with WebPACK edition

**Alternative Tools (if Vivado unavailable):**
- Icarus Verilog (iverilog) - Open source
- Verilator - Fast, open source
- ModelSim - Commercial

### 4.2 Vivado XSim Setup

**Installation:**
1. Download Vivado from Xilinx website
2. Install Vivado WebPACK (free edition)
3. Source settings file:
   ```bash
   source /tools/Xilinx/Vivado/2023.2/settings64.sh
   ```
   (Adjust path to your installation)

**Verify Installation:**
```bash
which xvlog
which xelab
which xsim
```

Should return paths to Vivado binaries.

### 4.3 Simulation Process

**Step 1: Compilation**
```bash
xvlog --sv \
    rtl/primitives/mac_int8.v \
    rtl/compute/dot_product_engine.v \
    rtl/softmax/softmax_unit.v \
    rtl/attention/streaming_attention.v \
    tb/integration/tb_streaming_attention.v
```

**Purpose:** Parse Verilog files, check syntax, build simulation database

**Expected Output:**
```
Parsing design file 'rtl/primitives/mac_int8.v'
Parsing design file 'rtl/compute/dot_product_engine.v'
...
Completed static elaboration
```

**Step 2: Elaboration**
```bash
xelab -debug typical tb_streaming_attention -s attention_sim
```

**Purpose:** Link modules, resolve hierarchy, create executable simulation

**Expected Output:**
```
Elaborating module <tb_streaming_attention>
Elaborating module <streaming_attention>
...
Simulation snapshot created: attention_sim
```

**Step 3: Simulation**
```bash
xsim attention_sim -runall
```

**Purpose:** Execute testbench, generate waveforms, report results

**Expected Output:**
```
========================================
Streaming Attention Integration Test
========================================
Parameters:
  L (sequence length):    8
  D (embedding dim):      64
  TILE_WIDTH:             16
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
Computation completed in 945 cycles
Expected cycles: ~912 (predicted)
Cycle efficiency: 96.5%

Sample output (first row, first 8 elements):
    -12   45  -23   67  -8   34  -56   12 ...

Comparing outputs with expected values...

========================================
Output Comparison Results
========================================
Total elements:  512
Errors (>2):     18
Max error:       3
Average error:   0.8
Error rate:      3.5%

*** MOSTLY CORRECT (<10% errors) ***
========================================

Performance Summary
========================================
Latency:         945 cycles
Time:            9.45 μs
Throughput:      105,820 attentions/sec
========================================
```

### 4.4 Waveform Analysis

**Generated Files:**
- `tb_streaming_attention.vcd` - Value Change Dump (waveform data)

**Viewing Waveforms:**
```bash
# Using GTKWave (open source)
gtkwave tb_streaming_attention.vcd

# Using Vivado GUI
vivado -mode gui
# File → Open Waveform Database → select .vcd file
```

**Key Signals to Monitor:**
- `clk`, `rst_n` - Clock and reset
- `state` - State machine progression
- `q_addr`, `k_addr`, `v_addr` - Memory access patterns
- `scores` - Attention scores after Q·K^T
- `attention_weights` - Softmax output
- `output_acc` - Output accumulator
- `done` - Completion signal

---

## 5. Validation Criteria

### 5.1 Python Reference Model

**Pass Criteria:**
- ✅ Attention weights sum to 1.0 (±0.01)
- ✅ All weights in range [0, 1]
- ✅ Mean absolute error < 0.05 (FP vs. Quantized)
- ✅ No NaN or Inf values

**Fail Criteria:**
- ❌ Attention weights sum deviates > 0.05 from 1.0
- ❌ Mean absolute error > 0.10
- ❌ Any NaN or Inf values

### 5.2 RTL Simulation

**Pass Criteria:**
- ✅ Simulation completes without errors
- ✅ Cycle count within ±20% of prediction (730-1095 cycles)
- ✅ Error rate < 10% (< 51 elements with error > 2)
- ✅ Max error ≤ 5 INT8 values
- ✅ Mean error ≤ 2 INT8 values

**Acceptable Criteria:**
- ⚠️ Cycle count within ±30% of prediction
- ⚠️ Error rate < 20% (< 102 elements)
- ⚠️ Max error ≤ 10 INT8 values
- ⚠️ Mean error ≤ 3 INT8 values

**Fail Criteria:**
- ❌ Simulation hangs or crashes
- ❌ Cycle count > 1500 (>64% deviation)
- ❌ Error rate > 20%
- ❌ Max error > 10 INT8 values
- ❌ Any memory access violations

### 5.3 Error Tolerance Rationale

**Why ±2 INT8 values?**
- Quantization scale = 0.01
- ±2 INT8 = ±0.02 in float
- Represents ±2% error for values in [-1, 1]
- Accounts for:
  - Input quantization: ±0.5 LSB
  - Dot product rounding: ±0.5 LSB per MAC
  - Softmax approximation: ±0.1%
  - Output requantization: ±0.5 LSB

**Why 10% error rate?**
- Some elements will have larger errors due to:
  - Values near zero (high relative error)
  - Softmax LUT approximation
  - Accumulated rounding
- 10% = 51 out of 512 elements
- Indicates systematic correctness with acceptable outliers

---

## 6. Setup Instructions

### 6.1 Complete Setup Procedure

**Step 1: Python Environment**
```bash
cd /home/aleem/Desktop/streaming-attention-accelerator
./python/setup_python_env.sh
```

This creates `.venv` and installs numpy.

**Step 2: Activate Environment**
```bash
source .venv/bin/activate
```

**Step 3: Run Python Tests**
```bash
cd python/reference
python3 attention.py
```

Verify all tests pass.

**Step 4: Generate Test Vectors**
```bash
cd ../verification
python3 generate_test_vectors.py
```

Verify `test_vectors/` directory is created with 5 files.

**Step 5: Setup Vivado (if available)**
```bash
source /path/to/Vivado/settings64.sh
```

**Step 6: Run RTL Simulation**
```bash
cd ../../tb/scripts
./run_sim.sh all
```

### 6.2 Quick Start (All-in-One)

```bash
cd /home/aleem/Desktop/streaming-attention-accelerator

# Setup Python
./python/setup_python_env.sh
source .venv/bin/activate

# Run all tests
python3 python/reference/attention.py
python3 python/verification/generate_test_vectors.py

# Run RTL simulation (requires Vivado)
# source /path/to/Vivado/settings64.sh
# ./tb/scripts/run_sim.sh all
```

---

## 7. Troubleshooting

### 7.1 Python Issues

**Problem:** `ModuleNotFoundError: No module named 'numpy'`

**Solution:**
```bash
source .venv/bin/activate
pip install numpy
```

**Problem:** High quantization error (>50%)

**Solution:**
- Check that softmax scaling is correct
- Verify scale_shift = 3 (for √64 = 8)
- Ensure activation_scale = 0.01

### 7.2 Test Vector Issues

**Problem:** Test vector files not found

**Solution:**
```bash
cd python/verification
python3 generate_test_vectors.py
ls ../../test_vectors/  # Verify files exist
```

**Problem:** Invalid values in test vectors

**Solution:**
- Check that quantization scale matches (0.01)
- Verify INT8 range [-128, 127]
- Regenerate vectors with fixed seed

### 7.3 RTL Simulation Issues

**Problem:** `xvlog: command not found`

**Solution:**
```bash
# Find Vivado installation
find /tools -name "settings64.sh" 2>/dev/null
# Or
find /opt -name "settings64.sh" 2>/dev/null

# Source the settings file
source /path/to/Vivado/settings64.sh
```

**Problem:** Compilation errors

**Solution:**
- Check Verilog syntax
- Verify all files are in correct directories
- Check for missing module instantiations

**Problem:** Simulation hangs

**Solution:**
- Check for infinite loops in state machine
- Verify ready/valid handshakes
- Add timeout watchdog (already in testbench)
- View waveforms to identify stuck state

**Problem:** High error rate (>20%)

**Solution:**
- Verify test vectors are correct
- Check softmax LUT values
- Verify scaling factors match Python reference
- Debug using waveforms

---

## 8. Summary

### Testing Workflow

```
1. Setup Python Environment
   └─> ./python/setup_python_env.sh

2. Validate Python Reference
   └─> python3 python/reference/attention.py
       ├─> Pass: Mean error < 5%
       └─> Fail: Fix quantization bugs

3. Generate Test Vectors
   └─> python3 python/verification/generate_test_vectors.py
       └─> Creates test_vectors/*.txt

4. Run RTL Simulation
   └─> ./tb/scripts/run_sim.sh all
       ├─> Pass: Error rate < 10%, cycles ~912
       └─> Fail: Debug with waveforms

5. Analyze Results
   └─> Compare cycle count, error metrics
       └─> Document in analysis file
```

### Success Criteria Summary

| Test Level | Pass Criteria |
|------------|---------------|
| Python FP | Weights sum to 1.0, no NaN/Inf |
| Python Quantized | Mean error < 5% vs. FP |
| Test Vectors | 512 elements per file, valid INT8 range |
| RTL Simulation | Error rate < 10%, cycles 730-1095 |

### Next Steps After Validation

1. **If all tests pass:**
   - Proceed to Vivado synthesis
   - Measure actual resource utilization
   - Verify timing closure at 100 MHz

2. **If tests fail:**
   - Analyze waveforms
   - Fix RTL bugs
   - Adjust quantization if needed
   - Re-run tests

---

**Document Version:** 1.0  
**Last Updated:** 2026-04-01  
**Status:** Complete
