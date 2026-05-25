# PROJECT REQUIREMENTS DOCUMENT
## Streaming Transformer Attention Accelerator with AXI-Stream Dataflow
### Hardware-Software Co-Design on Xilinx Zynq FPGA

---

## Project Identity

**Title:** Streaming Transformer Attention Accelerator on Zynq FPGA

**Tagline:** Real GPT-2 weights, tiled dataflow, AXI-Stream, measured throughput — built from scratch in RTL

**Target Audience:** AMD / Qualcomm hardware engineering interviews

**Duration:** 4 weeks (1 month)

**Primary Skills Demonstrated:**
- RTL design and verification (Verilog)
- AXI-Stream dataflow architecture
- Memory hierarchy and tiling strategy
- Fixed-point numerical analysis
- Hardware-software co-design
- Performance measurement and bottleneck analysis

**Resume Bullet (fill X, Y, Z after completion):**
> *"Implemented and analyzed transformer attention kernel on Zynq FPGA — tiled INT8 matmul, LUT-based fixed-point softmax, AXI-Stream dataflow; quantified compute vs memory tradeoffs via hardware performance counters (X% utilization, Y% stall), verified INT8 output within Z% of float32 reference across 100 trials"*

**Internal framing (internalize this, do not say it out loud):**
"I implemented and measured every design tradeoff in a transformer attention dataflow on real hardware." Not: "I built an AI accelerator." Not: "This is like a TPU."

---

## Problem Statement

Running transformer inference on cheap embedded hardware is unsolved at the RTL level. Existing solutions (TFLite, ONNX Runtime) are software-only and cannot exploit custom silicon parallelism. This project builds a hardware attention engine that demonstrates the core techniques used in real NPUs and AI accelerators — tiled compute, streaming dataflow, backpressure handling, and measured performance — on a $200 Zynq board.

---

## Design Parameters

| Parameter | Value | Rationale |
|---|---|---|
| Embedding dimension | 64 | Fits BRAM, maps to systolic array from Project 1 |
| Sequence length | 8 tokens | Weekend-feasible, shows attention pattern |
| Tile width | 16 | Fits distributed RAM, reusable compute |
| Attention heads | 1 | Isolates mechanism, multi-head is parallel replication |
| Weight precision | INT8 | Reuses quantization pipeline from Project 1 |
| Accumulator precision | INT32 | Prevents overflow during tiled matmul |
| Softmax precision | Fixed-point 16-bit | LUT-based exp, real softmax not approximation |
| Interface (data) | AXI-Stream | Burst-capable, backpressure-native |
| Interface (control) | AXI-Lite | Register map for start/done/counters |
| Target FPGA | xc7z020clg400-1 | Zynq-7020 (ZedBoard or equivalent) |
| Clock target | 100 MHz | Achievable with clean RTL |
| Software side | Python (pynq or mmap) | PS-side weight loading and result readback |

---

## Analytical Model (Predict Before You Build)

**This section must be completed before Phase 2 begins. Predict every number. Measure it. Explain every deviation.**

### Compute Model

```
MAC operations per inference:
  QKV projection:  3 × (8 × 64 × 64) = 98,304 MACs
  Score (QK^T):    8 × 8 × 64        =  4,096 MACs
  Attend (AW×V):   8 × 64 × 8        =  4,096 MACs
  Total:                               106,496 MACs

Parallelism: 16 MACs active per cycle (TILE_W=16)

Theoretical minimum cycles:
  = 106,496 / 16 = 6,656 cycles

At 100MHz:
  = 66.56 μs theoretical minimum
```

### Memory Model

```
Bytes moved per tile (one projection):
  Weight tile:  16 × 64 × 1 byte  = 1,024 bytes
  Input tile:    8 × 16 × 1 byte  =   128 bytes
  Output accum:  8 × 64 × 4 bytes = 2,048 bytes (INT32)

Tiles per projection: 4
Total per projection: 4 × (1024 + 128 + 2048) = 13,184 bytes
Three projections:    39,552 bytes total memory traffic

BRAM bandwidth at 100MHz (1 read/write per cycle):
  Available: ~800 MB/s (dual-port BRAM, 8-byte wide)
  Required:  16 bytes/cycle × 100MHz = 1.6 GB/s peak

Conclusion: BRAM bandwidth is the primary constraint.
Tiling reduces effective requirement to 800 MB/s — just fits.
```

### Predicted Latency Breakdown

```
Before implementation, fill this in:

Stage          | Predicted Cycles | Reasoning
---------------|-----------------|----------------------------------
QKV (parallel) | ___             | 4 tiles × 8 rows × 64/16 MACs
Score (QK^T)   | ___             | 64 dot products, 8 parallel MACs
Softmax        | ___             | 15 cycles × 8 rows
Attend (AW×V)  | ___             | 8 × 64 output elements, 8 MACs
FSM overhead   | ___             | State transitions between stages
Tile boundary  | ___             | 4 cycles × 4 boundaries × 3 proj
BRAM latency   | ___             | 2 cycle read latency × tile starts
---------------|-----------------|----------------------------------
TOTAL PREDICTED| ___             |

After implementation, fill measured values and explain delta.
```

### Bottleneck Prediction (answer before Phase 2)

```
Question: Is this design compute-bound or memory-bound?

Compute bound if: MAC utilization > 80%
Memory bound if:  Stall cycles > 20%

My prediction: _______________
Reasoning:     _______________

Verify with perf_counters.v after Phase 3.
```

---

## Scaling Study (analysis only — no RTL implementation)

**Complete this in docs/architecture.md before Phase 3.**

```
Current design parameters: seq_len=8, embed_dim=64, tile_w=16

Derive what happens as you scale:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scaling seq_len (8 → 64 → 256):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

QKV compute scales as:     O(seq_len × embed_dim²)
Score matrix scales as:    O(seq_len²)  ← quadratic
Attend compute scales as:  O(seq_len²)

Score matrix BRAM requirement:
  seq=8:   8×8×4B   = 256B    ← fits in registers
  seq=64:  64×64×4B = 16KB    ← needs BRAM
  seq=256: 256×256×4B = 256KB ← exceeds Zynq BRAM

First constraint broken at seq_len = ___
Reason: ___

Required architectural change: ___
(hint: tiled score computation, streaming softmax)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scaling embed_dim (64 → 256 → 768):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Weight matrix BRAM requirement (per projection):
  dim=64:  64×64×1B  = 4KB    ← fits easily
  dim=256: 256×256×1B = 64KB  ← uses 50% of Zynq BRAM
  dim=768: 768×768×1B = 576KB ← 12× BRAM capacity

First constraint broken at embed_dim = ___
Required architectural change: ___
(hint: weight streaming from DDR, double-buffer layers)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scaling both simultaneously:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

At what (seq_len, embed_dim) does this design break?
Fill in the table:

seq_len | embed_dim | Fits? | First constraint broken
--------|-----------|-------|------------------------
      8 |        64 |  YES  | ← current
      8 |       256 |       |
     64 |        64 |       |
     64 |       256 |       |
    256 |        64 |       |
    256 |       256 |       |
```

---

## Complete File Structure

```
streaming-attention-accelerator/
│
├── rtl/
│   ├── primitives/
│   │   ├── mac_unit.v              ← reused from Project 1
│   │   └── reg_slice.v             ← pipeline register slice
│   │
│   ├── compute/
│   │   ├── tiled_matmul.v          ← core tiled INT8 matmul
│   │   ├── tile_controller.v       ← FSM for tile sequencing
│   │   ├── accumulator.v           ← INT32 tile accumulator
│   │   └── double_buffer.v         ← ping-pong buffer for tiles
│   │
│   ├── softmax/
│   │   ├── softmax_lut.v           ← LUT-based exp (256 entry)
│   │   ├── max_finder.v            ← parallel tree max reduction
│   │   ├── reciprocal_lut.v        ← LUT-based division
│   │   └── softmax_pipeline.v      ← full softmax top level
│   │
│   ├── streaming/
│   │   ├── stream_fifo.v           ← AXI-Stream FIFO
│   │   ├── stream_splitter.v       ← 1-to-3 for Q/K/V paths
│   │   └── stream_merger.v         ← merge output streams
│   │
│   ├── attention/
│   │   ├── qkv_projection.v        ← parallel Q, K, V matmul
│   │   ├── score_engine.v          ← QK^T computation
│   │   ├── attend_engine.v         ← softmax(QK^T)×V
│   │   └── attention_pipeline.v    ← full attention top level
│   │
│   ├── infrastructure/
│   │   ├── axi_lite_slave.v        ← control/status registers
│   │   ├── axi_stream_master.v     ← DMA-style stream source
│   │   ├── axi_stream_slave.v      ← DMA-style stream sink
│   │   └── perf_counters.v         ← cycle/stall/util counters
│   │
│   └── top/
│       └── top.v                   ← full system integration
│
├── tb/
│   ├── unit/
│   │   ├── tb_mac_unit.v
│   │   ├── tb_tiled_matmul.v
│   │   ├── tb_double_buffer.v
│   │   ├── tb_softmax_lut.v
│   │   ├── tb_stream_fifo.v
│   │   └── tb_perf_counters.v
│   │
│   ├── integration/
│   │   ├── tb_qkv_projection.v
│   │   ├── tb_score_engine.v
│   │   ├── tb_attention_pipeline.v
│   │   └── tb_top.v
│   │
│   └── scripts/
│       ├── run_unit_tests.tcl
│       └── run_integration_tests.tcl
│
├── python/
│   ├── weight_extraction/
│   │   ├── extract_weights.py      ← pull Q,K,V from GPT-2
│   │   ├── quantize_weights.py     ← float32 → INT8
│   │   └── export_mem_files.py     ← generate .mem for Verilog
│   │
│   ├── reference/
│   │   ├── reference_attention.py  ← float32 PyTorch golden
│   │   ├── int8_attention.py       ← INT8 numpy reference
│   │   └── lut_softmax.py          ← Python model of LUT softmax
│   │
│   ├── verification/
│   │   ├── generate_test_vectors.py← create sim input/output pairs
│   │   ├── compare_outputs.py      ← RTL vs reference comparison
│   │   └── error_analysis.py       ← statistical error reporting
│   │
│   ├── inference/
│   │   ├── run_inference.py        ← PS→PL→PS full inference
│   │   ├── benchmark.py            ← latency + throughput measurement
│   │   └── profile_bottleneck.py   ← DMA vs compute breakdown
│   │
│   └── visualization/
│       ├── plot_attention_map.py   ← visualize attention weights
│       ├── plot_latency.py         ← latency breakdown charts
│       └── plot_error_dist.py      ← error distribution histogram
│
├── mem/
│   ├── wq.mem                      ← Q projection weights (INT8 hex)
│   ├── wk.mem                      ← K projection weights (INT8 hex)
│   ├── wv.mem                      ← V projection weights (INT8 hex)
│   ├── exp_lut.mem                 ← exp() lookup table (256 entry)
│   ├── recip_lut.mem               ← reciprocal LUT for softmax
│   └── test_input.mem              ← test token embeddings
│
├── vivado/
│   ├── create_project.tcl          ← full project creation script
│   ├── run_synthesis.tcl           ← synthesis + reports
│   ├── run_implementation.tcl      ← implementation + bitstream
│   └── constraints/
│       └── top.xdc                 ← timing + pin constraints
│
├── docs/
│   ├── architecture.md             ← full system architecture
│   ├── analytical_model.md         ← predicted vs measured breakdown
│   ├── register_map.md             ← AXI-lite register map
│   ├── timing_analysis.md          ← critical path analysis
│   ├── performance_report.md       ← measured metrics + experiments
│   └── interview_prep.md           ← Q&A defense guide
│
├── Makefile
├── requirements.txt
├── .gitignore
└── README.md
```

---

## AXI-Lite Register Map

| Address | Name | R/W | Description |
|---|---|---|---|
| 0x000 | CTRL | W | bit0=start, bit1=reset |
| 0x004 | STATUS | R | bit0=done, bit1=busy, bit2=error |
| 0x008 | SEQ_LEN | W | sequence length (default 8) |
| 0x00C | EMB_DIM | W | embedding dim (default 64) |
| 0x010 | CYCLE_COUNT | R | total cycles since start |
| 0x014 | STALL_CYCLES | R | cycles with no valid data |
| 0x018 | COMPUTE_CYCLES | R | cycles with active compute |
| 0x01C | DMA_CYCLES | R | cycles waiting for DMA |
| 0x020 | TILE_COUNT | R | tiles processed so far |
| 0x024 | ERROR_FLAGS | R | overflow, underflow flags |
| 0x100-0x1FF | INPUT_BUF | W | input embeddings (256 bytes) |
| 0x200-0x5FF | OUTPUT_BUF | R | attention output (1024 bytes) |

---

## Performance Counters (mandatory)

Every cycle, hardware must track:

```verilog
// Inside perf_counters.v
always @(posedge clk) begin
    if (start) cycle_count <= cycle_count + 1;

    if (start && !data_valid_in)
        stall_cycles <= stall_cycles + 1;      // waiting for data

    if (compute_active)
        compute_cycles <= compute_cycles + 1;  // doing real work

    if (dma_wait)
        dma_cycles <= dma_cycles + 1;          // waiting for DMA
end

// Derived metric (reported in Python)
// compute_utilization = compute_cycles / cycle_count × 100%
```

---

## Dataflow Architecture

```
PS (ARM) — Python
    │
    │  [write input embeddings via AXI-lite]
    │
    ▼
┌─────────────────────────────────────────────────────┐
│                    PL (FPGA Fabric)                 │
│                                                     │
│  INPUT_BUF (256 bytes)                              │
│      │                                              │
│      ▼                                              │
│  stream_splitter ──────────────────────────────┐   │
│      │              │                          │   │
│      ▼              ▼                          ▼   │
│  Q_matmul       K_matmul                   V_matmul │
│  (tiled)        (tiled)                    (tiled)  │
│  wq.mem         wk.mem                     wv.mem  │
│      │              │                          │   │
│      └──────┬────────┘                         │   │
│             ▼                                  │   │
│         score_engine                           │   │
│         (QK^T, tile by tile)                   │   │
│             │                                  │   │
│             ▼                                  │   │
│         scale_unit (>> 3)                      │   │
│             │                                  │   │
│             ▼                                  │   │
│         softmax_pipeline                       │   │
│         (max→exp LUT→recip LUT→normalize)      │   │
│             │                                  │   │
│             └──────────────┬───────────────────┘   │
│                            ▼                       │
│                      attend_engine                 │
│                      (attn_weights × V)            │
│                            │                       │
│                            ▼                       │
│                      OUTPUT_BUF (1024 bytes)       │
│                            │                       │
│                      perf_counters                 │
│                      (cycle/stall/util tracking)   │
└─────────────────────────────────────────────────────┘
    │
    │  [read output + performance counters via AXI-lite]
    │
    ▼
PS (ARM) — Python
    - compare vs PyTorch reference
    - report latency, throughput, error
    - plot attention map
```

---

## Tiling Strategy

Instead of loading full 64×64 weight matrix at once:

```
Full matmul: input(8×64) × weight(64×64) → output(8×64)

Tiled execution (tile_width=16):
  Tile 0: input(8×16) × weight_cols(16×64)[0:16]   → partial(8×64)
  Tile 1: input(8×16) × weight_cols(16×64)[16:32]  → accumulate
  Tile 2: input(8×16) × weight_cols(16×64)[32:48]  → accumulate
  Tile 3: input(8×16) × weight_cols(16×64)[48:64]  → final output

Each tile fits in distributed RAM (16×64 INT8 = 1KB)
Full weight matrix stays in BRAM (64×64 INT8 = 4KB per projection)
Double buffer: load tile N+1 while computing tile N
```

---

## LUT Softmax Design

```
Step 1 — Find max (parallel tree reduction, 3 cycles for 8 values)
Step 2 — Subtract max from all 8 scores (numerical stability)
Step 3 — exp() via 256-entry LUT (1 cycle per element)
          LUT generated in Python: [int(exp(x/8)*128) for x in range(256)]
Step 4 — Sum all exp values
Step 5 — Normalize via reciprocal LUT (1 cycle per element)
          recip_lut[sum] = 256/sum (pre-computed)
Step 6 — Output: 8 normalized attention weights (INT16)

Total latency: ~15 cycles for 8 values
Error vs true softmax: < 1% (LUT resolution 1/256)
```

---

---

# PHASE 1 — Foundation and Python Infrastructure
## Week 1 | Days 1–7

**Goal:** Before writing a single line of RTL, build the complete Python reference stack. Every RTL module you build in later phases will be verified against these Python models. This is non-negotiable — RTL without a reference model is debugging in the dark.

---

### Phase 1 Objectives

- Extract real GPT-2 weights and understand their structure
- Build float32 golden reference (source of truth)
- Build INT8 numpy reference (matches what RTL will compute)
- Build Python model of LUT softmax (matches what softmax RTL will compute)
- Generate test vectors for every RTL module
- Validate numerical accuracy of INT8 vs float32
- Complete the analytical model with all predicted values before any RTL

---

### Phase 1 Tasks

**Task 1.1 — Environment Setup**

```bash
# Create project structure
mkdir -p streaming-attention-accelerator/{rtl/{primitives,compute,softmax,streaming,attention,infrastructure,top},tb/{unit,integration,scripts},python/{weight_extraction,reference,verification,inference,visualization},mem,vivado/constraints,docs}

cd streaming-attention-accelerator
git init
pip install torch transformers numpy scipy matplotlib pynq
```

**Task 1.2 — GPT-2 Weight Extraction**

Claude Code prompt:
```
Create python/weight_extraction/extract_weights.py that:

- Loads GPT-2 small using HuggingFace transformers library
- Extracts from transformer layer 0, attention head 0:
  - W_Q: query projection weight matrix
  - W_K: key projection weight matrix
  - W_V: value projection weight matrix
- Full GPT-2 matrices are 768×768 — slice to 64×64
  (first 64 rows, first 64 cols of each)
- Prints: matrix shapes, dtype, min, max, mean, std for each
- Saves raw float32 matrices as .npy files in mem/ directory
- Also saves a summary JSON with all metadata

Create python/weight_extraction/quantize_weights.py that:
- Loads the .npy float32 matrices
- Applies symmetric per-tensor INT8 quantization:
  scale = max(abs(W)) / 127
  W_int8 = clip(round(W / scale), -127, 127)
- Reports for each matrix:
  - Scale factor used
  - Min/max before and after quantization
  - Mean absolute quantization error
  - Signal-to-quantization-noise ratio (SQNR) in dB
- Saves quantized matrices as .npy INT8 files

Create python/weight_extraction/export_mem_files.py that:
- Loads INT8 quantized .npy files
- Exports as hex .mem files (one value per line, 2-digit hex)
  compatible with Verilog $readmemh
- Files: mem/wq.mem, mem/wk.mem, mem/wv.mem
- Also generates mem/exp_lut.mem:
  256-entry LUT where entry[i] = int(exp((i-128)/16) * 128)
  clamped to 0..255 (unsigned 8-bit)
- Generates mem/recip_lut.mem:
  256-entry LUT where entry[i] = int(32768 / max(i, 1))
  (reciprocal scaled by 2^15, unsigned 16-bit)
- Prints first 8 and last 8 entries of each LUT for verification
```

**Task 1.3 — Float32 Golden Reference**

Claude Code prompt:
```
Create python/reference/reference_attention.py that:

- Implements single-head self-attention in PyTorch float32
- This is the ground truth — every other implementation
  is compared against this
- Uses extracted GPT-2 W_Q, W_K, W_V (float32, 64×64)
- Function signature:
  def attention_float32(x, wq, wk, wv):
    # x: (8, 64) float32 input embeddings
    # returns: (8, 64) float32 attention output
    Q = x @ wq.T          # (8, 64)
    K = x @ wk.T          # (8, 64)
    V = x @ wv.T          # (8, 64)
    scores = Q @ K.T      # (8, 8)
    scores = scores / sqrt(64)
    weights = softmax(scores, dim=-1)  # (8, 8)
    output = weights @ V  # (8, 64)
    return output, weights

- Generates 10 different random input sequences (8×64 float32)
- For each: runs attention, saves inputs and outputs
- Saves all test cases to mem/test_vectors.npy
- Prints attention weight matrix for first test case (8×8)
  so you can visually verify attention pattern
- Plots and saves attention heatmap as docs/attention_map.png
```

**Task 1.4 — INT8 Numpy Reference**

Claude Code prompt:
```
Create python/reference/int8_attention.py that:

- Implements the EXACT same attention computation as
  reference_attention.py but using INT8/INT32 numpy
- This must match what the RTL will compute exactly
- Quantization scheme must be identical to quantize_weights.py

def attention_int8(x_int8, wq_int8, wk_int8, wv_int8,
                   wq_scale, wk_scale, wv_scale, x_scale):
  # All matmuls in INT32 accumulator
  # Scale factors applied after each matmul
  # Score scaling: right shift by 3 (divide by 8, approx 1/sqrt(64))
  # No float operations anywhere

- For each of the 10 test vectors from Task 1.3:
  - Run float32 reference
  - Run INT8 numpy
  - Compute:
    - Max absolute error per element
    - Mean absolute error
    - Relative error percentage
    - Whether outputs agree within 5% threshold

- Saves comparison results to docs/int8_accuracy_report.json
- Prints summary table

Create python/reference/lut_softmax.py that:
- Implements softmax using EXACTLY the same LUT tables as
  the hardware will use (exp_lut.mem and recip_lut.mem)
- Input: 8 INT16 values (one attention score row)
- Output: 8 INT16 normalized attention weights
- Algorithm:
  1. Find max
  2. Subtract max, clamp to [-128, 0]
  3. Look up exp_lut for each value
  4. Sum exp values
  5. Look up recip_lut for sum
  6. Multiply each exp value by reciprocal, shift right 15
- Compare against scipy.special.softmax for same inputs
- Report max error vs true softmax

Also add a LUT precision experiment function:

def run_lut_experiment():
    lut_sizes = [64, 128, 256, 512, 1024]
    test_inputs = generate_random_score_rows(100)  # 100 × 8 INT16

    for size in lut_sizes:
        exp_lut = generate_exp_lut(size)
        errors = []
        for row in test_inputs:
            lut_out  = lut_softmax(row, exp_lut)
            true_out = scipy_softmax(row)
            errors.append(mean_abs_error(lut_out, true_out))

        print(f"LUT size {size:4d}: mean_err={mean(errors):.4f}%, "
              f"max_err={max(errors):.4f}%")

# Expected output pattern:
# LUT size   64: mean_err=X%   ← high error
# LUT size  128: mean_err=X%   ← diminishing returns start
# LUT size  256: mean_err=X%   ← current choice
# LUT size  512: mean_err=X%   ← marginal improvement
# LUT size 1024: mean_err=X%   ← essentially saturated
```

**Task 1.5 — Test Vector Generation**

Claude Code prompt:
```
Create python/verification/generate_test_vectors.py that:

Generates test vectors for EVERY RTL module that will be built:

1. MAC unit vectors:
   - 20 pairs of (a: INT8, b: INT8, acc_in: INT32)
   - Expected acc_out = acc_in + a*b
   - Save as mem/tb_mac_vectors.mem

2. Tiled matmul vectors:
   - 5 complete matmul inputs/outputs
   - Input: 8×64 INT8, weights: 64×64 INT8
   - Expected output: 8×64 INT32
   - Save as mem/tb_matmul_input.mem, mem/tb_matmul_expected.mem

3. Softmax LUT vectors:
   - 10 rows of 8 INT16 attention scores
   - Expected output from lut_softmax.py
   - Save as mem/tb_softmax_input.mem, mem/tb_softmax_expected.mem

4. Full attention vectors:
   - 3 complete attention inputs/outputs
   - Input: 8×64 INT8 embeddings
   - Expected: 8×64 INT32 attention output
   - Save as mem/tb_attn_input.mem, mem/tb_attn_expected.mem

All .mem files in hex format compatible with $readmemh
Print summary of all files generated with sizes
```

**Task 1.6 — Complete Analytical Model**

After Tasks 1.2–1.5, open docs/analytical_model.md and fill in every predicted value in the Analytical Model section of this document. Do this before writing any RTL. The predicted vs measured comparison is mandatory deliverable for Phase 4.

**Phase 1 Completion Criteria:**
- [ ] `wq.mem`, `wk.mem`, `wv.mem` generated and non-empty
- [ ] `exp_lut.mem`, `recip_lut.mem` generated and verified
- [ ] Float32 reference produces sensible attention maps
- [ ] INT8 numpy matches float32 within 5% on all 10 test vectors
- [ ] LUT softmax matches scipy softmax within 1%
- [ ] All test vector .mem files generated
- [ ] `docs/int8_accuracy_report.json` shows passing results
- [ ] `docs/analytical_model.md` exists with ALL predicted values filled in
- [ ] Bottleneck prediction (compute-bound vs memory-bound) written down before any RTL
- [ ] Scaling study table completed in docs/architecture.md

---

# PHASE 2 — Primitive RTL Modules
## Week 2 | Days 8–14

**Goal:** Build and verify every primitive RTL module in isolation. No integration yet. Every module must pass its unit testbench completely before moving forward. No exceptions. Treat each module as an experiment — extract quantitative understanding, not just a passing testbench.

---

### Phase 2 Objectives

- Build all leaf-level RTL modules
- Write self-checking testbenches using Phase 1 test vectors
- Simulate every module in Vivado XSim
- Measure cycle latency of each module
- Check synthesis for each module individually
- For each module: record actual cycle count vs analytical model prediction

---

### Phase 2 Tasks

**Task 2.1 — MAC Unit (reuse + verify)**

Claude Code prompt:
```
Reuse mac_unit.v from Project 1 exactly as written.

Create tb/unit/tb_mac_unit.v that:
- Loads mem/tb_mac_vectors.mem (20 test vectors)
- For each vector: applies inputs, waits one clock cycle,
  checks output against expected
- Reports PASS/FAIL per test, total pass/fail count
- Measures and prints cycle latency
- Uses $readmemh to load test vectors
- Ends with $finish

Run in Vivado XSim and confirm all 20 tests pass.
```

**Task 2.2 — Double Buffer**

Claude Code prompt:
```
Create rtl/compute/double_buffer.v — ping-pong buffer for tiles:

Parameters:
- DEPTH: number of elements (default 1024)
- WIDTH: bit width per element (default 8)

Functionality:
- Two internal RAMs of size DEPTH×WIDTH (ping and pong)
- While buffer A is being READ by compute engine,
  buffer B is being WRITTEN by tile loader
- On swap signal: roles swap (ping becomes pong, vice versa)
- Ports:
  - clk, rst_n
  - wr_en, wr_addr, wr_data (write port — loader side)
  - rd_en, rd_addr, rd_data (read port — compute side)
  - swap (pulse to swap ping/pong roles)
  - wr_buf_id, rd_buf_id (which buffer is which, for debug)
  - wr_ready (write buffer is empty and ready)
  - rd_valid (read buffer has valid data)

Create tb/unit/tb_double_buffer.v that:
- Fills buffer A while reading buffer B simultaneously
- Swaps and verifies data integrity
- Tests edge case: swap during simultaneous read/write
- Reports PASS/FAIL
```

**Task 2.3 — Stream FIFO**

Claude Code prompt:
```
Create rtl/streaming/stream_fifo.v — AXI-Stream compliant FIFO:

Parameters:
- DEPTH: FIFO depth (default 16)
- WIDTH: data width in bits (default 8)

AXI-Stream ports:
- s_axis_tvalid, s_axis_tready, s_axis_tdata (slave/input)
- m_axis_tvalid, m_axis_tready, m_axis_tdata (master/output)
- s_axis_tlast, m_axis_tlast (end of packet)

Additional ports:
- clk, rst_n
- fill_level (how many entries currently in FIFO)
- overflow_flag (write attempted when full)
- underflow_flag (read attempted when empty)

Requirements:
- Registered outputs (no combinational paths from in to out)
- Correct backpressure: assert s_axis_tready=0 when full
- Correct valid: assert m_axis_tvalid=0 when empty
- Must handle simultaneous read and write
- overflow_flag and underflow_flag are sticky (cleared by rst_n)

Create tb/unit/tb_stream_fifo.v that:
- Test 1: fill to capacity, verify overflow_flag behavior
- Test 2: read from empty, verify underflow_flag behavior
- Test 3: simultaneous read/write at full speed
- Test 4: backpressure — receiver stalls, sender keeps pushing
- Test 5: tlast propagation through FIFO
- All tests self-checking with PASS/FAIL
```

**Task 2.4 — Performance Counters**

Claude Code prompt:
```
Create rtl/infrastructure/perf_counters.v:

Ports:
- clk, rst_n
- start (begin counting)
- stop (stop counting, freeze values)
- clear (reset all counters)
- data_valid_in (is input data arriving this cycle?)
- compute_active (is compute engine active this cycle?)
- dma_wait (is pipeline stalled waiting for DMA?)
- tile_done (pulse each time a tile completes)

Output registers (readable via AXI-lite):
- cycle_count [31:0]
- stall_cycles [31:0] (cycles where !data_valid_in && start)
- compute_cycles [31:0]
- dma_cycles [31:0]
- tile_count [15:0]
- utilization [7:0] (compute_cycles*255/cycle_count, updated at stop)

Requirements:
- All counters are 32-bit, saturate at max (no wraparound)
- utilization computed combinatorially from other counters
- Cycle-accurate — no double-counting

Create tb/unit/tb_perf_counters.v that:
- Simulates a 100-cycle workload with known activity pattern:
  60 compute cycles, 25 stall cycles, 15 DMA cycles
- Verifies counter values match expected exactly
- Tests clear and freeze behavior
- Reports PASS/FAIL
```

**Task 2.5 — LUT Softmax Modules**

Claude Code prompt:
```
Create three RTL modules for the softmax pipeline:

1. rtl/softmax/max_finder.v — parallel tree max reduction:
   - Input: 8 signed INT16 values (in parallel)
   - Output: max value (INT16), index of max (3-bit)
   - Implemented as binary tree: 4 comparators → 2 → 1
   - Fully combinatorial (no clock needed)
   - Latency: 3 logic levels

2. rtl/softmax/softmax_lut.v — exp LUT lookup:
   - Input: 8 INT16 values (shifted by subtracting max)
   - Uses $readmemh to load mem/exp_lut.mem (256 entries)
   - Maps each value to LUT index:
     index = clamp(value + 128, 0, 255)
   - Output: 8 unsigned INT8 exp approximations
   - Registered output, 1 cycle latency per element
   - Process all 8 in parallel

3. rtl/softmax/softmax_pipeline.v — full softmax top level:
   - Instantiates max_finder, softmax_lut, reciprocal_lut
   - FSM: IDLE→FIND_MAX→SUBTRACT→EXP_LUT→SUM→NORMALIZE→DONE
   - Input: 8 INT16 scores (valid_in pulse)
   - Output: 8 INT16 normalized weights (valid_out pulse)
   - Cycle count: report in comment how many cycles per row
   - Load mem/recip_lut.mem for normalization step

Create tb/unit/tb_softmax_lut.v that:
- Loads mem/tb_softmax_input.mem (10 test rows)
- Loads mem/tb_softmax_expected.mem (expected outputs)
- Runs each row through softmax_pipeline
- Compares output against expected within tolerance of ±2 LSB
- Reports PASS/FAIL per row, total summary
- Reports cycle count per row
```

**Task 2.6 — Tiled Matmul**

Claude Code prompt:
```
Create rtl/compute/tiled_matmul.v — the core compute engine:

Parameters:
- ROWS = 8 (input rows)
- COLS = 64 (output cols)
- INNER = 64 (inner dimension)
- TILE_W = 16 (tile width)
- NUM_TILES = INNER/TILE_W = 4

Architecture:
- TILE_W MAC units instantiated in parallel (16 MACs)
- tile_controller.v FSM sequences through 4 tiles
- double_buffer.v holds current and next tile weights
- accumulator.v maintains INT32 partial sums across tiles

Operation sequence per tile:
1. Load tile weights from BRAM (16×64 INT8 = 1KB)
2. For each of 8 input rows:
   For each of 64 output cols:
     Accumulate 16 MAC results (one tile contribution)
3. Advance to next tile, accumulate into same output buffer
4. After 4 tiles: output complete 8×64 INT32 matrix

Ports:
- clk, rst_n, start, done
- input_data (8×64 INT8 flattened, loaded before start)
- weight_sel (which .mem file: 0=wq, 1=wk, 2=wv)
- output_data (8×64 INT32 flattened)
- tile_done (pulse per tile for perf counter)
- compute_active (high when MACs are running)

Create tb/unit/tb_tiled_matmul.v that:
- Loads mem/tb_matmul_input.mem as input
- Loads wq.mem as weights (weight_sel=0)
- Runs matmul, waits for done
- Compares output against mem/tb_matmul_expected.mem
- Tolerance: exact match (INT8×INT8→INT32 is exact)
- Reports cycle count, PASS/FAIL
```

**Phase 2 Completion Criteria:**
- [ ] All 6 unit testbenches pass in XSim
- [ ] tb_mac_unit: 20/20 pass
- [ ] tb_double_buffer: all edge cases pass
- [ ] tb_stream_fifo: all 5 tests pass including backpressure
- [ ] tb_perf_counters: exact cycle counts match expected
- [ ] tb_softmax_lut: 10/10 rows pass within ±2 LSB
- [ ] tb_tiled_matmul: exact INT32 match on all 5 vectors
- [ ] Each module synthesizes individually without errors
- [ ] Measured cycle count for each module recorded against analytical model prediction

---

# PHASE 3 — Integration and Full Attention Pipeline
## Week 3 | Days 15–21

**Goal:** Wire all primitives into a complete attention pipeline. Verify end-to-end correctness in simulation. Build AXI-lite control interface. Achieve timing closure in Vivado synthesis.

---

### Phase 3 Objectives

- Build QKV projection block (3 parallel tiled matmuls)
- Build score engine (QK^T computation)
- Build attend engine (attention weights × V)
- Wire into complete attention_pipeline.v
- Build AXI-lite slave for PS control
- Full integration testbench (end-to-end)
- Vivado synthesis — timing closure at 100MHz

---

### Phase 3 Tasks

**Task 3.1 — QKV Projection Block**

Claude Code prompt:
```
Create rtl/attention/qkv_projection.v:

Instantiates THREE tiled_matmul units in parallel:
- Q_matmul: weight_sel=0 (wq.mem)
- K_matmul: weight_sel=1 (wk.mem)
- V_matmul: weight_sel=2 (wv.mem)

All three receive the same input embeddings simultaneously.
All three start on the same start pulse.
done asserted when ALL THREE are complete.

Ports:
- clk, rst_n, start, done
- input_embeddings (8×64 INT8 flattened)
- q_out (8×64 INT32), k_out (8×64 INT32), v_out (8×64 INT32)
- compute_active (OR of all three matmuls)
- tile_done (any tile completion)

Create tb/integration/tb_qkv_projection.v that:
- Loads mem/tb_attn_input.mem as embeddings
- Runs all three projections
- Compares Q, K, V outputs against Python INT8 reference
- Reports cycle count, PASS/FAIL per projection
```

**Task 3.2 — Score Engine**

Claude Code prompt:
```
Create rtl/attention/score_engine.v — computes QK^T:

Input: Q (8×64 INT32), K (8×64 INT32)
Output: scores (8×8 INT32) — the raw attention scores

Operation: scores[i][j] = sum(Q[i][:] * K[j][:]) for all i,j
This is a dot product of each Q row with each K row.

Architecture:
- 64 multipliers in parallel (one per inner dimension element)
- Adder tree reduces 64 products to 1 sum per cycle
- Process all 64 pairs (8×8) sequentially
- Total: 64 cycles for full score matrix

Then instantiate rtl/infrastructure/scale_unit.v:
- Input: 8×8 INT32 scores
- Operation: arithmetic right shift by 3 (÷8 ≈ ÷√64)
- Output: 8×8 INT16 scaled scores

Ports:
- clk, rst_n, start, done
- q_in (8×64 INT32), k_in (8×64 INT32)
- scores_out (8×8 INT16 scaled)

Create tb/integration/tb_score_engine.v:
- Uses Q, K from tb_qkv_projection output
- Compares 8×8 score matrix against Python reference
- Tolerance: ±1 LSB after scaling
- Reports cycle count, PASS/FAIL
```

**Task 3.3 — Attend Engine**

Claude Code prompt:
```
Create rtl/attention/attend_engine.v — computes attention×V:

Input:
- attn_weights (8×8 INT16 — from softmax)
- v_out (8×64 INT32 — from V projection)

Output: attention_output (8×64 INT32)

Operation: output[i][j] = sum(attn_weights[i][:] * v_out[:][j])
This is matrix multiply: (8×8) × (8×64) → (8×64)

Architecture:
- Process row by row
- For each output row i (8 total):
  For each output col j (64 total):
    Accumulate 8 products: sum(attn[i][k] * V[k][j])
- 8×64 = 512 output elements
- Use 8 parallel MACs (one per k dimension)
- Total: 64 cycles for full output matrix

Ports:
- clk, rst_n, start, done
- attn_weights (8×8 INT16), v_in (8×64 INT32)
- output_data (8×64 INT32)

Create tb/integration/tb_attend_engine.v:
- Uses attention weights from softmax, V from QKV projection
- Compares final output against Python int8_attention.py output
- Tolerance: ±4 LSB (accumulated quantization error)
- Reports PASS/FAIL
```

**Task 3.4 — Full Attention Pipeline**

Claude Code prompt:
```
Create rtl/attention/attention_pipeline.v — complete attention:

Instantiates in order:
1. qkv_projection (parallel Q, K, V matmuls)
2. score_engine (QK^T + scale)
3. softmax_pipeline (per-row softmax on 8×8 scores)
4. attend_engine (attn_weights × V)
5. perf_counters (tracks all pipeline stages)

FSM:
IDLE → QKV_PROJECT → SCORE → SOFTMAX → ATTEND → DONE

Ports:
- clk, rst_n, start, done
- input_embeddings (8×64×8-bit)
- attention_output (8×64×32-bit)
- perf data: cycle_count, stall_cycles, compute_cycles,
  tile_count, utilization

Create tb/integration/tb_attention_pipeline.v:
- Loads all 3 test vectors from tb_attn_input.mem
- Runs complete attention for each
- Compares against tb_attn_expected.mem
- Reports:
  - PASS/FAIL per test vector
  - Total cycle count per inference
  - Breakdown: QKV cycles, score cycles, softmax cycles,
    attend cycles
  - Compute utilization percentage

Also add backpressure injection for Experiment 3:
- parameter STALL_EVERY_N_CYCLES = 0 (0 = no stalls)
- When non-zero, artificially deassert data_valid_in
  every N cycles to simulate input starvation
- Record perf counter readings for each stall setting
```

**Task 3.5 — AXI-Lite Slave + Top Level**

Claude Code prompt:
```
Create rtl/infrastructure/axi_lite_slave.v:

Implement full AXI4-Lite slave protocol:
- awvalid/awready (write address channel)
- wvalid/wready (write data channel)
- bvalid/bready (write response channel)
- arvalid/arready (read address channel)
- rvalid/rready (read data channel)

Register map as defined in PRD (0x000-0x5FF)
Write to INPUT_BUF fills input_embeddings buffer
Read from OUTPUT_BUF reads attention_output buffer
Control/status registers connect to attention_pipeline ports
Performance counter registers connect to perf_counters

Create rtl/top/top.v:
- Instantiates axi_lite_slave
- Instantiates attention_pipeline
- Wires all internal signals
- Single clock domain (100MHz)
- Synchronous reset (active low)

Create tb/integration/tb_top.v:
- Simulates AXI-lite transactions from a BFM
  (bus functional model)
- Write input embeddings via AXI-lite
- Pulse start via control register
- Poll status register until done
- Read output via AXI-lite
- Read all performance counters
- Verify output correctness
- Print full performance report

Create vivado/create_project.tcl:
- Target: xc7z020clg400-1
- Add all RTL sources
- Add all mem files as simulation sources
- Create block design with Zynq PS7 IP
- Connect AXI-lite master (PS) to top.v slave (PL)
- Set 100MHz clock constraint
- Run synthesis
- Generate timing and utilization reports
```

**Task 3.6 — Timing Closure**

Steps (manual in Vivado — not Claude Code):
- Run synthesis: `source vivado/run_synthesis.tcl`
- Check WNS (want > 0ns at 100MHz)
- If WNS < 0: identify critical path in timing report
- Common fixes:
  - Add pipeline register in long combinatorial path
  - Reduce LUT depth in adder trees
  - Use `(* use_dsp = "yes" *)` attribute on MAC units
- Re-run synthesis after each fix
- Record final: WNS, LUTs, DSPs, BRAMs, FFs

**Phase 3 Completion Criteria:**
- [ ] tb_qkv_projection: all projections match Python reference
- [ ] tb_score_engine: 8×8 score matrix correct within ±1 LSB
- [ ] tb_attend_engine: final output correct within ±4 LSB
- [ ] tb_attention_pipeline: all 3 vectors pass, cycle breakdown printed
- [ ] tb_top: full AXI-lite transaction simulation passes
- [ ] Vivado synthesis: WNS ≥ 0 at 100MHz
- [ ] Utilization recorded: LUTs, DSPs, BRAMs, FFs
- [ ] Measured stage cycle counts recorded against Phase 1 analytical predictions

---

# PHASE 4 — PS Integration, Benchmarking, Documentation
## Week 4 | Days 22–30

**Goal:** Run real inference on the board. Measure everything. Document everything. Make this portfolio-grade.

---

### Phase 4 Objectives

- Deploy bitstream to Zynq board
- Write Python inference driver
- Measure end-to-end latency and throughput
- Profile bottlenecks using performance counters
- Run all three controlled experiments
- Complete predicted vs measured analysis
- Generate all plots and reports
- Write complete README and interview prep guide
- Push to GitHub

---

### Phase 4 Tasks

**Task 4.1 — Bitstream Generation and Board Bring-up**

Steps:
```bash
# In Vivado
source vivado/run_implementation.tcl
# generates streaming_attention.bit

# On board (if pynq available)
from pynq import Overlay
ol = Overlay("streaming_attention.bit")

# Or via /dev/mem if no pynq
# Verify AXI-lite access first
python3 -c "
import mmap, os
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
mem = mmap.mmap(fd, 0x1000, offset=0x43C00000)
print('STATUS:', hex(int.from_bytes(mem[4:8], 'little')))
"
```

**Task 4.2 — Inference Driver**

Claude Code prompt:
```
Create python/inference/run_inference.py:

Functions:
1. setup_hardware(base_addr):
   - Opens /dev/mem or pynq overlay
   - Returns handle to AXI-lite register space

2. write_embeddings(handle, embeddings_int8):
   - Writes 8×64 INT8 matrix to INPUT_BUF (0x100-0x1FF)
   - 512 bytes total
   - Use word-aligned writes (4 bytes at a time)

3. run_inference(handle):
   - Write 0x1 to CTRL register (start=1)
   - Poll STATUS register until bit0=done
   - Timeout after 10000 polls
   - Return cycle_count from CYCLE_COUNT register

4. read_output(handle):
   - Read 8×64 INT32 matrix from OUTPUT_BUF (0x200-0x5FF)
   - 2048 bytes total
   - Return as numpy array (8, 64) int32

5. read_perf_counters(handle):
   - Read all performance counter registers
   - Return dict with all metrics

Main script:
- Generates random INT8 input (8×64)
- Runs float32 PyTorch reference (timed)
- Runs PL inference (timed end-to-end)
- Prints side-by-side output comparison (first row)
- Prints latency comparison
- Prints performance counter values
```

**Task 4.3 — Benchmarking**

Claude Code prompt:
```
Create python/inference/benchmark.py:

Run 100 inference trials:
- 50 with random inputs
- 50 with structured inputs (repeated tokens, worst case)

For each trial measure:
- Total wall-clock time (Python → PL → Python)
- PL compute time from cycle counter (cycles / 100MHz)
- PyTorch float32 time on PS CPU
- Error vs float32 reference

Report:
- Mean, std, min, max latency for PL and PyTorch
- Throughput: tokens/second (seq_len / latency)
- Mean compute utilization from perf counters
- Mean stall percentage
- Mean DMA overhead percentage
- Mean absolute error vs float32
- Percentage of trials within 5% error

Create python/inference/profile_bottleneck.py:
- Runs 10 inferences with detailed counter reading
- Computes for each:
  compute_util = compute_cycles / cycle_count * 100
  stall_pct = stall_cycles / cycle_count * 100
  dma_pct = dma_cycles / cycle_count * 100
- Identifies dominant bottleneck
- Suggests optimization (more specific than "it is slow")
- Prints analysis: "Bottleneck is X because Y, fix by Z"
```

**Task 4.4 — Controlled Experiments**

**Experiment 1 — Tile Size Sensitivity**

```
Modify tiled_matmul.v parameter TILE_W and re-synthesize:

TILE_W | Measured Latency | Measured Utilization | BRAM usage
-------|-----------------|---------------------|------------
  8   |                 |                     |
 16   |                 |                     |  ← baseline
 32   |                 |                     |

What to measure per tile size:
- Total inference cycles (from perf_counters)
- Compute utilization %
- BRAM blocks used (from Vivado utilization report)
- Whether timing closure holds (WNS)

What to explain in docs/performance_report.md:
- Why does smaller tile increase stall cycles?
- Why does larger tile increase BRAM pressure?
- Where is the knee of the curve and why?
- What tile size would you choose for embed_dim=256?
```

**Experiment 2 — Softmax LUT Precision**

```
Run python/reference/lut_softmax.py run_lut_experiment()
Record results:

LUT size | Mean Error | Max Error | BRAM entries
---------|------------|-----------|-------------
      64 |            |           |
     128 |            |           |
     256 |            |           |  ← current
     512 |            |           |
    1024 |            |           |

What to explain in docs/performance_report.md:
- At what LUT size does error stop improving significantly?
- What is the memory cost of each size?
- Why does 256 entries give a good error/cost tradeoff?
- What would break if you used 64 entries?
```

**Experiment 3 — Backpressure Sensitivity**

```
In tb/integration/tb_attention_pipeline.v, vary STALL_EVERY_N_CYCLES:

STALL_EVERY_N | Injected Stall % | Measured Util % | Latency multiplier
--------------|-----------------|-----------------|-------------------
            0 |              0% |                 | 1.0x (baseline)
           10 |             10% |                 |
            5 |             20% |                 |
            2 |             50% |                 |

What to explain in docs/performance_report.md:
- Is the relationship between injected stall and utilization linear?
- Where does the pipeline absorb stalls (FIFO buffering)?
- Where does it propagate stalls upstream (backpressure)?
- What minimum input bandwidth keeps utilization above 80%?
```

**Task 4.5 — Visualization**

Claude Code prompt:
```
Create three visualization scripts:

1. python/visualization/plot_latency.py:
   - Bar chart: PL latency vs PyTorch latency (log scale)
   - Stacked bar: cycle breakdown
     (QKV cycles, score cycles, softmax cycles, attend cycles)
   - Line chart: latency vs tile size (Experiment 1 results)
   - Save as docs/latency_analysis.png

2. python/visualization/plot_error_dist.py:
   - Histogram of element-wise errors across 100 trials
   - CDF plot of errors
   - Line chart: LUT size vs error % (Experiment 2 results)
   - Annotation: "X% of outputs within 5% of float32"
   - Save as docs/error_distribution.png

3. python/visualization/plot_attention_map.py:
   - Heatmap of 8×8 attention weight matrix (PL output)
   - Side by side: PL attention vs PyTorch attention
   - Shows visually that patterns match
   - Save as docs/attention_comparison.png
```

**Task 4.6 — Complete Documentation**

Claude Code prompt:
```
Create all documentation files:

1. README.md — complete project README:
   - Title, tagline, badges (Verilog, Python, Vivado)
   - What this project is (2 paragraphs, no jargon)
   - Why it matters (industry context — NPUs, dataflow kernels)
   - Full ASCII architecture diagram
   - Hardware modules table (name, purpose, latency, location)
   - AXI-lite register map table (full)
   - Performance results table (fill with actual numbers):
     | Metric | Value |
     | End-to-end latency | X ms |
     | Throughput | X tokens/sec |
     | Compute utilization | X% |
     | Stall percentage | X% |
     | Error vs float32 | X% mean abs |
     | LUT utilization | X / 53200 |
     | DSP utilization | X / 220 |
     | BRAM utilization | X / 140 |
     | Clock frequency | 100 MHz (WNS: +Xns) |
   - Controlled experiments summary table (tile size, LUT precision, backpressure)
   - Predicted vs measured latency table
   - How to reproduce (step by step)
   - Key design decisions section:
     - Why INT8? Why 64-dim? Why tile width 16?
     - Why LUT softmax over approximation?
     - Why AXI-lite (not DMA) and what that tradeoff costs
   - Known limitations and future work
   - Resume bullet with actual numbers

2. docs/analytical_model.md:
   - All predicted values from Phase 1
   - All measured values from Phase 3 and 4
   - Delta column with cycle-accurate explanation for each deviation
   - Final verdict: compute-bound or memory-bound, with evidence

3. docs/architecture.md:
   - Detailed architecture explanation
   - Every design decision with rationale
   - Tiling math worked out explicitly
   - Softmax LUT derivation
   - Scaling study table completed with analysis
   - Why AXI-lite (not DMA) and tradeoffs acknowledged

4. docs/register_map.md:
   - Full register map with bit-level description
   - Timing diagrams for read and write transactions
   - Example Python code for each register operation

5. docs/performance_report.md:
   - Full benchmark results
   - Bottleneck analysis output
   - All three controlled experiment tables with explanations
   - All three plots embedded
   - Predicted vs measured comparison
   - Comparison: this design vs pure PS inference

6. docs/interview_prep.md:
   - 20 questions you will be asked about this project
   - Full answers for each
   - "What would you do differently?" section
   - How to draw architecture on whiteboard in 3 minutes
   - Connections to real industry: TPU, NPU, Hexagon DSP

7. .gitignore (Vivado + Python + data files)

8. push_to_github.sh
```

**Phase 4 Completion Criteria:**
- [ ] Bitstream deploys to board without errors
- [ ] `run_inference.py` completes without errors
- [ ] `benchmark.py` runs 100 trials and reports all metrics
- [ ] `profile_bottleneck.py` identifies and explains bottleneck
- [ ] Experiment 1 complete: tile size table filled with measured values
- [ ] Experiment 1: optimal tile size identified with quantitative reasoning
- [ ] Experiment 2 complete: LUT precision curve generated
- [ ] Experiment 2: saturation point identified and explained
- [ ] Experiment 3 complete: backpressure sensitivity measured
- [ ] Experiment 3: minimum input bandwidth calculated
- [ ] Predicted vs measured latency table complete in docs/analytical_model.md
- [ ] Every deviation from prediction has a written explanation
- [ ] All 3 plots generated and saved
- [ ] README complete with actual measured numbers
- [ ] All docs written
- [ ] Pushed to GitHub with clean commit history
- [ ] Can answer all 13 interview questions without opening any file

---

## Metrics You Must Report (non-negotiable)

| Metric | How to measure | Target |
|---|---|---|
| End-to-end latency | Python timer around full inference | < 10ms |
| Throughput | seq_len / latency | > 1000 tokens/sec |
| Compute utilization | compute_cycles / cycle_count | > 60% |
| Stall percentage | stall_cycles / cycle_count | < 30% |
| DMA overhead | dma_cycles / cycle_count | < 20% |
| Error vs float32 | mean abs error across 100 trials | < 5% |
| WNS | Vivado timing report | > 0ns |
| LUT utilization | Vivado utilization report | < 80% |
| Predicted vs measured delta | docs/analytical_model.md | All deviations explained |

---

## Controlled Experiments (mandatory, not optional)

**Run all three experiments during Phase 4. Results go in docs/performance_report.md.**

### Experiment 1 — Tile Size Sensitivity

**Question:** Is TILE_W=16 actually optimal? What is the tradeoff?

```
Modify tiled_matmul.v parameter TILE_W and re-synthesize.
See Task 4.4 for full measurement procedure.

What to explain after measuring:
- Why does smaller tile increase stall cycles?
- Why does larger tile increase BRAM pressure?
- Where is the knee of the curve and why?
- What tile size would you choose for embed_dim=256?
```

### Experiment 2 — Softmax LUT Precision

**Question:** Is 256 entries enough? Where does precision saturate?

```
Python only — no RTL changes needed.
Run run_lut_experiment() in python/reference/lut_softmax.py.
See Task 4.4 for full measurement procedure.

What to explain after measuring:
- At what LUT size does error stop improving significantly?
- What is the memory cost of each size (BRAM entries)?
- Why does 256 entries give a good error/cost tradeoff?
- What would break if you used 64 entries?
```

### Experiment 3 — Backpressure Sensitivity

**Question:** How much does input starvation hurt compute utilization?

```
Use STALL_EVERY_N_CYCLES parameter in tb_attention_pipeline.v.
See Task 4.4 for full measurement procedure.

What to explain after measuring:
- Is the relationship linear? Why or why not?
- Where does the pipeline absorb stalls (FIFO buffering)?
- Where does it propagate stalls upstream (backpressure)?
- What minimum input bandwidth keeps utilization above 80%?
```

---

## Interview Defense — The 13 Hardest Questions

**Q1: "Why does tiling reduce bandwidth pressure?"**
> Without tiling, the full 64×64 weight matrix needs to be read in parallel — 4096 bytes × 3 projections = 12KB of simultaneous BRAM reads. Zynq has limited BRAM read ports. Tiling reduces this to 16×64 = 1KB per cycle, fits in distributed RAM, and enables double buffering — loading the next tile while computing the current one.

**Q2: "What is your memory bandwidth and how did you calculate it?"**
> At 100MHz with 16-wide tiles: 16 INT8 reads per cycle × 100M cycles/sec = 1.6 GB/s per weight matrix. Three projections in parallel = 4.8 GB/s. Zynq PL BRAM bandwidth is ~10 GB/s — so compute is the bottleneck, not memory. This is visible in the performance counters.

**Q3: "Why AXI-lite instead of DMA for tensor transfer?"**
> AXI-lite is the honest tradeoff acknowledgment. DMA would give burst transfers from DDR but requires scatter-gather setup, interrupt handling, and cache coherency management. For 512-byte inputs, AXI-lite single transfers cost ~512 cycles vs ~100 cycles for DMA burst. At 100MHz that's 4μs overhead — acceptable for this sequence length. Scaling to 512 tokens would require DMA. I document this as the primary scalability bottleneck.

**Q4: "How does your LUT softmax compare to true softmax?"**
> The 256-entry exp LUT with 1/256 resolution gives < 1% mean absolute error vs scipy softmax, verified across 100 random inputs and confirmed by the LUT precision experiment. The reciprocal LUT for normalization adds another < 0.5% error. Total softmax error is dominated by the quantization of attention scores to INT16, not the LUT resolution.

**Q5: "What is your critical path?"**
> The adder tree in score_engine.v — reducing 64 INT32 products to one sum. 64-to-1 reduction needs log2(64)=6 adder stages. At 100MHz (10ns clock) each stage has 1.67ns budget. With carry-lookahead this is achievable but tight. Timing report shows WNS of +Xns — confirmed by Vivado.

**Q6: "How would you scale this to 512 tokens?"**
> Three changes: replace AXI-lite tensor transfer with AXI DMA in scatter-gather mode; tile the sequence dimension (currently fixed at 8) to process 8 tokens at a time with output accumulation; add a second level of tiling for the score matrix which becomes 512×512. BRAM usage scales as O(seq_len) not O(seq_len²) with tiling. The scaling study in docs/architecture.md shows exactly where each constraint breaks.

**Q7: "What is your compute utilization and what limits it?"**
> Measured at X% via performance counters. The gap from 100% is tile boundary transitions — 4 cycles per tile boundary × 4 boundaries × 3 projections = 48 idle cycles per inference. Double buffering recovers 80% of this. The remaining stall is BRAM read latency (2 cycles) at the start of each tile.

**Q8: "Why INT8 and not FP16?"**
> On xc7z020, DSP48E1 slices support 18×25 bit integer multiply natively. FP16 requires either soft-float logic (expensive LUTs) or Xilinx floating-point IP (uses multiple DSPs per operation). INT8 maps one multiply to one DSP slice. At 220 DSPs on this device, INT8 gives 220 parallel multiplies vs ~55 for FP16. Accuracy cost is < 5% on attention output, which is within transformer robustness margins.

**Q9: "How does this relate to how real NPUs work?"**
> Real NPUs use the same three primitives: systolic array or tiled MAC for matmul, on-chip SRAM for weight staging, and streaming dataflow with backpressure. The difference is scale and scheduling — a full NPU adds multi-kernel scheduling, layer fusion, and runtime weight streaming from DRAM. This project implements the attention kernel primitive that sits inside that larger system.

**Q10: "What would you add if you had 2 more weeks?"**
> In priority order: AXI DMA with scatter-gather for tensor transfer (removes AXI-lite bandwidth bottleneck), LayerNorm in RTL before Q/K/V projection (makes it a complete transformer sub-layer), multi-head by replicating attention_pipeline N times with shared V projection, and a Linux kernel driver with IOCTL interface for clean user-space control.

**Q11: "You predicted X cycles but measured Y. What caused the delta?"**
> Walk through the analytical model. Tile boundary stalls account for Z cycles, BRAM read latency for W cycles, FSM overhead for V cycles. Total accounts for the full delta. This is documented in docs/analytical_model.md with cycle-accurate reasoning per stage.

**Q12: "What is the minimum input bandwidth required to keep utilization above 80%?"**
> From Experiment 3: injecting 20% artificial stalls reduced utilization to X%. The FIFO absorbs bursts up to depth N cycles. Below Y MB/s sustained input bandwidth, utilization drops below 80%. This means AXI-lite is sufficient for seq_len=8 but DMA burst mode is required above seq_len=Z.

**Q13: "At what sequence length does your design break and why?"**
> From the scaling study: the score matrix grows as seq_len². At seq_len=64, the 64×64 INT32 score matrix requires 16KB — within BRAM budget. At seq_len=128, it requires 64KB — exceeds available BRAM on xc7z020. The fix is tiled score computation with streaming softmax, which processes one score row at a time and never materializes the full matrix.

---

## Daily Schedule Suggestion

```
Week 1: Python infrastructure (2-3 hrs/day)
  Mon: env setup + weight extraction
  Tue: float32 reference + accuracy report
  Wed: INT8 numpy reference
  Thu: LUT softmax Python model + LUT precision experiment
  Fri: test vector generation
  Sat: complete analytical model (all predictions filled)
  Sun: scaling study + buffer day

Week 2: Primitive RTL (3-4 hrs/day)
  Mon: MAC unit tb + double buffer
  Tue: stream FIFO + backpressure testing
  Wed: performance counters
  Thu: softmax LUT modules
  Fri: tiled matmul
  Sat-Sun: fix failing testbenches, record cycle counts vs predictions

Week 3: Integration (4-5 hrs/day)
  Mon: QKV projection
  Tue: score engine + scale unit
  Wed: attend engine
  Thu: full attention pipeline
  Fri: AXI-lite slave + top level
  Sat: tb_top simulation
  Sun: Vivado synthesis + timing closure

Week 4: Board + Experiments + Docs (3-4 hrs/day)
  Mon: bitstream + board bring-up
  Tue: inference driver + benchmark
  Wed: Experiment 1 (tile size) + Experiment 2 (LUT precision)
  Thu: Experiment 3 (backpressure) + profiling
  Fri: visualization scripts + analytical model completion
  Sat: all documentation
  Sun: GitHub push + interview prep dry run
```
