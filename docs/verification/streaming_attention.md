# Streaming Attention Verification Plan
**Module:** streaming_attention  
**Role:** Verification Engineer  
**Date:** 2026-04-01  
**Status:** Verification Strategy - Phase 1

---

## Purpose

This document defines the verification strategy for the streaming attention accelerator. It specifies test levels, coverage goals, validation methodology, and acceptance criteria.

---

## 1. Verification Hierarchy

### 1.1 Test Levels

```
Level 0: Python Reference Model
  ├─ Floating-point reference (golden model)
  └─ Quantized reference (RTL behavior model)

Level 1: Unit Tests (RTL Components)
  ├─ mac_int8 (MAC unit)
  ├─ dot_product_engine (16-way parallel MAC)
  ├─ softmax_unit (exp + normalize)
  └─ [Future: weighted_sum_engine, memory controllers]

Level 2: Integration Tests (Subsystems)
  ├─ Compute pipeline (Q·K^T)
  ├─ Softmax pipeline
  └─ Output pipeline (A·V)

Level 3: System Tests (Full Attention)
  ├─ Single query attention
  ├─ Full sequence attention (L=8)
  └─ Corner cases (zeros, max values, edge cases)

Level 4: Performance Validation
  ├─ Cycle count verification
  ├─ Resource utilization (synthesis)
  └─ Timing closure (implementation)
```

---

## 2. Unit Test Specifications

### 2.1 MAC Unit (mac_int8)

**Test cases:**
1. Basic positive multiplication: `5 × 3 = 15`
2. Accumulation: `15 + (4 × 2) = 23`
3. Negative operands: `(-5) × 3 = -15`
4. Maximum values: `127 × 127 = 16129`
5. Clear functionality: accumulator resets to 0
6. Enable control: accumulation only when enabled
7. Long accumulation: 64 MACs without overflow

**Acceptance criteria:**
- All test cases pass
- 2-cycle latency verified
- No overflow for 64 INT8×INT8 accumulations
- Clear and enable signals work correctly

**Status:** Testbench created (`tb/unit/tb_mac_int8.v`)

### 2.2 Dot Product Engine (dot_product_engine)

**Test cases:**
1. Simple dot product: `[1,2,3,4] · [1,1,1,1] = 10`
2. Orthogonal vectors: `[1,0,0,0] · [0,1,0,0] = 0`
3. Negative values: `[-1,-2,-3,-4] · [1,2,3,4] = -30`
4. Full-length vectors (D=64): random vectors
5. Maximum values: all elements = 127
6. Pipeline behavior: back-to-back operations

**Acceptance criteria:**
- Correct dot product results (±1 tolerance for rounding)
- Latency: 6 cycles for D=64 (2 pipeline + 4 compute)
- Throughput: 1 dot product per 6 cycles
- Ready/valid handshake works correctly

**Status:** Testbench needed (TODO)

### 2.3 Softmax Unit (softmax_unit)

**Test cases:**
1. Uniform scores: `[1,1,1,1,1,1,1,1]` → `[0.125, 0.125, ...]`
2. One dominant: `[10,0,0,0,0,0,0,0]` → `[~1.0, ~0, ...]`
3. Negative scores: `[-5,-3,-1,0]` → verify normalization
4. Max-subtraction: verify numerical stability
5. Sum to 1.0: verify Σ weights = 1.0 (within tolerance)

**Acceptance criteria:**
- Output weights sum to 1.0 (±0.01 tolerance)
- All weights in range [0, 1]
- Max-subtraction prevents overflow
- Latency: ~22 cycles for L=8

**Status:** Testbench needed (TODO)

---

## 3. Integration Test Specifications

### 3.1 Full Attention (streaming_attention)

**Test cases:**

**Test 1: Identity attention**
- Q = K = V = Identity matrix
- Expected: Output ≈ V (attention focuses on self)

**Test 2: Random inputs**
- Q, K, V = random INT8 matrices
- Compare with Python quantized reference
- Tolerance: ±2 INT8 values (±1.6% for scale=0.01)

**Test 3: Extreme values**
- All elements = 127 (max positive)
- All elements = -128 (max negative)
- Verify no overflow in accumulators

**Test 4: Sparse attention**
- Q, K designed to produce sparse attention weights
- Verify correct weighted sum

**Test 5: Sequential queries**
- Process all L=8 queries
- Verify output matrix shape and values

**Acceptance criteria:**
- Output matches Python reference within ±2 INT8 values
- No overflow or underflow
- Cycle count: 900-1000 cycles for L=8
- All memory accesses valid (no out-of-bounds)

**Status:** Testbench created (`tb/integration/tb_streaming_attention.v`)

---

## 4. Validation Methodology

### 4.1 Golden Reference Model

**Python floating-point model:**
- Implements attention in NumPy (float32)
- No quantization, no approximations
- Used to validate algorithm correctness

**Python quantized model:**
- Matches RTL quantization scheme (INT8/INT32/INT16)
- Matches RTL scaling (right-shift by 3)
- Matches RTL softmax (Q15 fixed-point)
- Used to generate expected RTL outputs

### 4.2 Test Vector Generation

**Process:**
1. Generate random Q, K, V matrices (float32, range [-1, 1])
2. Quantize to INT8 with scale=0.01
3. Run quantized Python model to get expected output
4. Write vectors to text files for Verilog testbench
5. RTL testbench reads vectors and compares outputs

**Files generated:**
- `test_vectors/q_matrix.txt` (512 INT8 values)
- `test_vectors/k_matrix.txt` (512 INT8 values)
- `test_vectors/v_matrix.txt` (512 INT8 values)
- `test_vectors/expected_output.txt` (512 INT8 values)
- `test_vectors/attention_weights.txt` (64 INT16 values, for debug)

### 4.3 Comparison Methodology

**Element-wise comparison:**
```
For each output element i:
  error[i] = |rtl_output[i] - expected[i]|
  if error[i] > tolerance:
    flag as error
```

**Metrics:**
- Max absolute error
- Mean absolute error
- Number of elements exceeding tolerance
- Error rate (percentage)

**Tolerance levels:**
- **Strict:** ±1 INT8 value (0.8% relative error)
- **Acceptable:** ±2 INT8 values (1.6% relative error)
- **Warning:** ±5 INT8 values (4% relative error)
- **Failure:** >5 INT8 values

---

## 5. Coverage Goals

### 5.1 Functional Coverage

**Input space:**
- [ ] All positive values
- [ ] All negative values
- [ ] Mixed positive/negative
- [ ] Zero values
- [ ] Maximum values (±127)
- [ ] Minimum values (near zero)

**Attention patterns:**
- [ ] Uniform attention (all weights equal)
- [ ] Focused attention (one dominant weight)
- [ ] Sparse attention (few non-zero weights)
- [ ] Distributed attention (many similar weights)

**Edge cases:**
- [ ] First query (query_idx = 0)
- [ ] Last query (query_idx = L-1)
- [ ] First element (element_idx = 0)
- [ ] Last element (element_idx = D-1)

### 5.2 Code Coverage

**Target:** 90% line coverage, 80% branch coverage

**Tools:**
- Vivado XSim coverage analysis
- Manual inspection of uncovered paths

**Exclusions:**
- Reset paths (covered by reset test)
- Error conditions (if any)

---

## 6. Performance Validation

### 6.1 Cycle Count Verification

**Predicted:** 912 cycles for L=8 queries

**Measurement:**
- Count cycles from `start` assertion to `done` assertion
- Compare with prediction
- Acceptable range: 900-1000 cycles (±10%)

**Breakdown verification:**
- LOAD_Q: 4 cycles × 8 queries = 32 cycles
- COMPUTE_SCORES: 32 cycles × 8 queries = 256 cycles
- SOFTMAX: 22 cycles × 8 queries = 176 cycles
- COMPUTE_OUTPUT: 32 cycles × 8 queries = 256 cycles
- WRITE_OUTPUT: 4 cycles × 8 queries = 32 cycles
- Overhead: ~160 cycles

### 6.2 Resource Utilization

**Synthesis targets:**
- LUTs: < 10% (< 5,320 / 53,200)
- FFs: < 10% (< 10,640 / 106,400)
- DSP48: < 20% (< 44 / 220)
- BRAM: < 5% (< 7 / 140)

**Measurement:**
- Run Vivado synthesis
- Extract utilization report
- Compare with predictions

### 6.3 Timing Closure

**Target frequency:** 100 MHz (10 ns period)

**Measurement:**
- Run Vivado implementation
- Extract timing report
- Verify worst negative slack (WNS) ≥ 0
- Verify total negative slack (TNS) = 0

**Critical paths to monitor:**
- MAC multiply → accumulate
- Softmax LUT → divider
- Adder tree in dot product

---

## 7. Regression Testing

### 7.1 Test Suite

**Quick regression (< 5 minutes):**
- MAC unit test
- Python reference model test
- Single attention test (1 random vector set)

**Full regression (< 30 minutes):**
- All unit tests
- All integration tests
- 10 random vector sets
- Corner case tests

**Nightly regression:**
- Full regression
- Synthesis
- Timing analysis
- Coverage report

### 7.2 Continuous Integration

**Trigger:** On every commit to main branch

**Steps:**
1. Run Python tests
2. Generate test vectors
3. Run RTL unit tests
4. Run RTL integration tests
5. Generate coverage report
6. Archive waveforms and logs

**Pass criteria:**
- All tests pass
- Coverage ≥ 80%
- No synthesis warnings

---

## 8. Known Issues and Limitations

### 8.1 Current Limitations

1. **Softmax LUT accuracy:** Using simplified approximation, not real exp values
   - **Impact:** May cause larger errors in attention weights
   - **Mitigation:** Replace with proper LUT in next phase

2. **Division approximation:** Using simple fixed-point division
   - **Impact:** May cause rounding errors
   - **Mitigation:** Implement Newton-Raphson refinement

3. **No pipeline optimization:** Sequential processing of queries
   - **Impact:** Lower throughput than possible
   - **Mitigation:** Add query-level pipelining in Phase 2

4. **Fixed sequence length:** L=8 hardcoded
   - **Impact:** Cannot handle variable-length sequences
   - **Mitigation:** Add length parameter in Phase 2

### 8.2 Expected Failures

**Accuracy test may fail initially due to:**
- Softmax LUT approximation
- Quantization error accumulation
- Division rounding

**Action:** Measure actual error, adjust tolerance if needed

---

## 9. Acceptance Criteria

### 9.1 Phase 1 Completion Criteria

**Must have:**
- [x] All RTL modules compile without errors
- [x] Python reference model passes self-tests
- [x] Test vector generation works
- [ ] MAC unit test passes (100% pass rate)
- [ ] Integration test runs (may have accuracy issues)
- [ ] Cycle count within ±20% of prediction

**Should have:**
- [ ] Integration test passes with ±5 INT8 tolerance
- [ ] Cycle count within ±10% of prediction
- [ ] No synthesis errors or critical warnings

**Nice to have:**
- [ ] Integration test passes with ±2 INT8 tolerance
- [ ] Synthesis meets resource targets
- [ ] Timing closure at 100 MHz

### 9.2 Sign-off Checklist

Before proceeding to Phase 2:

- [ ] All unit tests pass
- [ ] Integration test runs successfully
- [ ] Accuracy within acceptable tolerance (±5 INT8)
- [ ] Cycle count measured and documented
- [ ] Synthesis completes successfully
- [ ] Resource utilization documented
- [ ] Timing analysis completed
- [ ] Known issues documented
- [ ] Verification plan reviewed and approved

---

## 10. Next Steps

### 10.1 Immediate Actions (Phase 1 Completion)

1. **Run Python reference model test**
   ```bash
   cd python/reference
   python3 attention.py
   ```

2. **Generate test vectors**
   ```bash
   cd python/verification
   python3 generate_test_vectors.py
   ```

3. **Run MAC unit test**
   ```bash
   cd tb/scripts
   ./run_sim.sh mac
   ```

4. **Run integration test**
   ```bash
   ./run_sim.sh attention
   ```

5. **Analyze results**
   - Check cycle count vs. prediction
   - Measure accuracy vs. Python reference
   - Document any failures

### 10.2 Phase 2 Planning

**If Phase 1 tests pass:**
- Proceed to synthesis and implementation
- Optimize critical paths
- Add missing unit tests (dot product, softmax)

**If Phase 1 tests fail:**
- Debug failures using waveforms
- Fix RTL bugs
- Adjust quantization if needed
- Re-run tests

---

## Assumptions

1. Vivado XSim is available for simulation
2. Python 3.x with NumPy is installed
3. Test vectors fit in memory (512 bytes each)
4. Simulation completes in < 1 ms (1M cycles at 100 MHz)
5. Waveform files are manageable size (< 100 MB)

These assumptions will be validated during test execution.
