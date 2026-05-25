# Streaming Attention Module Design
**Module:** streaming_attention  
**Role:** Design Engineer  
**Date:** 2026-04-01  
**Status:** Architecture Design - Phase 1

---

## Purpose

This document specifies the RTL architecture for the streaming attention module. The design implements scaled dot-product attention with:
- Streaming computation (O(L) memory instead of O(L²))
- INT8 quantized weights and activations
- INT32 accumulators
- INT16 fixed-point softmax
- Tile-based parallelism (tile width = 16)

All design decisions are derived from the mathematical foundations in `docs/learning/attention_fundamentals.md`.

---

## 1. Module Interface

### 1.1 Top-Level Ports

```verilog
module streaming_attention #(
    parameter L = 8,           // Sequence length
    parameter D = 64,          // Embedding dimension
    parameter TILE_WIDTH = 16  // Parallel processing width
)(
    // Clock and reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface
    input  wire        start,
    output wire        done,
    output wire        busy,
    
    // Q matrix input (L×D, INT8)
    input  wire [7:0]  q_data,
    input  wire [9:0]  q_addr,    // log2(L*D) = log2(512) = 9 bits + 1
    output wire        q_rd_en,
    
    // K matrix input (L×D, INT8)
    input  wire [7:0]  k_data,
    input  wire [9:0]  k_addr,
    output wire        k_rd_en,
    
    // V matrix input (L×D, INT8)
    input  wire [7:0]  v_data,
    input  wire [9:0]  v_addr,
    output wire        v_rd_en,
    
    // Output matrix (L×D, INT8)
    output wire [7:0]  out_data,
    output wire [9:0]  out_addr,
    output wire        out_wr_en,
    
    // Configuration
    input  wire [7:0]  scale_shift  // Right-shift amount for scaling (default: 3 for √64=8)
);
```

### 1.2 Interface Protocol

**Start sequence:**
1. External controller loads Q, K, V into their respective memories
2. Controller asserts `start` for 1 cycle
3. Module asserts `busy` and begins computation
4. Module deasserts `busy` and pulses `done` when complete

**Memory access:**
- Module drives `*_addr` and `*_rd_en` to read from Q, K, V memories
- Module drives `out_addr`, `out_data`, and `out_wr_en` to write results
- Assumes 1-cycle read latency (BRAM behavior)

---

## 2. Architecture Overview

### 2.1 Block Diagram

```
                    ┌─────────────────────────────────────┐
                    │   Streaming Attention Controller    │
                    │         (State Machine)             │
                    └──────────┬──────────────────────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
        ┌───────────┐  ┌──────────────┐  ┌──────────┐
        │  Q Buffer │  │  K/V Buffer  │  │ Output   │
        │  (1 row)  │  │  (1 row)     │  │ Accum    │
        └─────┬─────┘  └──────┬───────┘  └────┬─────┘
              │                │               │
              └────────┬───────┘               │
                       ▼                       │
              ┌─────────────────┐              │
              │  Dot Product    │              │
              │  Engine (16×)   │              │
              └────────┬────────┘              │
                       │                       │
                       ▼                       │
              ┌─────────────────┐              │
              │  Score Buffer   │              │
              │  (1 row, L=8)   │              │
              └────────┬────────┘              │
                       │                       │
                       ▼                       │
              ┌─────────────────┐              │
              │  Softmax Unit   │              │
              └────────┬────────┘              │
                       │                       │
                       ▼                       │
              ┌─────────────────┐              │
              │ Attention Wts   │              │
              │  (1 row, L=8)   │              │
              └────────┬────────┘              │
                       │                       │
                       └───────┬───────────────┘
                               ▼
                      ┌─────────────────┐
                      │  Weighted Sum   │
                      │  Engine (16×)   │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │  Output Write   │
                      └─────────────────┘
```

### 2.2 Datapath Components

| Component | Function | Resources |
|-----------|----------|-----------|
| Q Buffer | Store current query row (64 INT8) | 64 registers |
| K/V Buffer | Store current key/value row (64 INT8) | 64 registers |
| Dot Product Engine | 16 parallel MAC units | 16 DSP48 + control |
| Score Buffer | Store attention scores (8 INT32) | 256 registers |
| Softmax Unit | Compute exp + normalize | LUT + divider |
| Attention Weights | Store softmax output (8 INT16) | 128 registers |
| Output Accumulator | Accumulate weighted values (64 INT32) | 2048 registers |
| Weighted Sum Engine | 16 parallel multiply-accumulate | 16 DSP48 + control |

### 2.3 Memory Organization

**External memories (provided by top-level system):**
- Q memory: 512 bytes (8 rows × 64 elements × 1 byte)
- K memory: 512 bytes
- V memory: 512 bytes
- Output memory: 512 bytes

**Internal buffers (registers):**
- Q row buffer: 64 bytes
- K row buffer: 64 bytes
- V row buffer: 64 bytes
- Score buffer: 32 bytes (8 × 4 bytes INT32)
- Attention weights: 16 bytes (8 × 2 bytes INT16)
- Output accumulator: 256 bytes (64 × 4 bytes INT32)

**Total internal storage: 492 bytes** (all registers, no BRAM needed internally)

---

## 3. State Machine

### 3.1 States

```
IDLE          → Wait for start signal
LOAD_Q        → Load current query row into Q buffer
COMPUTE_SCORES → For each key row, compute dot product
SOFTMAX       → Apply softmax to score buffer
COMPUTE_OUTPUT → For each value row, accumulate weighted sum
WRITE_OUTPUT  → Write output row to memory
NEXT_QUERY    → Increment query index, loop or finish
```

### 3.2 State Transition Diagram

```
        ┌──────┐
        │ IDLE │◄─────────────────────────┐
        └───┬──┘                          │
            │ start=1                     │
            ▼                             │
      ┌──────────┐                        │
      │ LOAD_Q   │                        │
      └─────┬────┘                        │
            │ q_row loaded                │
            ▼                             │
  ┌──────────────────┐                   │
  │ COMPUTE_SCORES   │                   │
  │  (loop k=0..L-1) │                   │
  └─────┬────────────┘                   │
        │ all scores computed            │
        ▼                                │
   ┌─────────┐                           │
   │ SOFTMAX │                           │
   └────┬────┘                           │
        │ softmax done                   │
        ▼                                │
  ┌──────────────────┐                  │
  │ COMPUTE_OUTPUT   │                  │
  │  (loop v=0..L-1) │                  │
  └─────┬────────────┘                  │
        │ output accumulated             │
        ▼                                │
   ┌──────────────┐                     │
   │ WRITE_OUTPUT │                     │
   └──────┬───────┘                     │
          │ write done                  │
          ▼                              │
     ┌──────────┐                       │
     │NEXT_QUERY│                       │
     └─────┬────┘                       │
           │                             │
           ├─ q_idx < L-1 ──► loop back to LOAD_Q
           │                             │
           └─ q_idx = L-1 ───────────────┘
```

### 3.3 State Timing

**Cycle counts per state (estimated):**

| State | Cycles | Derivation |
|-------|--------|------------|
| IDLE | 1 | Wait for start |
| LOAD_Q | 4 | Read 64 bytes in 4 bursts (16 bytes/cycle) |
| COMPUTE_SCORES | 8 × 4 = 32 | 8 keys × 4 cycles per dot product |
| SOFTMAX | 40 | Max-find (8) + exp (16) + sum (8) + divide (8) |
| COMPUTE_OUTPUT | 8 × 4 = 32 | 8 values × 4 cycles per weighted sum |
| WRITE_OUTPUT | 4 | Write 64 bytes in 4 bursts |
| NEXT_QUERY | 1 | Increment counter |

**Total per query: 114 cycles**  
**Total for L=8 queries: 8 × 114 = 912 cycles**

**At 100 MHz: 912 cycles = 9.12 μs**

**Assumption:** Dot product and weighted sum take 4 cycles each due to pipelining (64 elements / 16 parallel units = 4 cycles).

---

## 4. Dot Product Engine

### 4.1 Architecture

**Parallel structure:** 16 MAC units operating simultaneously.

```
Input A [63:0] (INT8)  ──┬─► MAC0  (A[0:15]  × B[0:15])
Input B [63:0] (INT8)  ──┼─► MAC1  (A[16:31] × B[16:31])
                         ├─► MAC2  (A[32:47] × B[32:47])
                         └─► MAC3  (A[48:63] × B[48:63])
                              │
                              ▼
                         Adder Tree (4→2→1)
                              │
                              ▼
                         Result (INT32)
```

### 4.2 MAC Unit Design

Each MAC unit computes:
```
result = Σ(i=0 to 15) A[i] × B[i]
```

**Pipeline stages:**
1. **Cycle 0:** Load 16 pairs of INT8 values
2. **Cycle 1:** Multiply (16 INT8×INT8 → 16 INT16) using DSP48
3. **Cycle 2:** Partial sum (16 INT16 → 4 INT32)
4. **Cycle 3:** Final sum (4 INT32 → 1 INT32)

**Latency:** 4 cycles  
**Throughput:** 1 dot product per 4 cycles (not fully pipelined due to adder tree)

### 4.3 Scaling

After dot product, result is scaled by right-shift:
```
scaled_result = dot_product >> scale_shift
```

For √d_k = √64 = 8, `scale_shift = 3` (divide by 8).

**Implementation:** Arithmetic right-shift (preserves sign).

---

## 5. Softmax Unit

### 5.1 Algorithm

**Input:** 8 INT32 scores  
**Output:** 8 INT16 attention weights (Q15 fixed-point, range [0,1])

**Steps:**
1. Find maximum: `max_val = max(scores[0..7])`
2. Subtract max: `shifted[i] = scores[i] - max_val`
3. Exponentiate: `exp_vals[i] = exp(shifted[i])` via LUT
4. Sum: `sum = Σ exp_vals[i]`
5. Normalize: `weights[i] = exp_vals[i] / sum`

### 5.2 Exponentiation LUT

**LUT specification:**
- Input: INT16 (range [-8, 0] after max-subtraction and scaling)
- Output: INT16 (Q15 fixed-point)
- Size: 256 entries
- Indexing: Use upper 8 bits of input as LUT address
- Interpolation: Linear interpolation using lower 8 bits

**LUT generation (Python):**
```python
import numpy as np
lut = np.exp(np.linspace(-8, 0, 256))
lut_int16 = (lut * 32768).astype(np.int16)
```

**Storage:** 256 × 16 bits = 512 bytes → 1 BRAM (18 Kb)

### 5.3 Division

**Method:** Reciprocal approximation + Newton-Raphson iteration.

**Algorithm:**
```
1. Approximate: inv_sum ≈ 1/sum (from reciprocal LUT)
2. Refine: inv_sum = inv_sum × (2 - sum × inv_sum)
3. Multiply: weights[i] = exp_vals[i] × inv_sum
```

**Reciprocal LUT:**
- Input: INT32 sum (range [0, 8×32768] = [0, 262144])
- Output: INT32 reciprocal (Q31 fixed-point)
- Size: 256 entries (use upper 8 bits of sum as index)

**Latency:** 
- Max-find: 8 cycles (tree of comparators)
- Exp lookup: 16 cycles (8 lookups × 2 cycles each for interpolation)
- Sum: 8 cycles (tree of adders)
- Division: 8 cycles (1 reciprocal lookup + 1 Newton-Raphson + 8 multiplies)

**Total: 40 cycles**

---

## 6. Weighted Sum Engine

### 6.1 Architecture

Similar to dot product engine, but multiplies INT16 attention weights by INT8 values.

```
Attention weights [7:0] (INT16)  ──┬─► MUL0  (W[0:3] × V[0:15])
Value row [63:0] (INT8)           ──┼─► MUL1  (W[0:3] × V[16:31])
                                    ├─► MUL2  (W[0:3] × V[32:47])
                                    └─► MUL3  (W[0:3] × V[48:63])
                                         │
                                         ▼
                                    Accumulate into Output[0:63]
```

**Operation:** For each value row `v`, accumulate:
```
Output[k] += Attention[v] × V[v,k]  for k = 0..63
```

### 6.2 Accumulation

**Accumulator precision:** INT32 (to prevent overflow)

**Worst-case accumulation:**
- Max attention weight: 32767 (Q15 = 1.0)
- Max value: 127 (INT8)
- Max product: 32767 × 127 = 4,161,409
- Sum over L=8: 8 × 4,161,409 = 33,291,272

This fits in INT32 (max 2,147,483,647) with 64× headroom.

### 6.3 Output Quantization

After accumulation, output is requantized to INT8:
```
output_int8[k] = clamp(output_int32[k] >> output_shift, -128, 127)
```

**Output shift:** Configurable parameter (typically 15 to undo Q15 scaling).

---

## 7. Resource Estimates

### 7.1 Logic Resources

| Component | LUTs | FFs | DSP48 | BRAM |
|-----------|------|-----|-------|------|
| State machine | 200 | 100 | 0 | 0 |
| Q/K/V buffers | 0 | 1536 | 0 | 0 |
| Dot product engine | 1200 | 800 | 16 | 0 |
| Score buffer | 0 | 256 | 0 | 0 |
| Softmax unit | 800 | 400 | 4 | 2 |
| Attention weights | 0 | 128 | 0 | 0 |
| Output accumulator | 0 | 2048 | 0 | 0 |
| Weighted sum engine | 1200 | 800 | 16 | 0 |
| Control logic | 400 | 200 | 0 | 0 |
| **Total** | **3800** | **6268** | **36** | **2** |

**Target FPGA:** xc7z020clg400-1
- Available: 53,200 LUTs, 106,400 FFs, 220 DSP48, 140 BRAMs
- **Utilization: 7% LUTs, 6% FFs, 16% DSP48, 1% BRAM**

**Conclusion:** Design fits comfortably with room for additional features.

### 7.2 Memory Bandwidth

**Per query computation:**
- Read Q: 64 bytes
- Read K: 8 × 64 = 512 bytes
- Read V: 8 × 64 = 512 bytes
- Write Output: 64 bytes
- **Total: 1,152 bytes**

**Bandwidth:** 1,152 bytes / 114 cycles = 10.1 bytes/cycle = **1.01 GB/s at 100 MHz**

**BRAM bandwidth (dual-port):** ~10 GB/s → **10% utilization**

**Conclusion:** Memory bandwidth is not a bottleneck.

---

## 8. Timing Analysis

### 8.1 Critical Path

**Longest combinational path:** Dot product MAC unit.

**Path:** Register → Multiplier (DSP48) → Adder tree → Register

**Estimated delay:**
- DSP48 multiply: 3 ns
- Adder tree (4 levels): 4 × 0.5 ns = 2 ns
- Routing: 2 ns
- **Total: 7 ns**

**Maximum frequency:** 1 / 7 ns = **142 MHz**

**Target frequency:** 100 MHz → **30% timing margin**

**Assumption:** DSP48 multiply delay is 3 ns (typical for xc7z020 at -1 speed grade).

### 8.2 Throughput

**Latency per attention:** 912 cycles = 9.12 μs at 100 MHz

**Throughput:** 1 / 9.12 μs = **109,649 attentions/second**

**For transformer inference:**
- Assume 12 layers, 8 heads per layer
- Total attentions: 12 × 8 = 96
- **Inference time: 96 × 9.12 μs = 875 μs = 0.875 ms**

**Tokens per second:** 1 / 0.875 ms = **1,143 tokens/second**

**Assumption:** This is for single-head attention. Multi-head would require 8× this module or time-multiplexing.

---

## 9. Interface Timing Diagrams

### 9.1 Start Sequence

```
Cycle:  0    1    2    3    4    5    6    ...
        ─────────────────────────────────────
start:  ──┐  ┌───────────────────────────────
          └──┘
busy:   ─────┐  ┌────────────────────────────
             └──┘ (stays high until done)
done:   ──────────────────────────────┐  ┌───
                                      └──┘
```

### 9.2 Memory Read Timing

```
Cycle:  0    1    2    3    4
        ─────────────────────────
q_addr: ──X──[A0]─[A1]─[A2]─[A3]
q_rd_en:──┐  ┌────────────────────
          └──┘
q_data: ─────X──[D0]─[D1]─[D2]─[D3]
             (1 cycle latency)
```

### 9.3 Memory Write Timing

```
Cycle:     0    1    2    3    4
           ─────────────────────────
out_addr:  ──X──[A0]─[A1]─[A2]─[A3]
out_data:  ──X──[D0]─[D1]─[D2]─[D3]
out_wr_en: ──┐  ┌────────────────────
             └──┘
```

---

## 10. Design Decisions and Trade-offs

### 10.1 Streaming vs. Block-Based

**Decision:** Streaming (O(L) memory)

**Rationale:**
- Saves 8× memory (384 bytes → 48 bytes for intermediate storage)
- Enables scaling to longer sequences
- Trade-off: 5.3× more memory bandwidth (acceptable for L=8)

### 10.2 Tile Width = 16

**Decision:** 16 parallel MAC units

**Rationale:**
- Divides D=64 evenly (64/16 = 4 cycles)
- Uses 16 DSP48 slices (7% of available 220)
- Balances parallelism vs. resource usage

**Alternative:** Tile width = 8 would use fewer resources but double latency.

### 10.3 Fixed-Point Softmax

**Decision:** INT16 Q15 format for attention weights

**Rationale:**
- Range [0,1] fits naturally in Q15
- 16-bit precision sufficient for 8-element softmax
- Avoids floating-point hardware

**Alternative:** Full INT32 would waste bits (attention weights never exceed 1.0).

### 10.4 LUT-Based Exponentiation

**Decision:** 256-entry LUT with linear interpolation

**Rationale:**
- Faster than CORDIC or polynomial approximation
- 512 bytes (1 BRAM) is negligible
- Accuracy sufficient for attention (errors < 0.1%)

**Alternative:** Polynomial approximation would save BRAM but increase latency.

---

## 11. Verification Strategy

### 11.1 Unit Tests

1. **Dot product engine:** Test with known INT8 vectors, verify INT32 result
2. **Softmax unit:** Test with known scores, verify weights sum to 1.0
3. **Weighted sum engine:** Test with known weights and values
4. **State machine:** Test state transitions with mock data

### 11.2 Integration Tests

1. **Single query:** Compute attention for one query, compare to Python reference
2. **Full attention:** Compute all 8 queries, compare full output matrix
3. **Edge cases:** Test with all-zeros, all-max, random inputs

### 11.3 Tolerance

**Acceptable error:** ±1% relative error per element

**Rationale:** Quantization introduces ~0.5% error per operation, accumulating to ~1% over full computation.

---

## 12. Open Questions

1. **Output quantization shift:** What value of `output_shift` preserves accuracy?
   - **Resolution:** Determine empirically via Python simulation

2. **Softmax LUT accuracy:** Is 256-entry LUT sufficient, or do we need 512?
   - **Resolution:** Measure error vs. floating-point reference

3. **Pipeline stalls:** Do memory accesses cause pipeline bubbles?
   - **Resolution:** Simulate with realistic BRAM timing

4. **Multi-head support:** How to extend to 8 attention heads?
   - **Resolution:** Defer to Phase 2 (out of scope for now)

---

## 13. Next Steps

**Before RTL implementation:**
1. Create `docs/analysis/streaming_attention.md` with predicted performance metrics
2. User confirms understanding of architecture
3. Generate RTL: `rtl/attention/streaming_attention.v`
4. Generate testbench: `tb/integration/tb_streaming_attention.v`
5. Simulate and measure actual performance
6. Update analysis document with measured vs. predicted

**Action:** Proceed to `/analyze streaming_attention` to predict performance before coding.

---

## Assumptions

1. BRAM read latency: 1 cycle
2. DSP48 multiply latency: 1 cycle (pipelined)
3. Clock frequency: 100 MHz
4. External memories (Q, K, V, Output) are dual-port BRAMs
5. No AXI interface (direct memory access for now)
6. Single attention head (no multi-head support)
7. Fixed sequence length L=8 (no variable-length support)
8. Quantization scales are powers of 2

These assumptions will be validated during implementation and testing.
