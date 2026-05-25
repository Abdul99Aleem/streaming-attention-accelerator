# Tiled Streaming Attention - Design Document
**Module:** streaming_attention_v4  
**Date:** 2026-04-03  
**Purpose:** Detailed architecture and implementation specification

---

## Design Overview

**Module Name:** `streaming_attention_v4`  
**Purpose:** High-performance tiled attention computation with 13.5× speedup over v3  
**Key Feature:** Parallel processing of 16 elements per cycle using tile-based architecture

### Design Goals

1. **Performance:** Reduce cycle count from 9,824 to ~728 cycles
2. **Efficiency:** Utilize DSP48 slices for parallel MAC operations
3. **Correctness:** Maintain proper softmax computation from v3
4. **Simplicity:** Clear state machine with predictable timing

---

## Architecture Diagram

```
                    ┌─────────────────────────────────────┐
                    │   streaming_attention_v4            │
                    │                                     │
    start ─────────>│  ┌──────────────────────────────┐  │
                    │  │   State Machine Controller    │  │
                    │  │   (13 states)                 │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
                    │            ▼                        │
                    │  ┌──────────────────────────────┐  │
    Q_mem ─────────>│  │   Tile Buffer (16 elements)  │  │
    K_mem ─────────>│  │   - Q tile: 16×INT8          │  │
    V_mem ─────────>│  │   - K tile: 16×INT8          │  │
                    │  │   - V tile: 16×INT8          │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
                    │            ▼                        │
                    │  ┌──────────────────────────────┐  │
                    │  │   Parallel MAC Array         │  │
                    │  │   16 MAC units (DSP48)       │  │
                    │  │   Each: acc += a[i] × b[i]   │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
                    │            ▼                        │
                    │  ┌──────────────────────────────┐  │
                    │  │   Adder Tree (4 levels)      │  │
                    │  │   16 → 8 → 4 → 2 → 1         │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
                    │            ▼                        │
                    │  ┌──────────────────────────────┐  │
                    │  │   Score Accumulator          │  │
                    │  │   Accumulates partial sums   │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
                    │            ▼                        │
                    │  ┌──────────────────────────────┐  │
                    │  │   Softmax Unit v2            │  │
                    │  │   (19 cycles)                │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
                    │            ▼                        │
                    │  ┌──────────────────────────────┐  │
                    │  │   Output Accumulator         │  │
                    │  │   Weighted sum computation   │  │
                    │  └──────────────────────────────┘  │
                    │            │                        │
    done <──────────│            ▼                        │
    Out_mem <───────│  Output Write                      │
                    └─────────────────────────────────────┘
```

---

## Module Interface

### Parameters

```verilog
parameter L = 8;              // Sequence length
parameter D = 64;             // Embedding dimension
parameter TILE_WIDTH = 16;    // Parallel processing width
```

### Ports

```verilog
// Control signals
input  wire        clk;           // 100 MHz clock
input  wire        rst_n;         // Active-low reset
input  wire        start;         // Start computation
output reg         done;          // Computation complete
output reg         busy;          // Module busy

// Q matrix memory interface (read-only)
output reg  [9:0]  q_addr;        // Address: 0 to L×D-1
output reg         q_rd_en;       // Read enable
input  wire [127:0] q_data;       // 16 INT8 elements (128 bits)

// K matrix memory interface (read-only)
output reg  [9:0]  k_addr;        // Address: 0 to L×D-1
output reg         k_rd_en;       // Read enable
input  wire [127:0] k_data;       // 16 INT8 elements (128 bits)

// V matrix memory interface (read-only)
output reg  [9:0]  v_addr;        // Address: 0 to L×D-1
output reg         v_rd_en;       // Read enable
input  wire [127:0] v_data;       // 16 INT8 elements (128 bits)

// Output memory interface (write-only)
output reg  [9:0]  out_addr;      // Address: 0 to L×D-1
output reg  [127:0] out_data;     // 16 INT8 elements (128 bits)
output reg         out_wr_en;     // Write enable

// Configuration
input  wire [2:0]  scale_shift;   // Scaling factor for Q·K^T
```

**Key Changes from v3:**
- Memory interfaces now 128 bits wide (16×8 bits) instead of 8 bits
- Addresses now point to tile boundaries (multiples of 16)
- Single cycle reads/writes 16 elements instead of 1

---

## State Machine Design

### State Definitions

```verilog
localparam IDLE              = 4'd0;   // Wait for start
localparam LOAD_Q_TILE       = 4'd1;   // Load 16 elements of Q
localparam SCORE_INIT        = 4'd2;   // Initialize score computation
localparam SCORE_TILE_LOAD   = 4'd3;   // Load K tile
localparam SCORE_TILE_COMPUTE = 4'd4;  // Compute partial dot product
localparam SCORE_ACCUMULATE  = 4'd5;   // Accumulate to score
localparam SCORE_NEXT_TILE   = 4'd6;   // Move to next tile
localparam SCORE_NEXT_KEY    = 4'd7;   // Move to next key
localparam SOFTMAX_START     = 4'd8;   // Start softmax
localparam SOFTMAX_WAIT      = 4'd9;   // Wait for softmax
localparam OUTPUT_INIT       = 4'd10;  // Initialize output computation
localparam OUTPUT_TILE_COMPUTE = 4'd11; // Compute weighted tile
localparam OUTPUT_ACCUMULATE = 4'd12;  // Accumulate to output
localparam WRITE_OUTPUT      = 4'd13;  // Write output row
localparam NEXT_QUERY        = 4'd14;  // Move to next query
```

### State Transition Diagram

```
IDLE ──start──> LOAD_Q_TILE
                     │
                     ▼
              SCORE_INIT ◄─────────────┐
                     │                 │
                     ▼                 │
           SCORE_TILE_LOAD             │
                     │                 │
                     ▼                 │
         SCORE_TILE_COMPUTE            │
                     │                 │
                     ▼                 │
          SCORE_ACCUMULATE             │
                     │                 │
                     ▼                 │
           SCORE_NEXT_TILE             │
                     │                 │
              tile_idx < D/W? ─────────┘
                     │ No
                     ▼
            SCORE_NEXT_KEY
                     │
              key_idx < L? ────────────┐
                     │ No              │
                     ▼                 │
             SOFTMAX_START             │
                     │                 │
                     ▼                 │
              SOFTMAX_WAIT             │
                     │                 │
                     ▼                 │
              OUTPUT_INIT ◄────────────┤
                     │                 │
                     ▼                 │
        OUTPUT_TILE_COMPUTE            │
                     │                 │
                     ▼                 │
         OUTPUT_ACCUMULATE             │
                     │                 │
              tile_idx < D/W? ─────────┘
                     │ No
                     ▼
             WRITE_OUTPUT
                     │
                     ▼
              NEXT_QUERY
                     │
              query_idx < L? ──────────┐
                     │ No              │
                     ▼                 │
                  IDLE                 │
                     ▲                 │
                     └─────────────────┘
```

### State Descriptions

**IDLE:**
- Wait for `start` signal
- Initialize all counters to 0
- Transition: start → LOAD_Q_TILE

**LOAD_Q_TILE:**
- Load entire Q row (D elements) in D/W cycles
- Store in Q tile buffer
- Transition: After D/W cycles → SCORE_INIT

**SCORE_INIT:**
- Initialize score computation for current query
- Set key_idx = 0, tile_idx = 0
- Clear partial score accumulator
- Transition: Immediate → SCORE_TILE_LOAD

**SCORE_TILE_LOAD:**
- Load W elements of K[key_idx] starting at tile_idx×W
- Issue read: k_addr = key_idx×D + tile_idx×W
- Transition: After 1 cycle (BRAM latency) → SCORE_TILE_COMPUTE

**SCORE_TILE_COMPUTE:**
- Compute partial dot product: Q_tile · K_tile
- Uses 16 parallel MAC units
- Result available after 1 cycle
- Transition: Immediate → SCORE_ACCUMULATE

**SCORE_ACCUMULATE:**
- Add partial result to score accumulator
- score[key_idx] += partial_dot_product
- Transition: Immediate → SCORE_NEXT_TILE

**SCORE_NEXT_TILE:**
- Increment tile_idx
- Check if all tiles processed
- Transition: 
  - If tile_idx < D/W → SCORE_TILE_LOAD
  - Else → SCORE_NEXT_KEY

**SCORE_NEXT_KEY:**
- Increment key_idx
- Reset tile_idx = 0
- Transition:
  - If key_idx < L → SCORE_INIT
  - Else → SOFTMAX_START

**SOFTMAX_START:**
- Assert softmax_start signal
- Pass scores[0:L-1] to softmax unit
- Transition: Immediate → SOFTMAX_WAIT

**SOFTMAX_WAIT:**
- Wait for softmax_valid signal
- Copy attention weights when valid
- Transition: When softmax_valid → OUTPUT_INIT

**OUTPUT_INIT:**
- Initialize output computation
- Set value_idx = 0, tile_idx = 0
- Clear output accumulator
- Transition: Immediate → OUTPUT_TILE_COMPUTE

**OUTPUT_TILE_COMPUTE:**
- Load V tile: v_addr = value_idx×D + tile_idx×W
- Compute: output_tile += attention_weight[value_idx] × V_tile
- Uses 16 parallel multipliers
- Transition: After 2 cycles → OUTPUT_ACCUMULATE

**OUTPUT_ACCUMULATE:**
- Add weighted tile to output accumulator
- Increment value_idx
- Transition:
  - If value_idx < L → OUTPUT_TILE_COMPUTE
  - Else → tile_idx++, value_idx=0
  - If tile_idx == D/W → WRITE_OUTPUT

**WRITE_OUTPUT:**
- Write output row to memory in D/W cycles
- out_addr = query_idx×D + tile_idx×W
- out_data = output_buffer[tile_idx×W : (tile_idx+1)×W-1]
- Transition: After D/W cycles → NEXT_QUERY

**NEXT_QUERY:**
- Increment query_idx
- Transition:
  - If query_idx < L → LOAD_Q_TILE
  - Else → IDLE (done = 1)

---

## Datapath Design

### Tile Buffers

```verilog
// Q tile buffer - stores current query row
reg signed [7:0] q_tile [0:D-1];

// K tile buffer - stores current key tile
reg signed [7:0] k_tile [0:TILE_WIDTH-1];

// V tile buffer - stores current value tile
reg signed [7:0] v_tile [0:TILE_WIDTH-1];

// Output buffer - accumulates weighted values
reg signed [31:0] output_buffer [0:D-1];
```

### Parallel MAC Array

```verilog
// 16 MAC units for parallel computation
wire [31:0] mac_out [0:TILE_WIDTH-1];

genvar i;
generate
    for (i = 0; i < TILE_WIDTH; i = i + 1) begin : mac_array
        mac_int8 mac_inst (
            .clk(clk),
            .rst_n(rst_n),
            .clear(mac_clear),
            .enable(mac_enable),
            .a(q_tile[tile_idx*TILE_WIDTH + i]),
            .b(k_tile[i]),
            .acc(mac_out[i])
        );
    end
endgenerate
```

### Adder Tree

```verilog
// 4-level adder tree to sum 16 MAC outputs
reg signed [31:0] sum_level1 [0:7];   // 16 → 8
reg signed [31:0] sum_level2 [0:3];   // 8 → 4
reg signed [31:0] sum_level3 [0:1];   // 4 → 2
reg signed [31:0] sum_final;          // 2 → 1

// Level 1: Add pairs
always @(posedge clk) begin
    for (j = 0; j < 8; j = j + 1) begin
        sum_level1[j] <= mac_out[2*j] + mac_out[2*j+1];
    end
end

// Level 2: Add pairs
always @(posedge clk) begin
    for (j = 0; j < 4; j = j + 1) begin
        sum_level2[j] <= sum_level1[2*j] + sum_level1[2*j+1];
    end
end

// Level 3: Add pairs
always @(posedge clk) begin
    for (j = 0; j < 2; j = j + 1) begin
        sum_level3[j] <= sum_level2[2*j] + sum_level2[2*j+1];
    end
end

// Final: Add last pair
always @(posedge clk) begin
    sum_final <= sum_level3[0] + sum_level3[1];
end
```

### Score Storage

```verilog
// Store attention scores for all L keys
reg signed [31:0] scores [0:L-1];

// Accumulate partial dot products
always @(posedge clk) begin
    if (state == SCORE_ACCUMULATE) begin
        scores[key_idx] <= scores[key_idx] + sum_final;
    end
end
```

### Softmax Integration

```verilog
// Softmax unit instance
reg softmax_start;
wire [15:0] attention_weights [0:L-1];
wire softmax_valid;

softmax_unit_v2 #(
    .L(L),
    .EXP_LUT_SIZE(256)
) softmax_inst (
    .clk(clk),
    .rst_n(rst_n),
    .start(softmax_start),
    .scores(scores),
    .weights(attention_weights),
    .valid(softmax_valid),
    .ready()
);
```

---

## Timing Analysis

### Cycle Count Derivation

**Per Query (L=8, D=64, W=16):**

```
1. Load Q row:
   - D/W cycles = 64/16 = 4 cycles
   
2. Compute scores for all L keys:
   For each key (8 keys):
       For each tile (4 tiles):
           - Load K tile: 1 cycle
           - Compute partial dot: 1 cycle
           - Accumulate: 1 cycle
           Total per tile: 3 cycles
       Total per key: 4 tiles × 3 cycles = 12 cycles
   Total for all keys: 8 × 12 = 96 cycles
   
3. Softmax:
   - 19 cycles (from softmax_unit_v2)
   
4. Compute output:
   For each tile (4 tiles):
       For each value (8 values):
           - Load V tile: 1 cycle
           - Multiply by weight: 1 cycle
           - Accumulate: 1 cycle
           Total per value: 3 cycles
       Total per tile: 8 × 3 = 24 cycles
   Total: 4 × 24 = 96 cycles
   
5. Write output:
   - D/W cycles = 4 cycles

Total per query: 4 + 96 + 19 + 96 + 4 = 219 cycles
```

**For All L=8 Queries:**
```
Total: 8 × 219 = 1,752 cycles
```

**Comparison:**

| Version | Cycles | Time @ 100MHz | Speedup |
|---------|--------|---------------|---------|
| v3 (sequential) | 9,824 | 98.24 μs | 1× |
| v4 (tiled) | 1,752 | 17.52 μs | 5.6× |

**Note:** This is more conservative than the 728-cycle prediction in the learning doc because it accounts for:
- BRAM read latency (1 cycle)
- Adder tree pipeline depth (3 cycles)
- State transition overhead

---

## Memory Interface Design

### Address Calculation

**Q matrix:**
```
q_addr = query_idx × D + tile_idx × TILE_WIDTH
Range: 0 to (L×D - TILE_WIDTH)
```

**K matrix:**
```
k_addr = key_idx × D + tile_idx × TILE_WIDTH
Range: 0 to (L×D - TILE_WIDTH)
```

**V matrix:**
```
v_addr = value_idx × D + tile_idx × TILE_WIDTH
Range: 0 to (L×D - TILE_WIDTH)
```

**Output:**
```
out_addr = query_idx × D + tile_idx × TILE_WIDTH
Range: 0 to (L×D - TILE_WIDTH)
```

### Memory Bandwidth Requirements

**Read Bandwidth:**
- Q: 4 reads × 128 bits = 512 bits per query
- K: 8 keys × 4 tiles × 128 bits = 4,096 bits per query
- V: 8 values × 4 tiles × 128 bits = 4,096 bits per query
- Total: 8,704 bits per query

**Write Bandwidth:**
- Output: 4 writes × 128 bits = 512 bits per query

**Peak Bandwidth:**
- 128 bits per cycle during tile loads
- Sustainable with dual-port BRAM (72 bits/port × 2 = 144 bits/cycle)

---

## Resource Utilization Estimates

### DSP48 Slices

**MAC Array:** 16 DSP48 slices  
**Softmax:** 0 DSP48 slices (uses fabric)  
**Total:** 16 DSP48 slices

**Utilization:** 16/220 = 7.3%

### LUTs

**State Machine:** ~500 LUTs  
**Address Generation:** ~300 LUTs  
**Tile Buffers:** ~800 LUTs  
**Adder Tree:** ~400 LUTs  
**Softmax Unit:** ~1,500 LUTs  
**Control Logic:** ~500 LUTs  
**Total:** ~4,000 LUTs

**Utilization:** 4,000/53,200 = 7.5%

### Flip-Flops

**State Registers:** ~100 FFs  
**Tile Buffers:** ~2,048 FFs (16×8 + 64×8 + 16×8)  
**Score Storage:** ~256 FFs (8×32)  
**Output Buffer:** ~2,048 FFs (64×32)  
**Pipeline Registers:** ~500 FFs  
**Total:** ~5,000 FFs

**Utilization:** 5,000/106,400 = 4.7%

### BRAMs

**Q Matrix:** 1 BRAM (512 bytes)  
**K Matrix:** 1 BRAM (512 bytes)  
**V Matrix:** 1 BRAM (512 bytes)  
**Output:** 1 BRAM (512 bytes)  
**Exp LUT:** 1 BRAM (512 bytes)  
**Total:** 5 BRAMs

**Utilization:** 5/140 = 3.6%

---

## Critical Path Analysis

**Longest combinational path:**

```
MAC output → Adder Level 1 → Adder Level 2 → Adder Level 3 → Final Sum → Score Accumulator
```

**Estimated Delay:**
- MAC output: 0 ns (registered)
- Adder Level 1: 2 ns
- Adder Level 2: 2 ns
- Adder Level 3: 2 ns
- Final Sum: 2 ns
- Setup time: 1 ns
- **Total: 9 ns**

**Timing Margin @ 100 MHz:**
- Clock period: 10 ns
- Critical path: 9 ns
- **Margin: 1 ns (10% slack)** ✓

**Mitigation if timing fails:**
- Add pipeline stage after Level 2
- Reduces critical path to 6 ns
- Increases latency by 1 cycle per tile

---

## Design Validation Checklist

Before implementation, verify:

- [ ] All states defined and transitions specified
- [ ] Cycle count derivation matches predictions
- [ ] Memory bandwidth within BRAM capabilities
- [ ] Resource estimates within device limits
- [ ] Critical path meets timing requirements
- [ ] Interface compatible with existing testbench
- [ ] Softmax integration matches v3 approach
- [ ] All edge cases handled (first/last tile, etc.)

---

## Assumptions

1. **BRAM Latency:** 1 cycle read latency (standard for Xilinx BRAM)
2. **Clock Frequency:** 100 MHz (10 ns period)
3. **Memory Width:** BRAMs configured for 128-bit wide access
4. **Alignment:** D is multiple of TILE_WIDTH (64 % 16 = 0) ✓
5. **Synthesis:** Vivado will infer DSP48 for MAC operations
6. **Timing:** Adder tree meets timing at 100 MHz

---

## Next Steps

After design review:
1. Create performance analysis document (predicted vs measured)
2. Implement RTL (streaming_attention_v4.v)
3. Update testbench for 128-bit memory interface
4. Simulate and measure actual cycle count
5. Compare measured vs predicted performance
6. Run synthesis to verify resource utilization

---

**Status:** Design complete - ready for analysis phase  
**User Action Required:** Review design before proceeding to analysis
