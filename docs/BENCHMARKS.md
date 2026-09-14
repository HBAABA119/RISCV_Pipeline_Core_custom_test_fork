# Estimated Performance Benchmarks

> **These are ESTIMATED numbers** produced by `tools/perf_model.js` from the
> architecture configuration and node assumptions. They are model outputs for
> proxy workloads — not measured silicon or emulator results.

## Legacy node (180 nm-class) — **RVX-1 Compact**

| Workload | Est. IPC | Clock | Perf (IPC×GHz) | vs. big-core ref | Est. power | Perf/W |
|---|---|---|---|---|---|---|
| Integer core (Dhrystone-style proxy) | 0.48 | 200 MHz | 0.1 | 0.4% | 0.22 W | 0.4 |
| Math / MAC kernel | 0.75 | 200 MHz | 0.15 | 0.7% | 0.22 W | 0.7 |
| Branch-heavy search/sort proxy | 0.32 | 200 MHz | 0.06 | 0.3% | 0.22 W | 0.3 |
| Streaming load/store | 0.35 | 200 MHz | 0.07 | 0.3% | 0.22 W | 0.3 |
| Quantized AI inference (NPU offload) | 1.76 | 200 MHz | 0.35 | 1.6% | 0.22 W | 1.6 |
| Graphics/blend kernel (GPU helper) | 1.03 | 200 MHz | 0.21 | 0.9% | 0.22 W | 1 |

> Old node: low clock, generous area budget, no aggressive scaling.

## Mainstream node (28 nm-class) — **RVX-2 Balanced**

| Workload | Est. IPC | Clock | Perf (IPC×GHz) | vs. big-core ref | Est. power | Perf/W |
|---|---|---|---|---|---|---|
| Integer core (Dhrystone-style proxy) | 1.16 | 800 MHz | 0.93 | 4.1% | 0.34 W | 2.7 |
| Math / MAC kernel | 2.33 | 800 MHz | 1.86 | 8.3% | 0.34 W | 5.5 |
| Branch-heavy search/sort proxy | 1.05 | 800 MHz | 0.84 | 3.7% | 0.34 W | 2.5 |
| Streaming load/store | 1.3 | 800 MHz | 1.04 | 4.6% | 0.34 W | 3.1 |
| Quantized AI inference (NPU offload) | 5.77 | 800 MHz | 4.61 | 20.5% | 0.34 W | 13.6 |
| Graphics/blend kernel (GPU helper) | 3.47 | 800 MHz | 2.78 | 12.3% | 0.34 W | 8.2 |

> Mainstream node: balanced clock/power, FPGA-to-ASIC sweet spot.

## Modern node (5 nm-class) — **RVX-4 Performance**

| Workload | Est. IPC | Clock | Perf (IPC×GHz) | vs. big-core ref | Est. power | Perf/W |
|---|---|---|---|---|---|---|
| Integer core (Dhrystone-style proxy) | 2.3 | 2800 MHz | 6.45 | 28.7% | 0.43 W | 15 |
| Math / MAC kernel | 4.08 | 2800 MHz | 11.42 | 50.8% | 0.43 W | 26.7 |
| Branch-heavy search/sort proxy | 2.24 | 2800 MHz | 6.28 | 27.9% | 0.43 W | 14.7 |
| Streaming load/store | 2.84 | 2800 MHz | 7.94 | 35.3% | 0.43 W | 18.5 |
| Quantized AI inference (NPU offload) | 7.08 | 2800 MHz | 19.83 | 88.1% | 0.43 W | 46.3 |
| Graphics/blend kernel (GPU helper) | 5.14 | 2800 MHz | 14.4 | 64% | 0.43 W | 33.6 |

> Modern node: high clock and density; enables wide-issue configs.

## Reference context

Relative numbers are against an estimated mainstream big-core configuration
(5 IPC @ 4.5 GHz, with 4× accelerator
offload factor in its favor for accelerated workloads). The compact and balanced
configs are **not** expected to beat a Core Ultra 7-class machine; the modern-node
performance config closes the gap substantially on accelerated workloads while
targeting a fraction of the power/area. That trade is the point of this project.
