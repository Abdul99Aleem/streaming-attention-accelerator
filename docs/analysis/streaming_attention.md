# Streaming Attention Performance Analysis
**Module:** streaming_attention  
**Role:** Performance Analyst  
**Date:** 2026-04-01  
**Status:** Predicted Performance - Phase 1

---

## Purpose

This document predicts the performance characteristics of the streaming attention module based on the architectural design in `docs/design/streaming_attention.md`. All metrics are derived from first principles before any RTL implementation.

After RTL simulation, this document will be updated with measured results and variance analysis.

---

## 1. Cycle Count Analysis

### 1.1 Per-State Breakdown

Based on the state machine design, we predict the following cycle counts:

| State | Cycles | Calculation |
|-------|--------|-------------|
| IDLE | 1 | Single cycle wait |
| LOAD_Q | 4 | 64 bytes ÷ 16 bytes/cycle = 4 cycles |
| COMPUTE_SCORES | 32 | 8 keys × (64 MACs ÷ 16 parallel) = 8 × 4 = 32 |
| SOFTMAX | 40 | Max(8) + Exp(16) + Sum(8) + Div(8) = 40 |
| COMPUTE_OUTPUT | 32 | 8 values × (64 MACs ÷ 16 parallel) = 8 × 4 = 32 |
| WRITE_OUTPUT | 4 | 64 bytes ÷ 16 bytes/cycle = 4 cycles |
| NEXT_QUERY | 1 | Counter increment |
| **Per Query Total** | **114** | Sum of above |

### 1.2 Full Attention Computation

**For L=8 queries:**
```
Total cycles = L × cycles_per_query
             = 8 × 114
             = 912 cycles
```

**At 100 MHz clock:**
```
Latency = 912 cycles ÷ 100 MHz
        = 9.12 μs
```

### 1.3 Breakdown by Operation Type

| Operation Type | Cycles | Percentage |
|----------------|--------|------------|
| Memory access (load/write) | 8 × 8 = 64 | 7.0% |
| Dot products (Q·K^T) | 8 × 32 = 256 | 28.1% |
| Softmax | 8 × 40 = 320 | 35.1% |
| Weighted sum (A·V) | 8 × 32 = 256 | 28.1% |
| Control overhead | 8 × 2 = 16 | 1.7% |
| **Total** | **912** | **100%** |

**Observation:** Softmax is the bottleneck at 35.1% of total cycles.

---

## 2. Throughput Analysis

### 2.1 Single Module Throughput

**Attentions per second:**
```
Throughput = Clock frequency ÷ Cycles per attention
           = 100 MHz ÷ 912 cycles
           = 109,649 attentions/second
           ≈ 110K attentions/second
```

### 2.2 Transformer Inference Throughput

**Assumptions:**
- 12-layer transformer
- 8 attention heads per layer
- Total attention operations: 12 × 8 = 96

**Time per token:**
```
Time = 96 attentions × 9.12 μs/attention
     = 875.52 μs
     ≈ 0.876 ms
```

**Tokens per second:**
```
Throughput = 1 ÷ 0.876 ms
           = 1,142 tokens/second
```

**Note:** This assumes sequential processing of attention heads. With 8 parallel modules, throughput would be 8× higher (9,136 tokens/second).

### 2.3 Comparison to CPU Baseline

**Estimated CPU performance (single-threaded):**
- Intel i7-10700K @ 3.8 GHz
- INT8 VNNI instructions: 64 INT8 MACs per cycle
- Attention MACs: 2 × L² × D = 2 × 64 × 64 = 8,192 MACs
- Cycles: 8,192 ÷ 64 = 128 cycles (compute only)
- With memory and control overhead: ~500 cycles
- Time: 500 ÷ 3.8 GHz = 0.132 μs

**CPU throughput:** 1 ÷ 0.132 μs = 7.6M attentions/second

**FPGA vs. CPU:** 110K ÷ 7.6M = **1.4% of CPU performance**

**Analysis:** Single FPGA module is slower than CPU due to:
1. Lower clock frequency (100 MHz vs. 3.8 GHz) → 38× disadvantage
2. Less parallelism (16 MACs vs. 64 MACs) → 4× disadvantage
3. Softmax overhead (35% of cycles vs. ~10% on CPU)

**Mitigation strategies:**
- Increase clock to 200 MHz → 2× improvement
- Increase tile width to 64 → 4× improvement
- Optimize softmax → 1.5× improvement
- **Combined: 12× improvement → 17% of CPU performance**

**Conclusion:** FPGA advantage comes from power efficiency and scalability (multiple modules), not raw single-module performance.

---

## 3. Resource Utilization

### 3.1 Predicted Resource Usage

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | 3,800 | 53,200 | 7.1% |
| Flip-Flops | 6,268 | 106,400 | 5.9% |
| DSP48 | 36 | 220 | 16.4% |
| BRAM (18Kb) | 2 | 140 | 1.4% |

**Derivation:**

**LUTs:**
- State machine: 200
- Dot product control: 1,200
- Softmax logic: 800
- Weighted sum control: 1,200
- Misc control: 400
- **Total: 3,800**

**Flip-Flops:**
- Q buffer: 64 × 8 = 512
- K/V buffer: 64 × 8 = 512
- Score buffer: 8 × 32 = 256
- Attention weights: 8 × 16 = 128
- Output accumulator: 64 × 32 = 2,048
- Pipeline registers: 2,000
- Control registers: 812
- **Total: 6,268**

**DSP48:**
- Dot product engine: 16 multipliers
- Weighted sum engine: 16 multipliers
- Softmax multipliers: 4
- **Total: 36**

**BRAM:**
- Exp LUT: 1 BRAM (512 bytes)
- Reciprocal LUT: 1 BRAM (512 bytes)
- **Total: 2 BRAMs**

### 3.2 Scalability

**Maximum modules per FPGA:**
```
Limited by DSP48: 220 ÷ 36 = 6.1 → 6 modules
Limited by LUTs: 53,200 ÷ 3,800 = 14 modules
Limited by FFs: 106,400 ÷ 6,268 = 16.9 → 16 modules
Limited by BRAM: 140 ÷ 2 = 70 modules
```

**Bottleneck: DSP48 slices → Maximum 6 parallel modules**

**With 6 modules:**
- Throughput: 6 × 110K = 660K attentions/second
- Tokens/second: 6 × 1,142 = 6,852 tokens/second
- **Still only 8.7% of CPU performance, but at much lower power**

---

## 4. Memory Bandwidth Analysis

### 4.1 Per-Query Memory Traffic

| Memory | Read (bytes) | Write (bytes) | Total (bytes) |
|--------|--------------|---------------|---------------|
| Q | 64 | 0 | 64 |
| K | 8 × 64 = 512 | 0 | 512 |
| V | 8 × 64 = 512 | 0 | 512 |
| Output | 0 | 64 | 64 |
| **Total** | **1,088** | **64** | **1,152** |

### 4.2 Bandwidth Requirements

**Per query:**
```
Bandwidth = 1,152 bytes ÷ 114 cycles
          = 10.1 bytes/cycle
          = 1.01 GB/s at 100 MHz
```

**For full attention (8 queries):**
```
Total data = 8 × 1,152 = 9,216 bytes
Bandwidth = 9,216 bytes ÷ 912 cycles
          = 10.1 bytes/cycle
          = 1.01 GB/s (same as per-query)
```

### 4.3 BRAM Bandwidth Capacity

**Dual-port BRAM at 100 MHz:**
- 2 ports × 64 bits/port × 100 MHz = 1.6 GB/s per BRAM
- With 4 BRAMs (Q, K, V, Output): 4 × 1.6 = 6.4 GB/s

**Utilization:** 1.01 GB/s ÷ 6.4 GB/s = **15.8%**

**Conclusion:** Memory bandwidth is not a bottleneck. We have 6.3× headroom.

### 4.4 Arithmetic Intensity

```
Arithmetic Intensity = Total MACs ÷ Total memory traffic
                     = 8,256 MACs ÷ 9,216 bytes
                     = 0.896 ops/byte
```

**Analysis:** This is **memory-bound** (arithmetic intensity < 1).

**Comparison:**
- Ideal compute-bound: > 10 ops/byte
- Our design: 0.896 ops/byte

**Implication:** Increasing compute parallelism beyond 16× won't improve performance much without also increasing memory bandwidth.

---

## 5. Power Consumption Estimate

### 5.1 Component Power Breakdown

**Assumptions:**
- DSP48 dynamic power: 10 mW per slice at 100 MHz
- BRAM dynamic power: 5 mW per block at 100 MHz
- Logic dynamic power: 0.1 mW per 100 LUTs
- Static power: 500 mW (Zynq-7020 baseline)

| Component | Quantity | Unit Power | Total Power |
|-----------|----------|------------|-------------|
| DSP48 | 36 | 10 mW | 360 mW |
| BRAM | 2 | 5 mW | 10 mW |
| LUTs | 3,800 | 0.1 mW/100 | 3.8 mW |
| FFs | 6,268 | 0.05 mW/100 | 3.1 mW |
| **Dynamic Total** | | | **377 mW** |
| Static | | | **500 mW** |
| **Grand Total** | | | **877 mW** |

**Rounded estimate: ~900 mW per module**

### 5.2 Energy per Attention

```
Energy = Power × Time
       = 900 mW × 9.12 μs
       = 8.2 μJ per attention
```

### 5.3 Energy per Token (Transformer Inference)

```
Energy = 96 attentions × 8.2 μJ/attention
       = 787 μJ per token
       ≈ 0.79 mJ per token
```

### 5.4 Comparison to CPU

**CPU power consumption (Intel i7-10700K):**
- TDP: 125 W
- Typical load: ~80 W
- Time per attention: 0.132 μs
- Energy per attention: 80 W × 0.132 μs = 10.6 μJ

**FPGA vs. CPU energy efficiency:**
```
FPGA: 8.2 μJ per attention
CPU:  10.6 μJ per attention
Efficiency gain: 10.6 ÷ 8.2 = 1.3× better
```

**Analysis:** FPGA is only 1.3× more energy-efficient than CPU for single module. However:
- CPU comparison is for single-threaded execution
- FPGA can run 6 modules in parallel at 6 × 900 mW = 5.4 W
- CPU running 6 threads would consume ~100 W
- **Multi-module FPGA efficiency: 100 W ÷ 5.4 W = 18.5× better**

---

## 6. Timing Analysis

### 6.1 Critical Path Prediction

**Longest combinational path:** DSP48 multiply → Adder tree → Register

**Component delays:**
- DSP48 multiply: 3.0 ns
- 4-input adder tree (4 levels): 4 × 0.5 ns = 2.0 ns
- Routing delay: 2.0 ns
- Setup time: 0.2 ns
- **Total: 7.2 ns**

**Maximum frequency:**
```
F_max = 1 ÷ 7.2 ns = 138.9 MHz
```

**Target frequency:** 100 MHz

**Timing margin:**
```
Margin = (138.9 - 100) ÷ 100 = 38.9%
```

**Conclusion:** Design should meet timing with comfortable margin.

### 6.2 Setup/Hold Timing

**Assumptions:**
- All registers are clocked by same 100 MHz clock
- No clock domain crossings
- BRAM outputs are registered (1-cycle latency)

**Potential timing violations:**
- Softmax LUT output → Divider input (long routing)
- Accumulator feedback path (64-bit adder)

**Mitigation:** Add pipeline stages if violations occur during synthesis.

---

## 7. Bottleneck Analysis

### 7.1 Cycle Distribution

From Section 1.3:
- Softmax: 35.1% of cycles
- Dot products: 28.1%
- Weighted sum: 28.1%
- Memory: 7.0%
- Control: 1.7%

**Primary bottleneck: Softmax (35.1%)**

### 7.2 Softmax Breakdown

| Softmax Stage | Cycles | Percentage of Softmax |
|---------------|--------|----------------------|
| Max-find | 8 | 20% |
| Exponentiation | 16 | 40% |
| Sum | 8 | 20% |
| Division | 8 | 20% |

**Exponentiation is the bottleneck within softmax.**

### 7.3 Optimization Opportunities

**1. Parallelize exponentiation:**
- Current: 8 sequential LUT lookups (2 cycles each)
- Optimized: 8 parallel LUT lookups (2 cycles total)
- **Savings: 14 cycles → Softmax reduces from 40 to 26 cycles**
- **Overall improvement: 912 → 798 cycles (12.5% faster)**

**2. Approximate division:**
- Current: Reciprocal LUT + Newton-Raphson (8 cycles)
- Optimized: Reciprocal LUT only (2 cycles)
- **Savings: 6 cycles → Softmax reduces from 40 to 34 cycles**
- **Overall improvement: 912 → 864 cycles (5.3% faster)**

**3. Combined optimizations:**
- Parallel exp + approximate division
- Softmax: 40 → 20 cycles
- **Overall: 912 → 752 cycles (17.5% faster)**
- **New throughput: 133K attentions/second**

**Trade-off:** Parallel exp requires 8× LUT BRAMs (16 BRAMs total) and may reduce accuracy.

---

## 8. Accuracy Analysis

### 8.1 Quantization Error Sources

| Source | Error Type | Magnitude |
|--------|------------|-----------|
| INT8 weights | Rounding | ±0.5 LSB = ±0.004 (scale=0.01) |
| INT8 activations | Rounding | ±0.5 LSB = ±0.004 |
| Dot product accumulation | Rounding | ±√64 × 0.004 = ±0.032 |
| Softmax LUT | Interpolation | ±0.001 (256-entry LUT) |
| Division approximation | Newton-Raphson | ±0.0001 |
| Output requantization | Rounding | ±0.5 LSB = ±0.004 |

### 8.2 Error Propagation

**Worst-case error (sum of absolute errors):**
```
Total error = 0.004 + 0.004 + 0.032 + 0.001 + 0.0001 + 0.004
            = 0.0451
            ≈ 4.5% relative error
```

**Expected error (RMS, assuming independence):**
```
RMS error = √(0.004² + 0.004² + 0.032² + 0.001² + 0.0001² + 0.004²)
          = √(0.00116)
          = 0.034
          ≈ 3.4% relative error
```

**Acceptable tolerance:** ±1% per element (from design spec)

**Conclusion:** Predicted error (3.4%) exceeds tolerance (1%). We may need:
1. Higher precision accumulators (already INT32, sufficient)
2. Finer quantization scales (reduce from 0.01 to 0.005)
3. Higher precision softmax (INT32 instead of INT16)

**Action:** Validate with Python simulation to measure actual error.

---

## 9. Comparison to Design Goals

### 9.1 Design Requirements

| Requirement | Target | Predicted | Status |
|-------------|--------|-----------|--------|
| Sequence length | 8 | 8 | ✓ Met |
| Embedding dim | 64 | 64 | ✓ Met |
| Precision | INT8/INT32 | INT8/INT32 | ✓ Met |
| Clock frequency | 100 MHz | 100 MHz (138 MHz max) | ✓ Met |
| Resource usage | < 20% LUTs | 7.1% | ✓ Met |
| Latency | < 10 μs | 9.12 μs | ✓ Met |
| Accuracy | ±1% error | ±3.4% error | ✗ **Needs validation** |

### 9.2 Performance Targets

| Metric | Target | Predicted | Status |
|--------|--------|-----------|--------|
| Throughput | > 100K attn/s | 110K attn/s | ✓ Met |
| Power | < 1 W | 0.9 W | ✓ Met |
| Energy efficiency | > 1× CPU | 1.3× CPU (single), 18.5× (multi) | ✓ Met |

---

## 10. Risk Assessment

### 10.1 High-Risk Items

**1. Accuracy (3.4% error vs. 1% target)**
- **Likelihood:** High
- **Impact:** High (may require redesign)
- **Mitigation:** Validate with Python simulation, adjust quantization scales

**2. Softmax bottleneck (35% of cycles)**
- **Likelihood:** Medium
- **Impact:** Medium (limits throughput)
- **Mitigation:** Implement parallel exponentiation

**3. Timing closure at 100 MHz**
- **Likelihood:** Low (38% margin predicted)
- **Impact:** High (would require clock reduction)
- **Mitigation:** Add pipeline stages if needed

### 10.2 Medium-Risk Items

**1. Memory bandwidth scaling**
- **Likelihood:** Low (15.8% utilization)
- **Impact:** Medium (limits multi-module scaling)
- **Mitigation:** Use separate BRAM banks per module

**2. DSP48 availability (limits to 6 modules)**
- **Likelihood:** High
- **Impact:** Medium (limits parallelism)
- **Mitigation:** Accept limitation or use larger FPGA

### 10.3 Low-Risk Items

**1. BRAM availability (1.4% utilization)**
- **Likelihood:** Very low
- **Impact:** Low
- **Mitigation:** None needed

**2. Control logic complexity**
- **Likelihood:** Low
- **Impact:** Low
- **Mitigation:** Thorough testbench coverage

---

## 11. Predicted vs. Measured (To Be Filled After Simulation)

### 11.1 Cycle Counts

| Metric | Predicted | Measured | Variance |
|--------|-----------|----------|----------|
| Cycles per query | 114 | TBD | TBD |
| Total cycles (L=8) | 912 | TBD | TBD |
| Softmax cycles | 40 | TBD | TBD |

### 11.2 Resource Utilization

| Resource | Predicted | Measured | Variance |
|----------|-----------|----------|----------|
| LUTs | 3,800 (7.1%) | TBD | TBD |
| FFs | 6,268 (5.9%) | TBD | TBD |
| DSP48 | 36 (16.4%) | TBD | TBD |
| BRAM | 2 (1.4%) | TBD | TBD |

### 11.3 Timing

| Metric | Predicted | Measured | Variance |
|--------|-----------|----------|----------|
| F_max | 138.9 MHz | TBD | TBD |
| Critical path | 7.2 ns | TBD | TBD |

### 11.4 Accuracy

| Metric | Predicted | Measured | Variance |
|--------|-----------|----------|----------|
| RMS error | 3.4% | TBD | TBD |
| Max error | 4.5% | TBD | TBD |

---

## 12. Summary

### 12.1 Key Predictions

- **Latency:** 9.12 μs per attention (912 cycles at 100 MHz)
- **Throughput:** 110K attentions/second
- **Resources:** 7% LUTs, 6% FFs, 16% DSP48, 1% BRAM
- **Power:** 900 mW per module
- **Energy:** 8.2 μJ per attention
- **Bottleneck:** Softmax (35% of cycles)
- **Risk:** Accuracy may exceed ±1% tolerance

### 12.2 Optimization Recommendations

1. **Immediate:** Validate accuracy with Python simulation
2. **Phase 2:** Implement parallel exponentiation (17.5% speedup)
3. **Phase 3:** Increase clock to 138 MHz (38% speedup)
4. **Phase 4:** Increase tile width to 32 (2× speedup)

**Combined potential:** 2.8× throughput improvement → 308K attentions/second

### 12.3 Next Steps

1. User confirms understanding of predicted performance
2. Generate RTL implementation
3. Generate testbench with Python golden reference
4. Simulate and measure actual performance
5. Update this document with measured results
6. Analyze variance and identify root causes

---

## Assumptions

1. BRAM read latency: 1 cycle
2. DSP48 multiply latency: 1 cycle (pipelined)
3. Adder tree delay: 0.5 ns per level
4. Routing delay: 2 ns (typical)
5. Quantization scale: 0.01 for INT8
6. LUT interpolation error: < 0.1%
7. Newton-Raphson provides 16-bit accuracy
8. No pipeline stalls or bubbles
9. Perfect memory scheduling (no conflicts)
10. Single module analysis (no inter-module interference)

These assumptions will be validated during RTL simulation and synthesis.
