# Architecture Direction — RISCV_Pipeline_Core Rewrite

This doc captures the target machine we are building toward and the order we will implement it.
It is the source of truth for the RTL rewrite, the performance model, and the documentation diagrams.

## Target identity

We are building a **parameterized RISC-V core family** that is serious enough to be a genuine
open-source CPU project, not a one-off class pipeline. The story is:

- A modern, aggressive in-order core as the scalar heart.
- Real memory hierarchy and branch prediction instead of a bare pipeline.
- Richer execution units, including multiply/divide and FP/vector-ish math where it helps.
- On-chip accelerators that justify a "graphics + AI/math helper" identity.
- One RTL source tree that can be configured for old, mainstream, and modern process nodes with
  adjusted estimated performance and simulated benchmark artifacts.
- Generated documentation and diagrams that reflect the actual architecture.

## Core microarchitecture

The scalar core should be a clean, deeper, more capable in-order pipeline.

### Pipeline
- Keep a classic staged structure, but make the pipeline registers explicit, consistent, and
  easy to retime/parameterize.
- Support configurable pipeline depth and issue width at the top level for different performance
  points.

### Issue and execution
- Move beyond single-issue where it makes sense; target a configurable issue policy that can
  dispatch more than one operation when operands are ready.
- Separate execution resources where it matters:
  - Integer ALU pipe(s)
  - Multiply unit(s) with sensible latency/throughput
  - Divide unit as a distinct multi-cycle block
  - Load/store unit with its own buffering behavior
  - Branch handling path with predictor integration

### Forwarding and stalls
- Improve bypass coverage beyond the current minimal scheme.
- Make load-use, ALU-use, and branch latency behavior cleaner and more predictable.
- Keep control and data hazards explicit so the model can estimate them.

### Branch prediction
- Add a real predictor path instead of "no prediction" as the baseline.
- Start with practical prediction structures:
  - Simple 2-bit predictor state
  - Local/global history option
  - Small branch target buffer / target cache
  - Return-address stack for call/return behavior
- Track prediction confidence and mispredict penalty so the performance model can reflect it.

### Memory hierarchy
- Upgrade from flat instruction/data memories to a configurable cache hierarchy.
- Provide:
  - I-cache and D-cache with configurable size, line size, and associativity
  - Write-back or write-through options
  - Write buffer for store coalescing/latency hiding
  - Prefetch behavior for sequential and strided patterns
- Keep miss behavior explicit so the estimator can model latency impact.

### Floating point and vector/math support
- Add a floating-point unit or FP-lite path suitable for the target workload story.
- Add packed/vector-ish math support where it improves throughput for media/Graphics/ML-lite
  styles of code.
- Make the math units useful for both general compute and accelerator feeding.

## Accelerators

The project should include on-chip accelerators that make the core more than a CPU.

### Graphics/math helper
- A transform and matrix math block.
- A filter/blend/tone-map style math block for pixel and media work.
- A command/descriptor interface so the core can dispatch batched work.
- A completion path, either via shared memory polling or an interrupt-like notification model.

### NPU-style matrix/dot-product unit
- A MAC/dot-product block suitable for quantized and/or floating-point accumulation.
- Support small matrix and vector operations.
- Use a shared-memory or queue-based dispatch model so the core can offload without stalling
  forever.

### CPU/accelerator integration
- A clean interface between the core and the accelerators.
- Shared memory regions or MMIO-style control registers.
- Commands, status, and completion modeled explicitly so the whole system behaves like one machine
  instead of a CPU plus unrelated datapaths.

## Multi-node strategy

The same RTL family should be tunable to different process contexts.

### Configuration knobs
- Pipeline depth
- Issue width and structure
- Cache geometry and policy
- Multiplier size and pipelining
- Bypass complexity
- Presence/absence of FP, vector-ish math, and accelerators
- Clock gating and power-aware structure options

### Performance estimation
- A separate estimation/modeling layer that takes simulated or functional behavior and applies
  node-specific assumptions.
- Model the major contributors:
  - Clock frequency assumptions per node class
  - IPC behavior from the pipeline structure and prediction behavior
  - Cache hit/miss behavior
  - Accelerator throughput in relevant workloads
- Produce clearly labeled estimated benchmark tables rather than pretending real game frames exist.

### Benchmark proxy workloads
- Math-heavy loops: MAC, dot product, small matrix.
- Branch-heavy code: search, recursion, state-heavy loops.
- Streaming load/store patterns.
- Pointer-chasing and latency-sensitive traversal.
- Mixed scalar plus accelerator offload to show offload benefit.

## Documentation and diagrams

The README and project docs should be generated from the architecture, not from a stale screenshot.

### Generated artifacts
- Top-level system block diagram showing core, memory hierarchy, accelerators, and interfaces.
- Pipeline diagram with stage registers, bypass paths, prediction, and cache interaction.
- Accelerator integration diagram showing command/status/completion flow.
- Node-profile and feature matrix diagram.
- Benchmark comparison charts generated from the estimation model.

### Sources of truth
- Diagrams and tables should be generated from text/spec sources or from model output so they stay
  aligned with the RTL as it evolves.

## Rollout order

1. Write this architecture direction and lock the spec.
2. Rewrite the top-level architecture and stage/control modules for the new core.
3. Add the memory hierarchy and branch prediction path.
4. Add the richer execution units.
5. Add the accelerators and their CPU interface.
6. Add configuration knobs for node profiles and feature sets.
7. Add the performance estimation model and benchmark proxy flow.
8. Extend the testbench and program flow so behavior can feed the model.
9. Regenerate README and diagrams from the resulting system.
