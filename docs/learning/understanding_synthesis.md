# Understanding FPGA Synthesis - A Learning Guide
**Date:** 2026-04-03  
**Purpose:** Explain what synthesis does, what it reveals, and how to interpret results

---

## What is Synthesis?

**Synthesis** is the process of converting RTL (Register Transfer Level) code into a gate-level netlist that can be implemented on an FPGA.

### The FPGA Design Flow

```
RTL Code (Verilog)
    ↓
[Synthesis] ← We are here
    ↓
Gate-level Netlist
    ↓
[Place & Route]
    ↓
Bitstream
    ↓
[Program FPGA]
    ↓
Hardware
```

### What Synthesis Does

1. **Parses RTL:** Reads Verilog code and builds internal representation
2. **Elaborates:** Resolves parameters, generates instances, expands loops
3. **Optimizes:** Simplifies logic, removes dead code, merges registers
4. **Maps to primitives:** Converts to FPGA building blocks (LUTs, FFs, DSPs, BRAMs)
5. **Estimates timing:** Predicts critical paths (before actual routing)

---

## FPGA Building Blocks (Zynq-7020)

### 1. LUTs (Look-Up Tables)

**What they are:** Small memories that implement combinational logic

**Zynq-7020 has:** 53,200 LUTs (6-input LUTs)

**What they implement:**
- Any 6-input boolean function
- Small ROMs
- Distributed RAM
- Shift registers

**Example:**
```verilog
wire result = (a & b) | (c & d);  // Uses 1 LUT
```

**Cost:** 1 LUT per 6-input function

### 2. Flip-Flops (FFs)

**What they are:** Edge-triggered registers

**Zynq-7020 has:** 106,400 FFs

**What they implement:**
- All `reg` variables in clocked `always` blocks
- Pipeline stages
- State machines

**Example:**
```verilog
always @(posedge clk) begin
    data_reg <= data_in;  // Uses 1 FF per bit
end
```

**Cost:** 1 FF per registered bit

### 3. DSP48E1 Slices

**What they are:** Dedicated multiply-accumulate units

**Zynq-7020 has:** 220 DSP slices

**What they implement:**
- Multiplications (up to 25×18 bits)
- Multiply-accumulate (MAC)
- Pre-adders
- Pattern detection

**Example:**
```verilog
always @(posedge clk) begin
    acc <= acc + (a * b);  // Uses 1 DSP slice
end
```

**Cost:** 1 DSP per MAC operation (if inferred correctly)

**Critical for our design:** We have many MAC operations for dot products

### 4. Block RAM (BRAM)

**What they are:** Dedicated memory blocks

**Zynq-7020 has:** 140 BRAM blocks (36 Kb each) = 4.9 Mb total

**What they implement:**
- Large memories
- FIFOs
- Lookup tables (like our exp_lut)

**Example:**
```verilog
reg [15:0] memory [0:1023];  // May use BRAM if large enough
```

**Cost:** Depends on size and configuration

---

## What Synthesis Reports Tell Us

### 1. Resource Utilization Report

**File:** `utilization.rpt`

**What it shows:**
```
+-------------------------+------+-------+------------+-----------+-------+
| Site Type               | Used | Fixed | Available  | Util%     |
+-------------------------+------+-------+------------+-----------+-------+
| Slice LUTs              | 5234 | 0     | 53200      | 9.84      |
| Slice Registers         | 3421 | 0     | 106400     | 3.22      |
| DSP48E1                 | 64   | 0     | 220        | 29.09     |
| Block RAM Tile          | 2    | 0     | 140        | 1.43      |
+-------------------------+------+-------+------------+-----------+-------+
```

**How to interpret:**

- **LUTs:** Combinational logic complexity
  - <50%: Good, plenty of room
  - 50-80%: Moderate, watch for congestion
  - >80%: High, may have routing issues

- **Registers (FFs):** Sequential logic / pipeline depth
  - Usually not a bottleneck (2× more FFs than LUTs)

- **DSPs:** Arithmetic operations
  - **Critical for us:** Each MAC should use 1 DSP
  - If DSP usage is low, multipliers may be in fabric (slow!)
  - If DSP usage is high, we're using hardware efficiently

- **BRAM:** Memory usage
  - Our exp_lut should use 1 BRAM
  - If using distributed RAM instead, that's wasteful

### 2. Timing Report

**File:** `timing.rpt`

**What it shows:**
```
Timing Summary:
  WNS (Worst Negative Slack): 2.345 ns
  TNS (Total Negative Slack):  0.000 ns
  WHS (Worst Hold Slack):      0.123 ns
  THS (Total Hold Slack):      0.000 ns
```

**Key metrics:**

**WNS (Worst Negative Slack):**
- Slack = Required Time - Arrival Time
- Positive slack: Timing met ✅
- Negative slack: Timing violated ❌
- Example: WNS = 2.345 ns means we have 2.345 ns margin

**Critical Path:**
- Longest delay path in the design
- Determines maximum clock frequency
- Format: `Start → Logic → Routing → End`

**Example critical path:**
```
Path 1: (VIOLATED)
  Source: state_reg[2]/C
  Destination: dot_acc_reg[31]/D
  Slack: -0.234 ns
  
  Logic Levels: 8
  
  Location    Delay type    Delay(ns)  Logical Resource
  -------------------------------------------------------
  SLICE_X12Y34  FDRE (Prop)    0.456    state_reg[2]/C → Q
  SLICE_X12Y34  LUT6 (Prop)    0.124    FSM_logic
  SLICE_X15Y36  LUT6 (Prop)    0.124    multiply_logic
  ...
  SLICE_X20Y40  FDRE (Setup)   0.091    dot_acc_reg[31]/D
```

**How to interpret:**

- **Positive WNS:** Design meets timing at target frequency
- **Negative WNS:** Design too slow, need to:
  - Lower clock frequency
  - Add pipeline stages
  - Optimize critical path

**Target for our design:**
- Clock period: 10 ns (100 MHz)
- Want WNS > 0 ns (ideally > 1 ns for margin)

### 3. Power Report

**File:** `power.rpt`

**What it shows:**
```
Total On-Chip Power (W): 1.234
  Dynamic (W):           0.987
  Static (W):            0.247
  
By Resource:
  DSPs:    0.456 W
  BRAMs:   0.123 W
  Logic:   0.234 W
  Signals: 0.174 W
```

**How to interpret:**

- **Dynamic power:** Power consumed during operation (switching)
- **Static power:** Leakage power (always present)
- **Total power:** Must be < device limit (~2W for Zynq PL)

---

## What We're Testing with v3 Synthesis

### Test 1: Do the fixes work?

**Question:** Does the design synthesize without errors?

**What we fixed:**
1. Array ports → Flattened buses
2. Block-scoped variables → Module-scoped variables

**Success criteria:**
- Synthesis completes without errors
- No warnings about non-synthesizable constructs

**If it fails:**
- Check synthesis log for errors
- Identify remaining issues
- Fix and re-synthesize

### Test 2: Resource utilization

**Question:** How many resources does v3 actually use?

**Predictions (from docs/analysis/streaming_attention.md):**

| Resource | Predicted | Available | Util% |
|----------|-----------|-----------|-------|
| DSP48E1 | 64 | 220 | 29% |
| LUTs | ~8,000 | 53,200 | 15% |
| FFs | ~5,000 | 106,400 | 5% |
| BRAM | 1-2 | 140 | 1% |

**What we'll learn:**
- Are predictions accurate?
- Is design efficient?
- Is there room for v4 (more parallelism)?

### Test 3: Timing analysis

**Question:** Does v3 meet 100 MHz timing?

**Predicted critical path:** ~6.5 ns (softmax division)

**Expected WNS:** 10 ns - 6.5 ns = 3.5 ns (good margin)

**What we'll learn:**
- Actual critical path location
- Actual timing margin
- Whether 100 MHz is achievable

### Test 4: DSP inference

**Question:** Are multiplications mapped to DSP slices?

**Critical check:**
- v3 has 64 MAC operations in dot_product_engine
- Should use 64 DSP slices
- If using fewer, multipliers are in fabric (bad!)
- If using more, inefficient mapping

**How to verify:**
- Check DSP count in utilization report
- Should be exactly 64 for v3

---

## Comparing Predictions vs. Reality

### Why predictions might be wrong:

1. **Optimization:** Synthesis may optimize away logic we thought was needed
2. **Inference:** Synthesis may not infer DSPs/BRAMs as expected
3. **Overhead:** Control logic, FSMs add resources we didn't count
4. **Packing:** Multiple functions may pack into single LUT

### Learning from discrepancies:

**If actual > predicted:**
- We underestimated complexity
- Synthesis added overhead
- Inefficient coding style

**If actual < predicted:**
- Synthesis optimized better than expected
- We overestimated resource needs
- Good news: more room for optimization

---

## What Comes After Synthesis

### Post-Synthesis Simulation

**Purpose:** Verify functionality with real gate delays

**Why it matters:**
- Behavioral simulation uses ideal timing
- Post-synthesis has real gate delays
- May reveal timing-dependent bugs

### Place & Route

**Purpose:** Physically place logic on FPGA and route connections

**What it does:**
- Assigns each LUT/FF to a physical location
- Routes wires between components
- Generates final timing numbers

**Why synthesis timing is approximate:**
- Synthesis estimates routing delays
- Place & route knows actual routing delays
- Final timing may be worse than synthesis timing

### Post-Implementation Simulation

**Purpose:** Verify with actual routing delays

**Most accurate simulation before hardware**

### Hardware Testing

**The ultimate test:** Does it work on real FPGA?

---

## How to Read Synthesis Results

### Step 1: Check for errors

```bash
grep -i "error" synth_v3.log
```

**If errors found:** Fix and re-synthesize  
**If no errors:** Proceed to analysis

### Step 2: Check utilization

```bash
cat synth_v3_output/utilization.rpt
```

**Look for:**
- DSP count (should be 64 for v3)
- LUT count (should be <50% of available)
- BRAM count (should be 1-2)

### Step 3: Check timing

```bash
cat synth_v3_output/timing.rpt
```

**Look for:**
- WNS (should be positive)
- Critical path (where is the slowest path?)
- Logic levels (how many LUTs in series?)

### Step 4: Compare with predictions

**Create comparison table:**

| Metric | Predicted | Actual | Difference | Analysis |
|--------|-----------|--------|------------|----------|
| DSPs | 64 | ? | ? | ? |
| LUTs | 8,000 | ? | ? | ? |
| FFs | 5,000 | ? | ? | ? |
| WNS | 3.5 ns | ? | ? | ? |

### Step 5: Document findings

**Write analysis document:**
- What worked as expected?
- What surprised us?
- Why are there differences?
- What did we learn?

---

## Common Synthesis Issues

### Issue 1: Multipliers in Fabric

**Symptom:** Low DSP usage, high LUT usage

**Cause:** Synthesis didn't infer DSP slices

**Fix:**
- Use proper coding style for MAC
- Add synthesis attributes
- Check operand sizes (DSP has limits)

**Example fix:**
```verilog
(* use_dsp = "yes" *)
always @(posedge clk) begin
    acc <= acc + (a * b);
end
```

### Issue 2: Distributed RAM instead of BRAM

**Symptom:** High LUT usage, low BRAM usage

**Cause:** Memory too small or wrong style

**Fix:**
- Increase memory size (>512 bits)
- Use proper RAM template
- Add synthesis attributes

### Issue 3: Timing Violations

**Symptom:** Negative WNS

**Causes:**
- Logic too complex (too many LUT levels)
- Long routing paths
- High fanout signals

**Fixes:**
- Add pipeline stages
- Reduce logic depth
- Register high-fanout signals

### Issue 4: High Resource Usage

**Symptom:** >80% LUT utilization

**Causes:**
- Inefficient coding
- Unnecessary logic
- Poor resource sharing

**Fixes:**
- Review RTL for optimization
- Enable resource sharing
- Simplify control logic

---

## Next Steps After Synthesis

1. **Analyze results** (create comparison document)
2. **Verify functionality** (post-synthesis simulation)
3. **Optimize if needed** (based on findings)
4. **Proceed to v4** (if v3 meets requirements)

---

## Summary

**Synthesis reveals:**
- Whether RTL is synthesizable
- Actual resource usage
- Timing feasibility
- Design efficiency

**Key learning:**
- Predictions are educated guesses
- Reality teaches us about synthesis behavior
- Discrepancies reveal optimization opportunities
- Iteration improves design quality

**For this project:**
- v3 synthesis validates our fixes
- Results inform v4 design decisions
- Comparison with predictions teaches VLSI design
- Documentation captures learning for future reference

---

**Waiting for synthesis to complete...**
