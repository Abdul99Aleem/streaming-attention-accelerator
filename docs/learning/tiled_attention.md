# Tiled Streaming Attention - Learning Document
**Module:** streaming_attention_tiled  
**Date:** 2026-04-03  
**Purpose:** Understand tile-based parallelism for attention acceleration

---

## What is Tiling?

**Tiling** (also called **blocking**) is a technique that divides large matrix operations into smaller sub-matrices (tiles) that can be processed in parallel or fit better in local memory.

### Why Tiling Matters for Attention

The attention computation has three main operations:
1. **Q·K^T** - Compute attention scores (L×D × D×L = L×L scores)
2. **Softmax** - Normalize scores (L×L → L×L weights)
3. **A·V** - Weighted sum of values (L×L × L×D = L×D output)

**Without tiling (sequential):**
- Process one element at a time
- D cycles to compute one dot product
- L×D cycles to compute all scores for one query
- Very slow for large D

**With tiling (parallel):**
- Process TILE_WIDTH elements simultaneously
- D/TILE_WIDTH cycles to compute one dot product
- L×(D/TILE_WIDTH) cycles for all scores
- TILE_WIDTH× speedup

---

## Mathematical Foundation

### Sequential Dot Product

Computing q·k where both are D-dimensional vectors:

```
result = Σ(i=0 to D-1) q[i] × k[i]
```

**Timing:** D cycles (one multiply-accumulate per cycle)

### Tiled Dot Product

Divide vectors into tiles of width W:

```
result = Σ(t=0 to D/W-1) Σ(i=0 to W-1) q[t×W + i] × k[t×W + i]
```

**Timing:** D/W cycles (W multiply-accumulates per cycle)

**Speedup:** W× faster

---

## Attention Tiling Strategy

### Current Implementation (v3 - Sequential)

```
For each query q_i (i = 0 to L-1):
    For each key k_j (j = 0 to L-1):
        score[i][j] = 0
        For each dimension d (d = 0 to D-1):
            score[i][j] += q_i[d] × k_j[d]  // 1 cycle per element
        // Total: D cycles per score
    // Total: L×D cycles per query
    
    softmax(scores[i])  // 19 cycles
    
    For each value v_j (j = 0 to L-1):
        For each dimension d (d = 0 to D-1):
            output[i][d] += attention[i][j] × v_j[d]  // 1 cycle per element
        // Total: L×D cycles per query
// Total per query: L×D + 19 + L×D = 2×L×D + 19 cycles
// For L=8, D=64: 2×8×64 + 19 = 1,043 cycles per query
// For all L queries: 8 × 1,043 = 8,344 cycles
```

### Tiled Implementation (v4 - Parallel)

```
For each query q_i (i = 0 to L-1):
    For each key k_j (j = 0 to L-1):
        score[i][j] = 0
        For each tile t (t = 0 to D/W-1):
            // Process W elements in parallel
            score[i][j] += dot_product_tile(q_i[t×W:(t+1)×W], k_j[t×W:(t+1)×W])
        // Total: D/W cycles per score
    // Total: L×(D/W) cycles per query
    
    softmax(scores[i])  // 19 cycles
    
    For each value v_j (j = 0 to L-1):
        For each tile t (t = 0 to D/W-1):
            // Process W elements in parallel
            output[i][t×W:(t+1)×W] += attention[i][j] × v_j[t×W:(t+1)×W]
        // Total: L×(D/W) cycles per query
// Total per query: L×(D/W) + 19 + L×(D/W) = 2×L×(D/W) + 19 cycles
// For L=8, D=64, W=16: 2×8×(64/16) + 19 = 2×8×4 + 19 = 83 cycles per query
// For all L queries: 8 × 83 = 664 cycles
```

**Speedup:** 8,344 / 664 = **12.6× faster**

---

## Hardware Requirements for Tiling

### Parallel MAC Units

To process W elements per cycle, we need W MAC units:

```
For W=16:
    16 MAC units operating in parallel
    Each MAC computes: acc += a[i] × b[i]
    All 16 MACs share the same control signals
```

**Resource Cost:**
- 16 MAC units = 16 DSP48 slices
- Zynq-7020 has 220 DSP48 slices
- 16/220 = 7.3% utilization ✓

### Memory Bandwidth

**Sequential (v3):**
- Read 1 element per cycle
- Bandwidth: 1 × 8 bits = 8 bits/cycle

**Tiled (v4):**
- Read W elements per cycle
- Bandwidth: W × 8 bits = 128 bits/cycle (for W=16)

**BRAM Capability:**
- Each BRAM port: 36 bits/cycle (configurable)
- Need 4 BRAM ports to supply 128 bits/cycle
- Or use wider BRAM configuration (72 bits/cycle with 2 ports)

---

## Tiling Trade-offs

### Advantages ✓

1. **Speed:** W× faster computation
2. **Efficiency:** Better DSP utilization
3. **Scalability:** Can increase W for more speedup
4. **Predictable:** Regular access patterns

### Disadvantages ✗

1. **Complexity:** More complex control logic
2. **Memory:** Requires wider memory interfaces
3. **Resources:** Uses more DSP slices
4. **Alignment:** D must be multiple of W

---

## Design Decisions for v4

### Tile Width Selection

**Options:**
- W=4: 4× speedup, 4 DSP slices
- W=8: 8× speedup, 8 DSP slices
- W=16: 16× speedup, 16 DSP slices ✓ (chosen)
- W=32: 32× speedup, 32 DSP slices (too many)

**Choice: W=16**

**Rationale:**
- Good balance of speed vs resources
- 16 DSP slices = 7.3% of available (plenty of headroom)
- D=64 is evenly divisible by 16 (4 tiles)
- Matches existing dot_product_engine design

### Memory Organization

**Strategy:** Use multiple BRAM ports

```
Q matrix: 2 BRAM ports (72 bits/cycle)
K matrix: 2 BRAM ports (72 bits/cycle)
V matrix: 2 BRAM ports (72 bits/cycle)
Output:   2 BRAM ports (72 bits/cycle)
```

**Total:** 8 BRAM ports (4 BRAMs with dual ports)

### State Machine Design

**States:**
1. IDLE - Wait for start
2. LOAD_Q_TILE - Load W elements of Q
3. SCORE_COMPUTE - Compute Q·K^T for one tile
4. SCORE_ACCUMULATE - Accumulate partial scores
5. SOFTMAX - Compute attention weights
6. LOAD_V_TILE - Load W elements of V
7. OUTPUT_COMPUTE - Compute weighted sum
8. OUTPUT_ACCUMULATE - Accumulate partial outputs
9. WRITE_OUTPUT - Write final output
10. NEXT_QUERY - Move to next query

---

## Performance Predictions

### Cycle Count Breakdown (W=16, L=8, D=64)

**Per Query:**
```
Load Q row:           D/W = 64/16 = 4 cycles
Compute scores:       L × (D/W) = 8 × 4 = 32 cycles
Softmax:              19 cycles
Load V + accumulate:  L × (D/W) = 8 × 4 = 32 cycles
Write output:         D/W = 4 cycles
Total:                4 + 32 + 19 + 32 + 4 = 91 cycles per query
```

**For All L=8 Queries:**
```
Total: 8 × 91 = 728 cycles
```

**Comparison:**

| Version | Cycles | Speedup vs v3 |
|---------|--------|---------------|
| v3 (sequential) | 9,824 | 1× (baseline) |
| v4 (tiled, W=16) | 728 | 13.5× |

**At 100 MHz:**
- v3: 98.24 μs
- v4: 7.28 μs
- **Speedup: 13.5×**

---

## Resource Predictions

### DSP48 Slices

**v3:** 0 DSP slices (uses fabric multipliers)  
**v4:** 16 DSP slices (parallel MAC array)

**Utilization:** 16/220 = 7.3%

### LUTs

**v3:** ~2,000 LUTs (estimated)  
**v4:** ~3,500 LUTs (estimated, includes tiling control)

**Utilization:** 3,500/53,200 = 6.6%

### BRAMs

**v3:** 4 BRAMs (Q, K, V, Output)  
**v4:** 4 BRAMs (same, but wider ports)

**Utilization:** 4/140 = 2.9%

### Registers

**v3:** ~1,500 FFs  
**v4:** ~2,500 FFs (more pipeline registers)

**Utilization:** 2,500/106,400 = 2.3%

---

## Key Concepts to Understand

Before proceeding to design, ensure you understand:

1. **Why tiling improves performance**
   - Parallel processing of W elements
   - Reduces cycle count by factor of W

2. **Memory bandwidth requirements**
   - Need to supply W elements per cycle
   - Requires wider memory interfaces or multiple ports

3. **Trade-off between speed and resources**
   - Larger W = faster but more DSP slices
   - Must balance performance vs available resources

4. **State machine complexity**
   - More states to manage tile loading
   - Need to track tile indices and accumulation

5. **Alignment requirements**
   - D must be multiple of W
   - Simplifies addressing and control logic

---

## Self-Check Questions

Before moving to design phase, answer these:

1. **Why does tiling provide a W× speedup?**
   - Answer: Because we process W elements in parallel instead of sequentially

2. **What is the main resource cost of tiling?**
   - Answer: DSP48 slices for parallel MAC units

3. **Why did we choose W=16 instead of W=32?**
   - Answer: Good balance - 16× speedup with only 7.3% DSP utilization

4. **How many cycles does v4 take per query?**
   - Answer: 91 cycles (vs 1,228 for v3)

5. **What is the total speedup for L=8 queries?**
   - Answer: 13.5× (9,824 cycles → 728 cycles)

---

## Next Steps

After confirming understanding:
1. Design the tiled architecture (state machine, datapath)
2. Analyze predicted performance vs measured
3. Implement RTL (streaming_attention_v4.v)
4. Create testbench
5. Simulate and measure actual performance
6. Compare measured vs predicted

---

**Status:** Teaching complete - ready for design phase  
**User Action Required:** Confirm understanding before proceeding to design
