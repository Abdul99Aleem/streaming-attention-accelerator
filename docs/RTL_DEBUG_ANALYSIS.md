# RTL Debug Analysis - Integration Test Failures
**Project:** Streaming Transformer Attention Accelerator  
**Date:** 2026-04-01  
**Status:** Critical Bugs Identified

---

## Critical Bug #1: Dot Product Inputs Not Driven

### Issue

**Symptom:**
- Outputs are undefined ("x")
- Cycle count 6.4× too high

**Root Cause:**
The `dp_a` and `dp_b` input arrays to the dot product engine are declared but **never populated** with data from the buffers.

**Code Analysis:**
```verilog
// In streaming_attention.v:
reg [7:0] dp_a [0:TILE_WIDTH-1];  // Declared
reg [7:0] dp_b [0:TILE_WIDTH-1];  // Declared

// But nowhere in the code are these arrays assigned values!
// The dot product engine receives undefined inputs
```

**Impact:**
- Dot product engine computes with undefined inputs
- Produces undefined results
- Propagates through entire pipeline
- Final output is undefined

### Fix Required

Add logic to populate `dp_a` and `dp_b` from buffers:

```verilog
// Load dp_a from q_buffer
always @(*) begin
    for (i = 0; i < TILE_WIDTH; i = i + 1) begin
        dp_a[i] = q_buffer[tile_idx * TILE_WIDTH + i];
    end
end

// Load dp_b from k_buffer
always @(*) begin
    for (i = 0; i < TILE_WIDTH; i = i + 1) begin
        dp_b[i] = k_buffer[tile_idx * TILE_WIDTH + i];
    end
end
```

---

## Critical Bug #2: K and V Buffers Not Loaded

### Issue

**Symptom:**
- k_buffer and v_buffer are never loaded from memory

**Root Cause:**
The code loads `q_buffer` in LOAD_Q state, but there's no logic to load `k_buffer` or `v_buffer` from memory.

**Code Analysis:**
```verilog
// Q buffer is loaded:
always @(posedge clk) begin
    if (state == LOAD_Q) begin
        q_buffer[element_idx] <= q_data;
    end
end

// But k_buffer and v_buffer are never loaded!
// They remain at their initial values (undefined or 0)
```

**Impact:**
- Dot product uses undefined K values
- Weighted sum uses undefined V values
- Entire computation is invalid

### Fix Required

Add logic to load K and V buffers:

```verilog
// Load K buffer during COMPUTE_SCORES
always @(posedge clk) begin
    if (state == COMPUTE_SCORES && k_rd_en) begin
        k_buffer[element_idx] <= k_data;
    end
end

// Load V buffer during COMPUTE_OUTPUT
always @(posedge clk) begin
    if (state == COMPUTE_OUTPUT && v_rd_en) begin
        v_buffer[element_idx] <= v_data;
    end
end
```

---

## Critical Bug #3: Tile Index Not Used

### Issue

**Symptom:**
- `tile_idx` is declared but never incremented or used

**Root Cause:**
The design needs to process D=64 elements in tiles of 16, requiring 4 iterations. But `tile_idx` is never managed.

**Impact:**
- Only first 16 elements processed
- Remaining 48 elements ignored
- Incorrect dot product results

### Fix Required

Add tile index management and use it in state machine.

---

## Critical Bug #4: State Machine Incomplete

### Issue

**Symptom:**
- State machine doesn't properly sequence tile-based computation

**Root Cause:**
The state machine assumes single-cycle operations but needs to iterate over tiles.

**Impact:**
- State transitions happen before operations complete
- Incorrect sequencing
- High cycle count

### Fix Required

Redesign state machine to handle tile-based iteration properly.

---

## Severity Assessment

| Bug | Severity | Impact | Fix Complexity |
|-----|----------|--------|----------------|
| #1: dp_a/dp_b not driven | CRITICAL | No valid outputs | Medium |
| #2: K/V buffers not loaded | CRITICAL | Invalid computation | Medium |
| #3: Tile index not used | CRITICAL | Incomplete computation | High |
| #4: State machine incomplete | CRITICAL | Wrong sequencing | High |

**Overall Assessment:** The integration module has fundamental design issues that require significant rework.

---

## Recommended Approach

### Option 1: Fix Current Design (Estimated: 4-6 hours)

**Pros:**
- Preserves existing architecture
- Incremental fixes

**Cons:**
- Multiple interconnected bugs
- High risk of introducing new bugs
- Complex state machine

### Option 2: Simplify Design (Estimated: 2-3 hours)

**Pros:**
- Cleaner implementation
- Easier to verify
- Better performance

**Cons:**
- Requires rewriting streaming_attention.v
- Previous work discarded

**Recommendation:** Option 2 - Simplify the design

**Simplified approach:**
- Remove tile-based processing (process 1 element at a time)
- Simpler state machine
- Sequential dot product (slower but correct)
- Get it working first, optimize later

---

## Conclusion

The integration test revealed fundamental bugs in the streaming_attention module:
1. Datapath not connected (dp_a, dp_b not driven)
2. Buffers not loaded (K, V never read)
3. Tile iteration not implemented
4. State machine incomplete

**These are not minor bugs - they require significant rework.**

**Recommendation:** Simplify the design to get a working baseline, then optimize.

---

**Status:** Critical bugs identified, fixes required  
**Next Action:** Redesign streaming_attention.v with simplified approach  
**Estimated Time:** 2-3 hours for simplified version
