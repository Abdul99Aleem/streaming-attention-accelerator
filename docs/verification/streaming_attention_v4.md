# Tiled Streaming Attention - Verification Plan
**Module:** streaming_attention_v4  
**Date:** 2026-04-03  
**Purpose:** Comprehensive verification strategy and test plan

---

## Verification Overview

**Objective:** Validate that streaming_attention_v4 correctly implements tiled attention computation with 5.6× speedup over v3.

**Verification Levels:**
1. **Unit-level:** Individual components (MAC array, adder tree)
2. **Module-level:** Complete v4 module functionality
3. **Integration-level:** Comparison with Python reference
4. **Performance-level:** Cycle count and resource validation

---

## 1. Verification Strategy

### 1.1 Verification Methodology

**Approach:** Directed testing with self-checking testbenches

**Test Flow:**
```
1. Generate test vectors (Python reference model)
2. Load vectors into testbench memories
3. Run RTL simulation
4. Compare outputs element-by-element
5. Measure cycle count and validate timing
6. Report pass/fail with detailed metrics
```

### 1.2 Coverage Goals

**Functional Coverage:**
- [ ] All state machine states reached
- [ ] All state transitions exercised
- [ ] All tile boundaries tested
- [ ] All query/key/value combinations tested
- [ ] Edge cases (first/last tile, first/last query)

**Code Coverage:**
- [ ] Line coverage: >95%
- [ ] Branch coverage: >90%
- [ ] FSM coverage: 100%
- [ ] Toggle coverage: >80%

**Performance Coverage:**
- [ ] Cycle count within ±10% of prediction
- [ ] Memory bandwidth utilization measured
- [ ] Critical path timing verified

---

## 2. Test Cases

### 2.1 Functional Test Cases

**Test 1: Basic Functionality**
- **Purpose:** Verify correct attention computation
- **Input:** Random Q, K, V matrices (L=8, D=64)
- **Expected:** Output matches Python reference within ±10 INT8
- **Success Criteria:** Error rate <20%

**Test 2: Uniform Inputs**
- **Purpose:** Verify tile processing with simple data
- **Input:** All elements = 1
- **Expected:** Predictable output values
- **Success Criteria:** Exact match with hand calculation

**Test 3: Zero Inputs**
- **Purpose:** Verify handling of zero matrices
- **Input:** Q=0, K=0, V=0
- **Expected:** Output = 0
- **Success Criteria:** All outputs exactly 0

**Test 4: Maximum Values**
- **Purpose:** Verify no overflow in accumulation
- **Input:** All elements = 127 (max INT8)
- **Expected:** No overflow, correct saturation
- **Success Criteria:** No X values, results within valid range

**Test 5: Negative Values**
- **Purpose:** Verify signed arithmetic
- **Input:** Mix of positive and negative values
- **Expected:** Correct signed computation
- **Success Criteria:** Matches Python reference

**Test 6: Tile Boundaries**
- **Purpose:** Verify correct tile alignment
- **Input:** Patterns that change at tile boundaries
- **Expected:** No artifacts at boundaries
- **Success Criteria:** Smooth transitions between tiles

**Test 7: First Query**
- **Purpose:** Verify initialization
- **Input:** Standard test vectors
- **Expected:** Correct output for query 0
- **Success Criteria:** Matches reference for first query

**Test 8: Last Query**
- **Purpose:** Verify completion
- **Input:** Standard test vectors
- **Expected:** Correct output for query L-1, done asserted
- **Success Criteria:** Matches reference, done=1

**Test 9: Softmax Edge Cases**
- **Purpose:** Verify softmax with extreme scores
- **Input:** Very large score differences
- **Expected:** Proper softmax normalization
- **Success Criteria:** Weights sum to ~1.0

**Test 10: Back-to-Back Operations**
- **Purpose:** Verify module can restart immediately
- **Input:** Two consecutive attention computations
- **Expected:** Both complete correctly
- **Success Criteria:** Both outputs match reference

### 2.2 Performance Test Cases

**Test P1: Cycle Count Measurement**
- **Purpose:** Validate predicted cycle count
- **Input:** Standard test vectors (L=8, D=64)
- **Expected:** 1,752 cycles ±10%
- **Success Criteria:** Measured within [1,577, 1,927] cycles

**Test P2: Memory Bandwidth**
- **Purpose:** Verify memory access patterns
- **Input:** Standard test vectors
- **Expected:** No memory conflicts, efficient access
- **Success Criteria:** All reads/writes complete without stalls

**Test P3: Pipeline Efficiency**
- **Purpose:** Measure MAC array utilization
- **Input:** Standard test vectors
- **Expected:** >80% MAC utilization during compute phases
- **Success Criteria:** MACs active for expected cycles

### 2.3 Corner Cases

**Test C1: Single Query (L=1)**
- **Purpose:** Verify minimum sequence length
- **Input:** L=1, D=64
- **Expected:** Correct computation, no hangs
- **Success Criteria:** Completes in ~219 cycles

**Test C2: Minimum Dimension (D=16)**
- **Purpose:** Verify minimum embedding dimension
- **Input:** L=8, D=16 (1 tile)
- **Expected:** Correct computation with single tile
- **Success Criteria:** Matches reference

**Test C3: Maximum Supported (L=16, D=128)**
- **Purpose:** Verify scalability
- **Input:** L=16, D=128
- **Expected:** Correct computation, no overflow
- **Success Criteria:** Matches reference, completes in ~7,000 cycles

---

## 3. Testbench Architecture

### 3.1 Testbench Structure

```verilog
module tb_streaming_attention_v4;
    // Parameters
    parameter CLK_PERIOD = 10;
    parameter L = 8;
    parameter D = 64;
    parameter TILE_WIDTH = 16;

    // DUT signals
    reg clk, rst_n, start;
    wire done, busy;
    
    // Memory interfaces (128-bit wide)
    wire [9:0] q_addr, k_addr, v_addr, out_addr;
    wire q_rd_en, k_rd_en, v_rd_en, out_wr_en;
    reg [127:0] q_data, k_data, v_data;
    wire [127:0] out_data;
    
    // Memory arrays
    reg [7:0] q_mem [0:L*D-1];
    reg [7:0] k_mem [0:L*D-1];
    reg [7:0] v_mem [0:L*D-1];
    reg [7:0] out_mem [0:L*D-1];
    reg [7:0] expected_out [0:L*D-1];
    
    // DUT instantiation
    streaming_attention_v4 #(
        .L(L),
        .D(D),
        .TILE_WIDTH(TILE_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .busy(busy),
        .q_addr(q_addr),
        .q_rd_en(q_rd_en),
        .q_data(q_data),
        // ... other ports
    );
    
    // Memory read logic (handles 128-bit reads)
    always @(posedge clk) begin
        if (q_rd_en) begin
            for (i = 0; i < TILE_WIDTH; i = i + 1) begin
                q_data[i*8 +: 8] <= q_mem[q_addr + i];
            end
        end
    end
    
    // Memory write logic (handles 128-bit writes)
    always @(posedge clk) begin
        if (out_wr_en) begin
            for (i = 0; i < TILE_WIDTH; i = i + 1) begin
                out_mem[out_addr + i] <= out_data[i*8 +: 8];
            end
        end
    end
    
    // Test execution
    initial begin
        reset_dut();
        load_test_vectors();
        run_attention();
        compare_outputs();
        measure_performance();
        report_results();
        $finish;
    end
endmodule
```

### 3.2 Key Testbench Features

**Memory Model:**
- 128-bit wide interfaces (16 INT8 elements per access)
- Tile-aligned addressing
- 1-cycle read latency (matches BRAM)

**Checking:**
- Element-by-element comparison with Python reference
- Error metrics: max error, mean error, error rate
- Cycle count measurement
- State machine coverage tracking

**Reporting:**
- Pass/fail status for each test
- Detailed error analysis
- Performance metrics
- Waveform generation for debugging

---

## 4. Verification Checklist

### 4.1 Pre-Simulation Checks

- [ ] All test vectors generated
- [ ] Testbench compiles without errors
- [ ] DUT compiles without errors
- [ ] Memory interfaces correctly connected
- [ ] Clock and reset properly configured

### 4.2 Simulation Checks

- [ ] Simulation completes without hangs
- [ ] No X values in outputs
- [ ] All state transitions occur
- [ ] Memory accesses are tile-aligned
- [ ] Cycle count measured accurately

### 4.3 Post-Simulation Checks

- [ ] Output matches reference within tolerance
- [ ] Cycle count within ±10% of prediction
- [ ] No timing violations
- [ ] All test cases pass
- [ ] Coverage goals met

---

## 5. Expected Results

### 5.1 Functional Correctness

**Success Criteria:**
```
Max error:       <10 INT8 values
Mean error:      <3 INT8 values
Error rate:      <20% of elements
Pass rate:       100% of test cases
```

**Comparison with v3:**
| Metric | v3 | v4 | Status |
|--------|----|----|--------|
| Algorithm | Proper softmax | Proper softmax | Same |
| Accuracy | Target <20% error | Target <20% error | Same |
| Correctness | Validated | To be validated | TBD |

### 5.2 Performance Metrics

**Cycle Count:**
```
Predicted:  1,752 cycles
Tolerance:  ±10% (1,577 to 1,927 cycles)
Status:     To be measured
```

**Timing:**
```
Clock period:   10 ns (100 MHz)
Critical path:  <9 ns (predicted)
Slack:          >1 ns (10% margin)
Status:         To be verified in synthesis
```

**Resource Usage:**
```
LUTs:    ~4,000 (7.5% predicted)
FFs:     ~5,000 (4.7% predicted)
DSP48:   16 (7.3% predicted)
BRAM:    5 (3.6% predicted)
Status:  To be measured in synthesis
```

---

## 6. Debug Strategy

### 6.1 Common Issues and Solutions

**Issue 1: Incorrect Output Values**
- **Symptom:** Output doesn't match reference
- **Debug Steps:**
  1. Check softmax weights (should sum to ~1.0)
  2. Verify tile loading (check q_tile, k_tile, v_tile)
  3. Check MAC array outputs
  4. Verify adder tree summation
  5. Check output scaling (>>> 15)
- **Tools:** Waveform viewer, signal probes

**Issue 2: Wrong Cycle Count**
- **Symptom:** Takes more/fewer cycles than predicted
- **Debug Steps:**
  1. Check state machine transitions
  2. Verify tile_idx increments correctly
  3. Check for extra wait states
  4. Verify softmax timing (should be 19 cycles)
- **Tools:** State machine trace, cycle counter

**Issue 3: Hangs or Timeouts**
- **Symptom:** Simulation doesn't complete
- **Debug Steps:**
  1. Check for infinite loops in state machine
  2. Verify done signal assertion
  3. Check counter overflow
  4. Verify all state transitions have exit conditions
- **Tools:** State machine trace, timeout watchdog

**Issue 4: X Values in Output**
- **Symptom:** Undefined values in results
- **Debug Steps:**
  1. Check for uninitialized registers
  2. Verify memory read timing
  3. Check for combinational loops
  4. Verify reset behavior
- **Tools:** X-propagation analysis, waveforms

### 6.2 Debugging Tools

**Waveform Analysis:**
```tcl
# Add key signals to waveform
add wave -group "State Machine" /tb/dut/state
add wave -group "Counters" /tb/dut/query_idx
add wave -group "Counters" /tb/dut/key_idx
add wave -group "Counters" /tb/dut/tile_idx
add wave -group "MAC Array" /tb/dut/mac_out[*]
add wave -group "Adder Tree" /tb/dut/sum_final
add wave -group "Scores" /tb/dut/scores[*]
add wave -group "Softmax" /tb/dut/attention_weights[*]
```

**Assertions:**
```verilog
// Check tile_idx doesn't exceed bounds
assert property (@(posedge clk) tile_idx < NUM_TILES);

// Check state machine doesn't hang
assert property (@(posedge clk) 
    (state != IDLE) |-> ##[1:10000] (state == IDLE));

// Check softmax weights sum to ~1.0
property softmax_sum;
    @(posedge clk) softmax_valid |->
        (sum_weights >= 32500 && sum_weights <= 33000);
endproperty
```

---

## 7. Regression Testing

### 7.1 Regression Test Suite

**Quick Regression (5 minutes):**
- Test 1: Basic functionality
- Test P1: Cycle count
- Test C1: Single query

**Full Regression (30 minutes):**
- All 10 functional tests
- All 3 performance tests
- All 3 corner case tests

**Nightly Regression:**
- Full regression
- Extended corner cases (L=32, D=256)
- Random test generation (100 iterations)

### 7.2 Regression Criteria

**Pass Criteria:**
- All tests pass
- No new warnings or errors
- Performance within tolerance
- Coverage goals maintained

**Fail Criteria:**
- Any test fails
- Cycle count regression >10%
- New X values appear
- Coverage drops below goals

---

## 8. Sign-Off Criteria

### 8.1 Functional Sign-Off

- [ ] All functional tests pass (10/10)
- [ ] All corner cases pass (3/3)
- [ ] Output matches reference (<20% error)
- [ ] No X values in outputs
- [ ] State machine coverage 100%

### 8.2 Performance Sign-Off

- [ ] Cycle count within ±10% (1,577-1,927 cycles)
- [ ] Memory bandwidth sufficient
- [ ] No timing violations in simulation
- [ ] Performance tests pass (3/3)

### 8.3 Quality Sign-Off

- [ ] Code coverage >95%
- [ ] No lint warnings
- [ ] All assertions pass
- [ ] Waveforms reviewed and clean
- [ ] Documentation complete

---

## 9. Comparison with v3

### 9.1 Verification Differences

| Aspect | v3 | v4 | Notes |
|--------|----|----|-------|
| Memory interface | 8-bit | 128-bit | v4 requires tile-aware testbench |
| Cycle count | 9,824 | 1,752 | v4 should be 5.6× faster |
| Test complexity | Simple | Moderate | v4 has tile boundaries to test |
| Debug difficulty | Low | Medium | v4 has parallel MAC array |

### 9.2 Reusable Components

**From v3:**
- ✓ Softmax unit (softmax_unit_v2)
- ✓ Test vector generation (Python)
- ✓ Error comparison logic
- ✓ Cycle counting methodology

**New for v4:**
- MAC array testbench
- Tile-aligned memory model
- 128-bit interface handling
- Parallel computation verification

---

## 10. Risk Assessment

### 10.1 Verification Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Tile boundary bugs | Medium | High | Dedicated boundary tests |
| MAC array timing | Low | High | Waveform analysis |
| Memory interface bugs | Medium | High | Thorough interface testing |
| State machine hangs | Low | High | Timeout watchdog |
| Incorrect cycle count | Medium | Medium | Detailed state trace |

### 10.2 Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Debug takes longer | Medium | Medium | Allocate extra time |
| Test vectors incomplete | Low | High | Generate early |
| Simulation too slow | Low | Medium | Use optimized simulator |

---

## 11. Success Metrics

### 11.1 Quantitative Metrics

```
Functional correctness:  100% test pass rate
Performance:             Cycle count within ±10%
Quality:                 >95% code coverage
Efficiency:              <2 hours debug time per bug
```

### 11.2 Qualitative Metrics

```
Code quality:            Clean, well-commented
Debuggability:           Easy to trace issues
Maintainability:         Clear structure
Confidence:              High confidence in correctness
```

---

## Conclusion

**Verification Approach:** Comprehensive directed testing with self-checking testbenches

**Key Focus Areas:**
1. Tile boundary correctness
2. Parallel MAC array functionality
3. Cycle count validation
4. Memory interface correctness

**Expected Outcome:** v4 passes all tests with 5.6× speedup over v3

**Next Steps:**
1. Create/update testbench (tb_streaming_attention_v4.v)
2. Run simulation
3. Measure and compare results
4. Update analysis document with measured values

---

**Status:** Verification plan complete  
**Next Action:** Create testbench and run simulation  
**Confidence:** HIGH - Comprehensive plan with clear criteria
