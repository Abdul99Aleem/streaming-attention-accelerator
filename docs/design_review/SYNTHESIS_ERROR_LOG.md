# Synthesis Error Discovery Log
**Date:** 2026-04-03  
**Purpose:** Track synthesis errors as they're discovered and fixed

---

## Error Discovery Process

### Iteration 1: softmax_unit_v2.v

**Errors found:**
1. Array input port `scores [0:L-1]`
2. Array output port `weights [0:L-1]`
3. Block-scoped variables (lines 238-239, 294-296)

**Status:** ✅ FIXED

**Files modified:**
- `rtl/softmax/softmax_unit_v2.v` - Fixed array ports and variable scope
- `rtl/attention/streaming_attention_v3.v` - Updated to use flattened interface

---

### Iteration 2: dot_product_engine.v

**Synthesis attempt:** v3 with fixed softmax

**Result:** ❌ FAILED

**New errors found:**
```
ERROR: [Synth 8-9917] port 'a' must not be declared to be an array
ERROR: [Synth 8-9917] port 'b' must not be declared to be an array
```

**Location:** `rtl/compute/dot_product_engine.v:34-35`

**Analysis:**
- Same issue as softmax_unit_v2.v
- Array ports not supported in Verilog-2005
- Need to apply same fix: flatten to buses

**Status:** 🔧 IN PROGRESS

---

## Key Learning: Cascading Synthesis Errors

### Why We Didn't See This Earlier

**Synthesis order:**
1. Vivado reads all source files
2. Starts with dependencies (bottom-up)
3. Stops at first error in dependency chain

**What happened:**
- First synthesis: softmax_unit_v2.v failed
- Synthesis stopped before checking dot_product_engine.v
- After fixing softmax, synthesis proceeded further
- Now discovered dot_product_engine.v has same issue

### Lesson: Check ALL Modules

**Wrong approach:**
- Fix one error
- Assume rest is fine
- Surprised by next error

**Right approach:**
- Grep for array ports in ALL files
- Fix all instances proactively
- Synthesize once with all fixes

**Command to find all array ports:**
```bash
grep -n "input.*\[.*\].*\[.*\]" rtl/**/*.v
grep -n "output.*\[.*\].*\[.*\]" rtl/**/*.v
```

This would have found both issues immediately.

---

## Systematic Fix Strategy

### Step 1: Identify all modules with array ports

Run grep on entire rtl/ directory to find all instances.

### Step 2: Fix all modules

Apply flattened bus conversion to all affected modules.

### Step 3: Update all instantiations

Update parent modules that instantiate fixed modules.

### Step 4: Synthesize

Run synthesis on complete design.

---

## Next Actions

1. Read dot_product_engine.v to understand interface
2. Fix array ports → flattened buses
3. Check for other modules with same issue
4. Update any parent modules
5. Re-synthesize

---

**This is good learning:** Finding errors iteratively teaches us about synthesis dependencies and the importance of systematic checking.
