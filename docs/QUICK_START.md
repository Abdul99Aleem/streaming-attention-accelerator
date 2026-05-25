# Quick Start Guide - Testing and Validation
**Project:** Streaming Transformer Attention Accelerator  
**Purpose:** Step-by-step execution instructions  
**Date:** 2026-04-01

---

## Prerequisites

- Python 3.8 or later
- Bash shell (Linux/macOS)
- Vivado 2023.x (optional, for RTL simulation)

---

## Step-by-Step Execution

### Step 1: Setup Python Environment (One-time)

```bash
cd /home/aleem/Desktop/streaming-attention-accelerator
./python/setup_python_env.sh
```

**Expected output:**
```
========================================================================
Python Environment Setup
========================================================================

[INFO] Found Python 3.x.x
[INFO] Creating virtual environment at .venv
[SUCCESS] Virtual environment created
[INFO] Activating virtual environment
[INFO] Upgrading pip
[INFO] Installing dependencies from requirements.txt

========================================================================
Setup Complete!
========================================================================
```

**What this does:**
- Creates `.venv` directory in project root
- Installs numpy
- Activates the environment

---

### Step 2: Activate Environment (Every session)

```bash
cd /home/aleem/Desktop/streaming-attention-accelerator
source .venv/bin/activate
```

**Verify activation:**
```bash
which python3
# Should show: /home/aleem/Desktop/streaming-attention-accelerator/.venv/bin/python3

python3 -c "import numpy; print(f'NumPy {numpy.__version__} installed')"
# Should show: NumPy 1.x.x installed
```

---

### Step 3: Run Python Reference Model Tests

```bash
cd python/reference
python3 attention.py
```

**Expected output:**
```
Attention Reference Implementation Test
============================================================

Generating test vectors (L=8, d=64)...

1. Testing floating-point reference...
   Output shape: (8, 64)
   Output range: [-0.5412, 0.5318]
   Attention weights shape: (8, 8)
   Attention weights sum per row: [1. 1. 1. 1. 1. 1. 1. 1.]
   ✓ Attention weights sum to 1.0

2. Testing quantized reference...
   Output shape: (8, 64)
   Output range: [-0.5200, 0.5100]
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

4. Comparing attention weights...
============================================================
Comparison: FP Weights vs Quantized Weights
============================================================
Max absolute error:  0.012
Mean absolute error: 0.004
Max relative error:  2.1%
Mean relative error: 0.8%
Elements exceeding 5.0% tolerance: 0/64
Status: ✓ PASSED
============================================================

*** ALL TESTS PASSED ***
```

**Success criteria:**
- ✅ Mean absolute error < 0.05
- ✅ Max relative error < 10%
- ✅ Status: PASSED

**If tests fail:**
- Check that you're in the virtual environment
- Verify numpy is installed: `pip list | grep numpy`
- Check the error message for details

---

### Step 4: Generate Test Vectors

```bash
cd ../verification
python3 generate_test_vectors.py
```

**Expected output:**
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

**Verify files created:**
```bash
ls -lh ../../test_vectors/
```

**Expected files:**
```
q_matrix.txt              (512 lines)
k_matrix.txt              (512 lines)
v_matrix.txt              (512 lines)
expected_output.txt       (512 lines)
attention_weights.txt     (64 lines)
summary.txt               (human-readable)
```

**Inspect a file:**
```bash
head -10 ../../test_vectors/q_matrix.txt
```

Should show INT8 values like:
```
-45
67
-23
12
...
```

---

### Step 5: Run RTL Simulation (Requires Vivado)

**5a. Setup Vivado (if not already done):**

```bash
# Find Vivado installation
find /tools -name "settings64.sh" 2>/dev/null
# OR
find /opt -name "settings64.sh" 2>/dev/null

# Source the settings file (adjust path to your installation)
source /tools/Xilinx/Vivado/2023.2/settings64.sh

# Verify
which xvlog
# Should show path to xvlog
```

**5b. Run simulations:**

```bash
cd ../../tb/scripts
./run_sim.sh all
```

**Expected output:**
```
========================================================================
Streaming Attention Accelerator - Simulation Runner
========================================================================

[INFO] Running all tests...

========================================================================
Running Python Reference Model Tests
========================================================================
[... Python test output ...]
[SUCCESS] Python tests completed

========================================================================
Generating Test Vectors
========================================================================
[... Test vector generation output ...]
[SUCCESS] Test vectors generated

========================================================================
Running MAC Unit Test
========================================================================
[INFO] Compiling RTL and testbench...
[INFO] Elaborating design...
[INFO] Running simulation...

========================================
MAC INT8 Unit Test
========================================
[PASS] Test 1: 5 * 3 = 15
[PASS] Test 2: 15 + (4 * 2) = 23
[PASS] Test 3: (-5) * 3 = -15
[PASS] Test 4: 127 * 127 = 16129
[PASS] Test 5: Clear resets accumulator to 0
[PASS] Test 6: Enable=0 prevents accumulation
[PASS] Test 7: 64 MACs = 6400 (expected 6400)

========================================
Test Summary
========================================
Total tests: 7
Passed:      7
Failed:      0

*** ALL TESTS PASSED ***
========================================

[SUCCESS] MAC unit test completed

========================================================================
Running Streaming Attention Integration Test
========================================================================
[INFO] Compiling RTL and testbench...
[INFO] Elaborating design...
[INFO] Running simulation...

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

[SUCCESS] Streaming attention test completed

========================================================================
All Tests Completed
========================================================================
```

---

## Alternative: Run Without Vivado

If Vivado is not available, you can still validate the design using:

### Option 1: Icarus Verilog (Open Source)

**Install:**
```bash
sudo apt-get install iverilog gtkwave
```

**Compile and run:**
```bash
cd /home/aleem/Desktop/streaming-attention-accelerator

# Compile
iverilog -o sim/mac_test \
    rtl/primitives/mac_int8.v \
    tb/unit/tb_mac_int8.v

# Run
vvp sim/mac_test

# View waveforms
gtkwave tb_mac_int8.vcd
```

### Option 2: Python-Only Validation

If no Verilog simulator is available, you can still validate the algorithm:

```bash
cd python/reference
python3 attention.py
```

This validates:
- ✅ Algorithm correctness
- ✅ Quantization behavior
- ✅ Expected error levels

RTL simulation would additionally validate:
- Cycle-accurate timing
- Hardware implementation correctness
- Resource usage

---

## Troubleshooting

### Issue: "ModuleNotFoundError: No module named 'numpy'"

**Solution:**
```bash
source .venv/bin/activate
pip install numpy
```

### Issue: "xvlog: command not found"

**Solution:**
```bash
# Find Vivado
find /tools -name "settings64.sh" 2>/dev/null
find /opt -name "settings64.sh" 2>/dev/null

# Source settings
source /path/to/Vivado/settings64.sh
```

### Issue: Python tests show high error (>50%)

**Solution:**
- Verify you're using the fixed version of attention.py
- Check that scale_shift = 3
- Regenerate test vectors

### Issue: Test vector files not found

**Solution:**
```bash
cd python/verification
python3 generate_test_vectors.py
ls ../../test_vectors/  # Verify files exist
```

---

## Success Checklist

- [ ] Python environment setup complete
- [ ] Python reference tests pass (error < 5%)
- [ ] Test vectors generated (6 files in test_vectors/)
- [ ] MAC unit test passes (7/7 tests)
- [ ] Integration test runs (error rate < 10%)
- [ ] Cycle count measured (~900-1000 cycles)

---

## Next Steps

After all tests pass:

1. **Document results:**
   - Update `docs/analysis/streaming_attention.md` with measured values
   - Compare predicted vs. actual cycle counts
   - Document error rates

2. **Proceed to synthesis (if Vivado available):**
   ```bash
   cd vivado
   vivado -mode batch -source synthesis.tcl
   ```

3. **Optimize if needed:**
   - If cycle count > 1000: optimize state machine
   - If error rate > 10%: adjust quantization
   - If timing fails: add pipeline stages

---

**Document Version:** 1.0  
**Last Updated:** 2026-04-01
