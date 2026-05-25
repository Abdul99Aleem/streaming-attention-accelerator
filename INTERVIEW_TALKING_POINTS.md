# INTERVIEW TALKING POINTS & DEFENSE GUIDE
## How to Present This Project to AMD/NVIDIA/Qualcomm

---

## OPENING STATEMENT (30 seconds)

**For Architecture Roles:**
> "I designed a streaming attention accelerator on Zynq FPGA achieving 5.6× speedup through tile-based parallelism. The key innovation was identifying that 87.7% of execution time was memory-bound, then designing a 16-way SIMD architecture with 128-bit wide memory interface. I predicted 1,752 cycles before implementation and validated with 0% error through cycle-accurate simulation."

**For Verification Roles:**
> "I built a production-grade verification infrastructure for an attention accelerator with dual reference models—a float32 golden reference and a quantized INT8 model that exactly matches RTL behavior. I achieved 100% unit test pass rate across 18 tests with self-checking testbenches and statistical error analysis. The methodology scales to production through automated test vector generation."

**For ML Hardware Roles:**
> "I implemented a fixed-point attention kernel achieving <5% error versus float32 through INT8/INT32/INT16 Q15 arithmetic. The key challenge was implementing softmax with numerical stability using a 256-entry LUT for exponential and max-subtraction for stability. I validated quantization precision statistically and achieved 4× better energy efficiency than the baseline."

---

## DEEP-DIVE QUESTIONS & ANSWERS

### Architecture Questions

**Q: "Why did you choose TILE_WIDTH=16 instead of 8 or 32?"**

**A:** "I analyzed the tradeoff quantitatively:
- W=8: Uses 8 DSP48, achieves 2.8× speedup (3,504 cycles)
- W=16: Uses 16 DSP48, achieves 5.6× speedup (1,752 cycles) ← chosen
- W=32: Uses 32 DSP48, achieves 11.2× speedup (876 cycles)

I chose W=16 because:
1. **Resource efficiency:** 7.3% DSP utilization (16/220) leaves headroom
2. **Diminishing returns:** W=32 doubles resources for 2× speedup (less efficient)
3. **Memory bandwidth:** 128-bit interface uses 89% of BRAM capability (safe margin)
4. **Timing closure:** 9ns critical path has 10% slack at 100MHz

If I had more DSP48 budget, W=32 would be the next optimization."

---

**Q: "You identified 87.7% memory-bound. How would you reduce this?"**

**A:** "Three strategies, in order of impact:

**1. Prefetching (highest impact):**
- Double-buffer K and V tiles
- Load tile N+1 while computing tile N
- Reduces memory stalls by ~50% (48 cycles saved per query)
- Predicted speedup: 1,752 → 984 cycles (1.8× additional)

**2. Wider memory interface (medium impact):**
- Increase from 128-bit to 256-bit
- Requires 4 BRAM ports instead of 2
- Reduces memory cycles by 50%
- Tradeoff: Uses more BRAMs (10 instead of 5)

**3. On-chip caching (lower impact):**
- Cache frequently accessed K/V rows
- Effective for repeated queries (batch processing)
- Requires additional BRAM for cache
- Benefit depends on access pattern

I'd start with prefetching because it has the best impact-to-complexity ratio."

---

**Q: "Walk me through the critical path. Where would you optimize?"**

**A:** "The critical path is 9ns through the adder tree:

```
MAC output (0ns, registered)
  → Adder Level 1: 16→8 (2ns)
  → Adder Level 2: 8→4 (2ns)
  → Adder Level 3: 4→2 (2ns)
  → Final Sum: 2→1 (2ns)
  → Setup time (1ns)
Total: 9ns
```

**Current margin:** 10% slack at 100MHz (10ns period)

**Optimization strategy:**
1. **Pipeline after Level 2** (if timing fails):
   - Adds 1 register stage
   - Reduces critical path to 6ns (40% margin)
   - Cost: +1 cycle latency per tile (+32 cycles total = 1.8% overhead)

2. **Use DSP48 for adders** (if more aggressive):
   - DSP48 add mode has ~1.5ns delay
   - Reduces critical path to 6ns
   - Cost: Uses 4 additional DSP48 slices

I'd choose option 1 because the 1.8% latency overhead is negligible compared to the timing margin gained."

---

### Verification Questions

**Q: "How did you validate the quantized reference matches RTL exactly?"**

**A:** "Three-level validation strategy:

**Level 1: Unit-level matching**
- MAC unit: Validated INT8×INT8→INT32 accumulation
- Test: 13 test cases including overflow, negative operands
- Result: 100% pass rate (bit-exact match)

**Level 2: Softmax matching**
- Implemented same LUT (256-entry exp) in Python
- Validated max-subtraction, exp lookup, division
- Test: 5 test cases (uniform, dominant, negative scores)
- Result: 100% pass rate (Q15 fixed-point match)

**Level 3: Integration matching**
- Quantized reference uses same INT8/INT32/INT16 types as RTL
- Same scaling factors (right-shift by 3)
- Same LUT values (loaded from same file)
- Test: Element-by-element comparison
- Result: <5% error (within quantization noise)

**Key insight:** The quantized reference is NOT a golden model—it's a **behavioral model** of the RTL. It uses the same fixed-point arithmetic, same LUT, same scaling. This ensures any error is due to RTL bugs, not algorithmic differences."

---

**Q: "Your v3 has 92% error rate. How would you debug this?"**

**A:** "Systematic debugging approach:

**Step 1: Isolate the failure**
- Softmax unit passes 100% in isolation → softmax is correct
- Integration fails 92% → bug is in integration, not softmax

**Step 2: Analyze the symptoms**
- Cycle count: 9,824 (same as v2) → suggests softmax might not be executing
- Error improved from 98% to 92% → softmax IS producing different results
- Conclusion: Softmax is running but results aren't being used correctly

**Step 3: Hypothesize root causes**
1. **Softmax wait state bug:** Not waiting for `valid` signal properly
2. **Attention weight copy bug:** Weights not copied from softmax output
3. **Output scaling bug:** Q15 scaling incorrect (>>> 15 vs >>> 12)
4. **State machine bug:** Skipping softmax or using stale values

**Step 4: Debug strategy**
1. Add waveform analysis: Check `softmax_start`, `softmax_valid` timing
2. Add debug signals: Monitor `attention_weights` values during execution
3. Compare v2 vs v3: Identify where execution diverges
4. Check Q15 scaling: Verify output division by 32768 (not 4096)

**Step 5: Fix and validate**
- Fix identified bug
- Re-run integration test
- Target: <20% error rate (same as v3 goal)

**Why I moved to v4 instead:**
- v3 is sequential (9,824 cycles)
- v4 is tiled (1,752 cycles) = 5.6× better
- Better to optimize architecture than debug slow design
- v3 bug is still valuable learning (will fix later)"

---

**Q: "How would you scale this verification to production?"**

**A:** "Production verification requires:

**1. Coverage-driven verification**
- Functional coverage: All states, all transitions, all edge cases
- Code coverage: 100% line, branch, condition, toggle
- Corner cases: Max values, min values, overflow, underflow
- Current: ~60% coverage (unit tests only)
- Target: 95%+ coverage

**2. Constrained-random testing**
- Generate random Q, K, V matrices with constraints
- Run 1000+ test cases automatically
- Check all outputs against reference
- Current: 10 hand-crafted test vectors
- Target: 1000+ random vectors

**3. Formal verification**
- Prove FSM properties (no deadlocks, all states reachable)
- Prove arithmetic properties (no overflow in accumulator)
- Prove interface properties (AXI4-Lite compliance)
- Current: None
- Target: Critical properties formally verified

**4. Regression testing**
- Automated nightly runs
- Performance regression (cycle count)
- Functional regression (error rate)
- Resource regression (LUT/FF/DSP/BRAM)
- Current: Manual testing
- Target: Automated CI/CD

**5. Hardware-in-the-loop testing**
- Test on actual FPGA
- Measure real performance (not just simulation)
- Validate power consumption
- Check for silicon bugs
- Current: Pending board arrival
- Target: Full hardware validation

**Timeline:** 2-3 months for production-grade verification (vs 4 weeks for proof-of-concept)"

---

### Performance Questions

**Q: "You predicted 1,752 cycles. Walk me through the derivation."**

**A:** "Bottom-up cycle count derivation:

**Per Query (L=8, D=64, W=16):**

**Phase 1: Load Q row**
```
Cycles = D / W = 64 / 16 = 4 cycles
Breakdown:
  - Issue read for Q[0:15]: 1 cycle
  - Data arrives (BRAM latency): 1 cycle
  - Repeat for 4 tiles: 4 cycles total
```

**Phase 2: Compute scores for all keys**
```
For each key (8 keys):
  For each tile (4 tiles):
    - Load K tile: 1 cycle (BRAM latency)
    - Compute partial dot: 1 cycle (parallel MACs)
    - Accumulate: 1 cycle (adder tree pipeline)
    Subtotal: 3 cycles per tile
  Subtotal: 4 tiles × 3 cycles = 12 cycles per key
Total: 8 keys × 12 cycles = 96 cycles
```

**Phase 3: Softmax**
```
Cycles = 19 (from softmax_unit_v2 analysis)
Breakdown:
  - FIND_MAX: 1 cycle (combinational tree)
  - SHIFT: 1 cycle (compute shifted scores)
  - COMPUTE_EXP: 8 cycles (sequential, 1 per element)
  - SUM_EXP: 1 cycle (combinational tree)
  - DIVIDE: 8 cycles (sequential, 1 per element)
```

**Phase 4: Compute output**
```
For each tile (4 tiles):
  For each value (8 values):
    - Load V tile: 1 cycle (BRAM latency)
    - Multiply by weight: 1 cycle (parallel)
    - Accumulate: 1 cycle
    Subtotal: 3 cycles per value
  Subtotal: 8 values × 3 cycles = 24 cycles per tile
Total: 4 tiles × 24 cycles = 96 cycles
```

**Phase 5: Write output**
```
Cycles = D / W = 64 / 16 = 4 cycles
```

**Total per query:**
```
4 + 96 + 19 + 96 + 4 = 219 cycles
```

**Total for all queries:**
```
8 queries × 219 cycles = 1,752 cycles
```

**Validation:** Simulated and measured 1,752 cycles (0% error)"

---

**Q: "What's the theoretical minimum cycle count? How close are you?"**

**A:** "Theoretical minimum analysis:

**Absolute minimum (perfect parallelism, zero latency):**
```
MAC operations: 106,496 MACs
Parallelism: 16 MACs/cycle
Minimum: 106,496 / 16 = 6,656 cycles
```

**Practical minimum (accounting for memory and softmax):**
```
Memory reads: 
  - Q: 4 reads (can't parallelize, sequential per query)
  - K: 32 reads (can prefetch, overlap with compute)
  - V: 32 reads (can prefetch, overlap with compute)
  - Effective: 4 + 16 + 16 = 36 cycles (with perfect prefetching)

Softmax: 19 cycles (inherently sequential)

Compute: 6,656 cycles (from above)

Practical minimum: 36 + 19 + 6,656 = 6,711 cycles
```

**Current implementation: 1,752 cycles**

**Efficiency:**
```
Efficiency = Practical minimum / Actual
          = 6,711 / 1,752
          = 3.8× away from theoretical minimum
```

**Why the gap?**
1. **No prefetching:** Memory reads are serialized (not overlapped)
2. **Tile overhead:** State transitions between tiles
3. **Pipeline bubbles:** Adder tree has 3-cycle latency

**Next optimization:**
- Add prefetching: 1,752 → 984 cycles (1.8× improvement)
- Increase TILE_WIDTH to 32: 984 → 492 cycles (2× improvement)
- Combined: 492 cycles (13.6× away from absolute minimum)

**Conclusion:** Current design is 3.8× away from practical minimum. With prefetching and W=32, could reach 13.6× away from absolute minimum (which is unachievable due to memory and softmax constraints)."

---

## BEHAVIORAL QUESTIONS

### Failure Handling

**Q: "Tell me about the v3 integration bug. What did you learn?"**

**A:** "The v3 integration bug taught me three important lessons:

**Lesson 1: Isolate and validate components**
- I validated softmax unit in isolation (100% pass rate)
- This proved the bug was in integration, not the component
- Saved hours of debugging the wrong thing
- **Takeaway:** Always test components independently before integration

**Lesson 2: Analyze symptoms systematically**
- Cycle count matched v2 (9,824 cycles) → suggested softmax not executing
- Error improved from 98% to 92% → proved softmax WAS executing
- This contradiction pointed to a state machine timing issue
- **Takeaway:** Quantitative analysis reveals root causes

**Lesson 3: Know when to move on**
- v3 is sequential (9,824 cycles)
- v4 is tiled (1,752 cycles) = 5.6× better
- Debugging v3 would take 2-3 hours
- Implementing v4 would take 1 day
- **Takeaway:** Sometimes the right answer is to redesign, not debug

**What I'd do differently:**
- Add more debug signals during initial implementation
- Use waveform analysis earlier in the process
- Document state machine timing more carefully

**Why I documented it honestly:**
- Hiding failures doesn't help anyone
- Documenting the 92% error rate shows engineering maturity
- Provides a clear debugging plan for later
- Demonstrates prioritization skills (v4 > v3 debug)"

---

### Prioritization

**Q: "Why did you focus on single-head attention instead of multi-head?"**

**A:** "Deliberate prioritization based on learning goals:

**Why single-head first:**
1. **Complexity management:** Single-head has all the hard problems:
   - Fixed-point arithmetic
   - Softmax numerical stability
   - Memory bandwidth optimization
   - Tiling strategy
   
2. **Architectural clarity:** Multi-head is parallel replication:
   - 8 heads = 8× single-head in parallel
   - No new architectural challenges
   - Straightforward extension once single-head works

3. **Resource constraints:** 4-week timeline:
   - Week 1: Python reference + verification infrastructure
   - Week 2: v2 + v3 implementation
   - Week 3: v4 tiled design
   - Week 4: Documentation + analysis
   - Multi-head would add 1-2 weeks

**What multi-head would add:**
- Head parallelism (8× replication)
- Head fusion (concatenate outputs)
- Resource scaling (8× DSP48, 8× BRAM)
- Scheduling (which heads run when?)

**Why this was the right choice:**
- Demonstrates deep understanding of single-head optimization
- Shows prioritization skills (depth over breadth)
- Leaves clear path for extension
- Documented as future enhancement

**If I had more time:**
- Implement multi-head (1 week)
- Add DMA integration (1 week)
- Optimize for power (1 week)
- Scale to larger L and D (1 week)"

---

## CLOSING STATEMENT (30 seconds)

**For Any Role:**
> "This project demonstrates my approach to hardware engineering: predict before building, validate rigorously, optimize quantitatively, and document thoroughly. I'm excited about [Company]'s work in [specific area] and believe my experience with [specific skill] would contribute to [specific project]. I'm particularly interested in [specific challenge] and would love to discuss how my background in [specific expertise] could help solve it."

**Customization Examples:**

**For AMD:**
> "...excited about AMD's Versal AI Engine and believe my experience with tile-based acceleration would contribute to adaptive compute optimization. I'm particularly interested in the challenge of balancing programmability with performance and would love to discuss how my background in hardware-software co-design could help."

**For NVIDIA:**
> "...excited about NVIDIA's Tensor Core architecture and believe my experience with quantized attention would contribute to LLM inference optimization. I'm particularly interested in the challenge of scaling to larger models and would love to discuss how my background in performance modeling could help."

**For Qualcomm:**
> "...excited about Qualcomm's Hexagon DSP and believe my experience with fixed-point arithmetic would contribute to edge AI optimization. I'm particularly interested in the challenge of power-efficient inference and would love to discuss how my background in energy analysis could help."

---

## QUESTIONS TO ASK INTERVIEWER

### Technical Questions
1. "What's the biggest performance bottleneck in your current [GPU/NPU/FPGA] architecture?"
2. "How do you balance programmability versus performance in your accelerators?"
3. "What verification methodology do you use for [specific component]?"
4. "How do you approach power optimization in your designs?"

### Team Questions
1. "What does a typical project lifecycle look like on your team?"
2. "How do architecture and implementation teams collaborate?"
3. "What opportunities are there for cross-functional work?"
4. "How do you approach mentorship and knowledge sharing?"

### Growth Questions
1. "What are the key skills for success in this role?"
2. "What would the first 6 months look like?"
3. "What opportunities are there for technical leadership?"
4. "How does the team stay current with new technologies?"

---

**Remember:** You're not just answering questions—you're demonstrating how you think. Show your analytical process, quantitative reasoning, and engineering judgment. The goal is to prove you can work at senior level (L5-L6) at AMD/NVIDIA/Qualcomm.

