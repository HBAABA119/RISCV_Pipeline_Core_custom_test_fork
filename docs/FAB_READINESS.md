# Fab Readiness — RVX Core Family

Status of the RTL and infrastructure relative to what a foundry / ASIC flow
would require. This document is honest about what is done and what remains —
that honesty is itself a fab-readiness requirement.

## What is in place

### RTL / functional
- Full 5-stage in-order pipeline with explicit stage registers, forwarding
  (MEM→EX, WB→EX), load-use stalls, and flush-on-mispredict.
- Branch predictor with **parameterized modes**: bimodal (legacy), gshare with
  folded history (mainstream), tage-lite with 2× history + larger tables
  (modern), plus a Return Address Stack.
- Configurable I/D caches with hit/miss counters.
- Separate MUL/DIV execution path.
- Functional **GPU helper unit** (blend / tone-map / 4-lane dot / small matmul,
  2-cycle pipelined) and **NPU MAC array** (4-lane signed INT8 MAC with 32-bit
  accumulator), dispatched through a command queue with a verified
  result/completion path.
- **Dual-issue logic** (`Issue_Unit.v`): in-order 2-slot dispatch with
  RAW/WAW dependency gating — real RTL behind the 2-issue profile, not just a
  model knob.
- Accelerator dispatch verified in simulation: tensor-MAC accumulation round
  trip (14 → 114), dot product (20), read-status, and per-unit perf counters.

### Verification
- Icarus Verilog simulation flow with a self-checking testbench
  (`pipeline_tb.v`): accelerator command push, result capture, perf counters.
- Composable include-guard structure so the design elaborates as one unit.

### Tooling
- `tools/perf_model.js` — node-aware performance estimates.
- `tools/generate_diagrams.js` — diagrams generated from architecture source.

## What remains before tapeout (real gaps, tracked honestly)

1. **Lint / CDC / RDC signoff** — run Spyglass or equivalent; the current
   single-clock design has no CDC but formal signoff is still required.
2. **Synthesis + STA** — DC/Genus + PrimeTime with a real PDK corner set
   (SS/TT/FF, mmmc). Clock constraints and SDC files are not yet written.
3. **DFT insertion** — scan chains, MBIST for the cache/memory arrays.
4. **Formal equivalence** — after any netlist ECO.
5. **Gate-level simulation (GLS)** with SDF back-annotation.
6. **Physical implementation** — floorplan for the memory macros (cache SRAMs
   must move to compiler-generated macros, not Verilog arrays), place/route,
   IR drop, EM analysis.
7. **Formal verification of the issue logic** — the dual-issue dependency
   checks should be proven with JasperGold-style sequential assertions.
8. **Corner-lot silicon validation plan** — the perf model produces estimates;
   silicon brings real numbers.

## Simulator / flow entry points

```sh
# Functional simulation (Icarus Verilog)
iverilog -g2012 -I src -o build/core.vvp src/Pipeline_Top.v src/pipeline_tb.v
vvp build/core.vvp

# Regenerate docs
node tools/generate_diagrams.js
node tools/perf_model.js
```
