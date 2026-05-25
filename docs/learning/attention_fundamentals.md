# Attention Fundamentals
**Module:** attention_fundamentals  
**Role:** Teaching Assistant  
**Date:** 2026-04-01  
**Status:** Foundation - Phase 1

---

## Purpose

This document establishes the mathematical foundation for implementing scaled dot-product attention in hardware. Every equation, every numerical consideration, and every design trade-off is derived from first principles. No prior knowledge is assumed beyond basic linear algebra and digital logic.

---

## 1. What is Attention?

### 1.1 The Core Problem

In sequence processing, we need to determine **which parts of the input sequence are relevant** when processing each element. Consider translating "The cat sat on the mat" to French. When translating "sat", we need to pay attention to "cat" (the subject) more than "the" or "mat".

Attention is a **learned weighting mechanism** that computes relevance scores between sequence elements.

### 1.2 The Three Matrices: Q, K, V

Every attention mechanism operates on three matrices derived from the input:

- **Query (Q):** "What am I looking for?"
- **Key (K):** "What do I contain?"
- **Value (V):** "What information do I carry?"

For a sequence of length `L` with embedding dimension `d`:
- Input: `X ∈ ℝ^(L×d)`
- Query: `Q = X·W_Q` where `W_Q ∈ ℝ^(d×d_k)`
- Key: `K = X·W_K` where `W_K ∈ ℝ^(d×d_k)`
- Value: `V = X·W_V` where `W_V ∈ ℝ^(d×d_v)`

**For this project:**
- `L = 8` (sequence length)
- `d = 64` (embedding dimension)
- `d_k = d_v = 64` (query/key/value dimension)

---

## 2. Scaled Dot-Product Attention

### 2.1 The Complete Formula

```
Attention(Q, K, V) = softmax(Q·K^T / √d_k) · V
```

Let's break this down step by step.

### 2.2 Step 1: Compute Similarity Scores

```
S = Q · K^T
```

**Dimensions:**
- `Q ∈ ℝ^(L×d_k)` → (8×64)
- `K^T ∈ ℝ^(d_k×L)` → (64×8)
- `S ∈ ℝ^(L×L)` → (8×8)

**Interpretation:** `S[i,j]` measures how much query `i` should attend to key `j`.

**Computation:** Each element `S[i,j]` is a dot product:
```
S[i,j] = Σ(k=0 to d_k-1) Q[i,k] · K[j,k]
```

For `d_k = 64`, this is 64 multiply-accumulate operations per score.

**Total operations for S:**
- Elements in S: `L × L = 8 × 8 = 64`
- MACs per element: `d_k = 64`
- **Total MACs: 64 × 64 = 4,096**

### 2.3 Step 2: Scale by √d_k

```
S_scaled = S / √d_k
```

**Why scale?** As `d_k` increases, the magnitude of dot products grows. For random unit vectors:
```
E[Q[i,:]·K[j,:]] = 0
Var[Q[i,:]·K[j,:]] = d_k
```

Without scaling, large `d_k` pushes dot products into regions where softmax gradients vanish (saturation). Dividing by `√d_k` normalizes variance to 1.

**For our design:** `√d_k = √64 = 8`

**Implementation consideration:** Division by 8 is a right-shift by 3 bits in hardware (assuming power-of-2 scaling).

### 2.4 Step 3: Apply Softmax

```
A = softmax(S_scaled)
```

Where softmax is applied **row-wise**:
```
A[i,j] = exp(S_scaled[i,j]) / Σ(k=0 to L-1) exp(S_scaled[i,k])
```

**Properties:**
- Each row sums to 1: `Σ_j A[i,j] = 1`
- All values in [0,1]: `0 ≤ A[i,j] ≤ 1`
- `A[i,j]` is the attention weight from query `i` to key `j`

**Numerical stability:** Direct computation of `exp(x)` overflows for large `x`. We use the **max-subtraction trick**:

```
For each row i:
  m_i = max_j S_scaled[i,j]
  A[i,j] = exp(S_scaled[i,j] - m_i) / Σ_k exp(S_scaled[i,k] - m_i)
```

This shifts all exponents to be ≤ 0, preventing overflow while preserving the result (since the `m_i` terms cancel in the ratio).

### 2.5 Step 4: Weighted Sum of Values

```
Output = A · V
```

**Dimensions:**
- `A ∈ ℝ^(L×L)` → (8×8)
- `V ∈ ℝ^(L×d_v)` → (8×64)
- `Output ∈ ℝ^(L×d_v)` → (8×64)

**Interpretation:** Each output row `i` is a weighted combination of all value vectors, where weights come from attention row `A[i,:]`.

**Computation:**
```
Output[i,k] = Σ(j=0 to L-1) A[i,j] · V[j,k]
```

**Total operations:**
- Elements in Output: `L × d_v = 8 × 64 = 512`
- MACs per element: `L = 8`
- **Total MACs: 512 × 8 = 4,096**

---

## 3. Quantization Strategy

### 3.1 Why Quantize?

Floating-point arithmetic in hardware is expensive:
- Large area (multipliers, adders)
- High power consumption
- Lower throughput

Integer arithmetic is:
- 10-100× smaller area
- 10-100× lower power
- 2-10× higher throughput

**Trade-off:** Reduced precision, potential accuracy loss.

### 3.2 Quantization Scheme for This Project

| Data Type | Precision | Range | Use Case |
|-----------|-----------|-------|----------|
| Weights (Q, K, V) | INT8 | [-128, 127] | Learned parameters |
| Activations (input) | INT8 | [-128, 127] | Input embeddings |
| Accumulators | INT32 | [-2^31, 2^31-1] | Intermediate sums |
| Softmax | INT16 (fixed-point) | [0, 1] scaled to [0, 32767] | Attention weights |

### 3.3 Quantization Mathematics

**Symmetric quantization** maps floating-point value `x` to integer `x_q`:

```
x_q = round(x / scale)
scale = max(|x|) / (2^(bits-1) - 1)
```

**Dequantization:**
```
x ≈ x_q · scale
```

**Example:** Quantize weight `w = 0.73` to INT8 with `scale = 0.01`:
```
w_q = round(0.73 / 0.01) = round(73) = 73
w_reconstructed = 73 × 0.01 = 0.73
```

### 3.4 Accumulator Precision

When multiplying two INT8 values:
```
x_q ∈ [-128, 127]
y_q ∈ [-128, 127]
x_q · y_q ∈ [-16384, 16129]
```

Summing `d_k = 64` such products:
```
Σ(i=0 to 63) x_q[i] · y_q[i] ∈ [-1,048,576, 1,032,576]
```

This fits comfortably in INT32 (range ±2.1 billion), with headroom for multiple accumulations.

### 3.5 Softmax in Fixed-Point

Softmax requires:
1. Exponentiation: `exp(x)`
2. Division: `1 / sum`

**Approach:** Use lookup table (LUT) for `exp(x)` with linear interpolation.

**Fixed-point representation:** Q15 format (1 sign bit, 15 fractional bits)
- Range: [-1, 1) with resolution 2^-15 ≈ 0.00003
- Attention weights in [0,1] fit naturally

**LUT design:**
- Input range: [-8, 0] (after max-subtraction, all values ≤ 0)
- LUT size: 256 entries (8-bit index)
- Step size: 8/256 = 0.03125
- Each entry: 16-bit fixed-point `exp(x)` value

---

## 4. Computational Complexity

### 4.1 Operation Counts

For sequence length `L` and dimension `d`:

| Operation | MACs            | Memory Reads     | Memory Writes |
| --------- | --------------- | ---------------- | ------------- |
| Q·K^T     | L²·d            | 2·L·d            | L²            |
| Softmax   | L² (exp + div)  | L²               | L²            |
| A·V       | L²·d            | L² + L·d         | L·d           |
| **Total** | **2·L²·d + L²** | **2·L·d + 2·L²** | **L² + L·d**  |

**For our parameters (L=8, d=64):**
- MACs: 2·64·64 + 64 = 8,256
- Memory reads: 2·8·64 + 2·64 = 1,152 bytes (INT8)
- Memory writes: 64 + 8·64 = 576 bytes

### 4.2 Memory Bandwidth Requirements

At 100 MHz clock:
- Cycle budget per attention: Assume 1000 cycles (10 μs)
- Memory bandwidth: (1,152 + 576) bytes / 10 μs = **172.8 MB/s**

**Assumption:** This is well within BRAM bandwidth (typically 10+ GB/s for dual-port BRAM).

### 4.3 Arithmetic Intensity

```
Arithmetic Intensity = MACs / Memory Accesses
                     = 8,256 / 1,728
                     ≈ 4.78 ops/byte
```

This is **compute-bound** rather than memory-bound, which is favorable for hardware acceleration.

---

## 5. Streaming vs. Block-Based Computation

### 5.1 Block-Based (Standard Approach)

**Method:** Compute entire attention matrix `A` before computing output.

**Memory requirement:**
- Store full `S` matrix: `L × L × 4 bytes = 8 × 8 × 4 = 256 bytes` (INT32)
- Store full `A` matrix: `L × L × 2 bytes = 8 × 8 × 2 = 128 bytes` (INT16)
- **Total intermediate storage: 384 bytes**

**Advantages:**
- Simpler control logic
- Easier to verify

**Disadvantages:**
- Memory scales as O(L²)
- Cannot handle long sequences

### 5.2 Streaming (This Project's Approach)

**Method:** Compute attention output **one query at a time**, discarding intermediate results.

**Memory requirement per query:**
- Store one row of `S`: `L × 4 bytes = 8 × 4 = 32 bytes`
- Store one row of `A`: `L × 2 bytes = 8 × 2 = 16 bytes`
- **Total intermediate storage: 48 bytes** (8× reduction)

**Advantages:**
- Memory scales as O(L) instead of O(L²)
- Enables longer sequences
- Lower power (less memory access)

**Disadvantages:**
- More complex control logic
- Must recompute or stream K, V for each query

**Trade-off:** We trade **recomputation** (reading K, V multiple times) for **memory savings** (not storing full attention matrix).

### 5.3 Streaming Algorithm

```
For each query i = 0 to L-1:
  1. Load Q[i,:] (64 bytes)
  2. For each key j = 0 to L-1:
       Load K[j,:] (64 bytes)
       Compute S[i,j] = Q[i,:] · K[j,:]
  3. Apply softmax to S[i,:] → A[i,:]
  4. For each key j = 0 to L-1:
       Load V[j,:] (64 bytes)
       Accumulate Output[i,:] += A[i,j] · V[j,:]
  5. Write Output[i,:] (64 bytes)
```

**Memory access pattern:**
- Q: Read once per query → `L × d = 512 bytes` total
- K: Read `L` times (once per query) → `L² × d = 4,096 bytes` total
- V: Read `L` times (once per query) → `L² × d = 4,096 bytes` total
- Output: Write once → `L × d = 512 bytes` total

**Total memory traffic: 9,216 bytes** (vs. 1,728 bytes for block-based)

**Conclusion:** Streaming trades 5.3× more memory bandwidth for 8× less on-chip storage. For small L=8, this is acceptable. For large L, this becomes essential.

---

## 6. Hardware Implications

### 6.1 Parallelism Opportunities

**Tile-based computation:** Process multiple elements in parallel.

For tile width `T = 16`:
- Compute 16 dot products simultaneously
- Requires 16 parallel MAC units
- Reduces latency by 16× (ideally)

**Resource estimate (rough):**
- 16 INT8×INT8 multipliers: ~1,600 LUTs, ~800 FFs
- 16 INT32 adders: ~800 LUTs, ~512 FFs
- Control logic: ~500 LUTs, ~300 FFs
- **Total: ~2,900 LUTs, ~1,612 FFs** (fits easily in xc7z020: 53,200 LUTs)

**Assumption:** These are order-of-magnitude estimates. Actual synthesis will differ.

### 6.2 Memory Architecture

**BRAM allocation:**
- Q buffer: 512 bytes → 1 BRAM (18 Kb)
- K buffer: 512 bytes → 1 BRAM
- V buffer: 512 bytes → 1 BRAM
- Intermediate S: 32 bytes → Registers
- Intermediate A: 16 bytes → Registers
- Output buffer: 512 bytes → 1 BRAM

**Total: 4 BRAMs** (xc7z020 has 140 BRAMs → plenty of headroom)

### 6.3 Pipeline Stages

Proposed pipeline for dot product:
1. **Fetch:** Read operands from BRAM (1 cycle)
2. **Multiply:** INT8×INT8 → INT16 (1 cycle, DSP48)
3. **Accumulate:** Add to running sum (1 cycle)
4. **Write-back:** Store result (1 cycle)

**Latency:** 4 cycles per MAC  
**Throughput:** 1 MAC per cycle (fully pipelined)

**Assumption:** DSP48 slices can sustain 1 MAC/cycle at 100 MHz.

---

## 7. Numerical Considerations

### 7.1 Quantization Error

**Per-operation error:** Quantization introduces rounding error at each step.

For INT8 with scale `s`:
```
Error per value: ±s/2
```

For dot product of length `d`:
```
Accumulated error: O(√d · s/2)  (assuming random errors)
```

**For d=64, s=0.01:**
```
Error ≈ √64 · 0.005 = 8 · 0.005 = 0.04
```

This is ~4% relative error for unit-magnitude vectors.

**Mitigation:** Use higher precision (INT32) for accumulators.

### 7.2 Softmax Stability

**Problem:** `exp(x)` overflows for `x > 88` (in float32).

**Solution:** Max-subtraction trick (described in Section 2.4).

**Hardware implementation:**
1. First pass: Find `max_j S[i,j]` (requires comparator tree)
2. Second pass: Compute `exp(S[i,j] - max)` using LUT
3. Third pass: Sum all `exp(...)` values
4. Fourth pass: Divide each by sum

**Latency:** 4 passes over L elements → `4·L = 32 cycles` (for L=8)

### 7.3 Division in Softmax

**Problem:** Division is expensive in hardware (high latency, large area).

**Solution:** Use reciprocal approximation + Newton-Raphson iteration.

**Algorithm:**
```
1. Approximate: x_0 = 1/sum (from LUT)
2. Refine: x_1 = x_0 · (2 - sum·x_0)
3. Multiply: result = numerator · x_1
```

**Latency:** ~10 cycles per division (vs. ~100 for full divider)

**Assumption:** One Newton-Raphson iteration provides sufficient accuracy for INT16.

---

## 8. Verification Strategy

### 8.1 Golden Reference Model

**Python implementation:** Compute attention in floating-point (NumPy).

**Purpose:**
- Generate expected outputs for testbenches
- Validate quantization effects
- Debug discrepancies

### 8.2 Testbench Hierarchy

1. **Unit tests:** Individual components (dot product, softmax, etc.)
2. **Integration tests:** Full attention module
3. **System tests:** End-to-end with real embeddings

### 8.3 Tolerance Specification

**Acceptable error:** ±1% relative error on output values.

**Rationale:** Quantization introduces ~4% error in intermediate values, but errors partially cancel in final output.

**Verification:** Compare RTL output against Python reference, flag any element with >1% error.

---

## 9. Summary of Key Equations

```
1. Attention scores:     S = Q · K^T
2. Scaling:              S_scaled = S / √d_k
3. Attention weights:    A = softmax(S_scaled)
4. Output:               Y = A · V

Where:
  Q, K, V ∈ ℝ^(L×d)
  S, A ∈ ℝ^(L×L)
  Y ∈ ℝ^(L×d)
  
Complexity:
  MACs: 2·L²·d + L²
  Memory: O(L) for streaming, O(L²) for block-based
```

---

## 10. Next Steps

Before proceeding to design, you should be able to answer:

1. **Why do we scale by √d_k?** (Explain in terms of variance)
2. **What is the arithmetic intensity of attention?** (Compute ops/byte)
3. **Why use streaming instead of block-based?** (Memory trade-off)
4. **How does quantization affect accuracy?** (Error propagation)
5. **What is the max-subtraction trick?** (Numerical stability)

**Action:** Please restate one of these concepts in your own words to verify understanding before we move to the design phase.

---

## Assumptions Made in This Document

1. Clock frequency: 100 MHz
2. BRAM latency: 1 cycle (dual-port)
3. DSP48 throughput: 1 MAC/cycle
4. Quantization scales are powers of 2 (for efficient shifting)
5. Newton-Raphson provides sufficient accuracy for division
6. Sequence length L=8 is fixed (no variable-length support)
7. Single attention head (no multi-head support yet)

These assumptions will be validated or revised in subsequent design phases.
