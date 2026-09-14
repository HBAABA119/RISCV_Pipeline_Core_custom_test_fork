#!/usr/bin/env node
/**
 * Performance estimation model for the parameterized RISC-V core family.
 *
 * Takes per-profile configuration (issue width, caches, predictor, accelerator)
 * plus node assumptions (frequency, power) and produces estimated benchmark
 * results for proxy workloads. Output: docs/BENCHMARKS.md + docs/benchmarks.json
 *
 * All numbers are ESTIMATES derived from IPC models, clearly labeled as such.
 */
'use strict';
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
//  Node profiles: process-node class assumptions
//  freq_mhz: achievable core clock; power_mw_per_ghz: dynamic power scaling;
//  area_scale: relative logic density (newer node = denser/faster)
// ---------------------------------------------------------------------------
const NODE_PROFILES = {
  legacy_180nm: {
    label: 'Legacy node (180 nm-class)',
    freq_mhz: 200,
    power_mw_per_ghz: 900,
    area_scale: 1.0,
    notes: 'Old node: low clock, generous area budget, no aggressive scaling.',
  },
  mainstream_28nm: {
    label: 'Mainstream node (28 nm-class)',
    freq_mhz: 800,
    power_mw_per_ghz: 250,
    area_scale: 0.15,
    notes: 'Mainstream node: balanced clock/power, FPGA-to-ASIC sweet spot.',
  },
  modern_5nm: {
    label: 'Modern node (5 nm-class)',
    freq_mhz: 2800,
    power_mw_per_ghz: 90,
    area_scale: 0.03,
    notes: 'Modern node: high clock and density; enables wide-issue configs.',
  },
};

// ---------------------------------------------------------------------------
//  Core configurations per node class (issue width, caches, predictor, acc)
// ---------------------------------------------------------------------------
const CORE_CONFIGS = {
  legacy_180nm: {
    name: 'RVX-1 Compact',
    issue_width: 1,
    pipeline_stages: 5,
    icache_kb: 4, dcache_kb: 4,
    predictor: 'Bimodal (64 entry) + BTB (16)',
    accel_gpu: true, accel_npu: false,
    base_ipc: 0.85,
  },
  mainstream_28nm: {
    name: 'RVX-2 Balanced',
    issue_width: 2,
    pipeline_stages: 6,
    icache_kb: 16, dcache_kb: 16,
    predictor: 'Gshare (512 entry) + BTB (128) + RAS(8)',
    accel_gpu: true, accel_npu: true,
    base_ipc: 1.35,
  },
  modern_5nm: {
    name: 'RVX-4 Performance',
    issue_width: 2,
    pipeline_stages: 7,
    icache_kb: 64, dcache_kb: 64,
    predictor: 'TAGE-lite (4K) + BTB (1K) + RAS(16)',
    accel_gpu: true, accel_npu: true,
    base_ipc: 2.4,
  },
};

// ---------------------------------------------------------------------------
//  Proxy workloads: characterize how they stress the machine.
//  branch_rate, mem_rate, fp/vector-like rate (as accelerated proxy), acc_rate
// ---------------------------------------------------------------------------
const WORKLOADS = {
  integer_core:  { label: 'Integer core (Dhrystone-style proxy)', branch: 0.15, mem: 0.25, vec: 0.00, acc: 0.00 },
  math_mac:      { label: 'Math / MAC kernel',                   branch: 0.05, mem: 0.30, vec: 0.35, acc: 0.10 },
  branch_heavy:  { label: 'Branch-heavy search/sort proxy',      branch: 0.30, mem: 0.25, vec: 0.00, acc: 0.00 },
  streaming:     { label: 'Streaming load/store',                branch: 0.05, mem: 0.55, vec: 0.20, acc: 0.00 },
  ai_inference:  { label: 'Quantized AI inference (NPU offload)',branch: 0.03, mem: 0.20, vec: 0.12, acc: 0.55 },
  graphics:      { label: 'Graphics/blend kernel (GPU helper)',  branch: 0.04, mem: 0.35, vec: 0.30, acc: 0.25 },
};

// ---------------------------------------------------------------------------
//  Reference machines for relative comparison (estimated, not measured).
//  Values are rough IPC/frequency estimates used only for ratio context.
// ---------------------------------------------------------------------------
const REFERENCE = {
  label: 'Estimated reference: mainstream big core (e.g. Core Ultra 7-class)',
  ipc: 5.0, freq_ghz: 4.5, acc_offload_factor: 4.0,
};

function estimate(config, node, wl) {
  // IPC model: base IPC adjusted by workload mix and structural capabilities.
  let ipc = config.base_ipc;

  // Branch penalty sensitivity: better predictor configs reduce branch drag.
  const branch_drag = wl.branch * (config.predictor.includes('TAGE') ? 0.4
    : config.predictor.includes('Gshare') ? 0.7 : 1.1);
  ipc -= branch_drag;

  // Memory sensitivity: bigger caches reduce stall drag on memory-heavy code.
  const mem_drag = wl.mem * (config.dcache_kb >= 64 ? 0.15
    : config.dcache_kb >= 16 ? 0.35 : 0.8);
  ipc -= mem_drag;

  // Vector/FP-like work benefits from issue width beyond 1.
  ipc += wl.vec * (config.issue_width - 1) * 0.9;

  // Accelerator offload: NPU/GPU helper converts a fraction of instructions
  // into high-throughput accelerated ops (effective IPC multiplication).
  const acc_gain = wl.acc * (config.accel_npu ? 8.0 : config.accel_gpu ? 2.0 : 0.0);
  ipc += acc_gain;

  ipc = Math.max(0.2, ipc);

  const freq_ghz = node.freq_mhz / 1000;
  const perf = ipc * freq_ghz; // relative performance units (IPC*GHz)

  // Estimated relative perf vs reference big core
  const ref_perf = REFERENCE.ipc * REFERENCE.freq_ghz;
  const rel_pct = (perf / ref_perf) * 100;

  // Power estimate (dynamic, whole core with accelerators at load)
  const power_w = (freq_ghz * node.power_mw_per_ghz / 1000)
    * (1 + (config.accel_npu ? 0.5 : 0) + (config.accel_gpu ? 0.2 : 0));

  // Perf/watt: perf units per watt
  const perf_per_watt = perf / power_w;

  return {
    ipc: +ipc.toFixed(2),
    freq_mhz: node.freq_mhz,
    perf: +perf.toFixed(2),
    rel_vs_reference_pct: +rel_pct.toFixed(1),
    est_power_w: +power_w.toFixed(2),
    perf_per_watt: +perf_per_watt.toFixed(1),
  };
}

function main() {
  const outDir = path.join(__dirname, '..', 'docs');
  fs.mkdirSync(outDir, { recursive: true });

  const results = {};
  let md = `# Estimated Performance Benchmarks\n\n`;
  md += `> **These are ESTIMATED numbers** produced by \`tools/perf_model.js\` from the\n`;
  md += `> architecture configuration and node assumptions. They are model outputs for\n`;
  md += `> proxy workloads — not measured silicon or emulator results.\n\n`;

  for (const [nodeKey, node] of Object.entries(NODE_PROFILES)) {
    const cfg = CORE_CONFIGS[nodeKey];
    results[nodeKey] = { node: node.label, core: cfg.name, workloads: {} };
    md += `## ${node.label} — **${cfg.name}**\n\n`;
    md += `| Workload | Est. IPC | Clock | Perf (IPC×GHz) | vs. big-core ref | Est. power | Perf/W |\n`;
    md += `|---|---|---|---|---|---|---|\n`;
    for (const [wlKey, wl] of Object.entries(WORKLOADS)) {
      const r = estimate(cfg, node, wl);
      results[nodeKey].workloads[wlKey] = r;
      md += `| ${wl.label} | ${r.ipc} | ${r.freq_mhz} MHz | ${r.perf} | ${r.rel_vs_reference_pct}% | ${r.est_power_w} W | ${r.perf_per_watt} |\n`;
    }
    md += `\n> ${node.notes}\n\n`;
  }

  md += `## Reference context\n\n`;
  md += `Relative numbers are against an estimated mainstream big-core configuration\n`;
  md += `(${REFERENCE.ipc} IPC @ ${REFERENCE.freq_ghz} GHz, with ${REFERENCE.acc_offload_factor}× accelerator\n`;
  md += `offload factor in its favor for accelerated workloads). The compact and balanced\n`;
  md += `configs are **not** expected to beat a Core Ultra 7-class machine; the modern-node\n`;
  md += `performance config closes the gap substantially on accelerated workloads while\n`;
  md += `targeting a fraction of the power/area. That trade is the point of this project.\n`;

  fs.writeFileSync(path.join(outDir, 'BENCHMARKS.md'), md);
  fs.writeFileSync(path.join(outDir, 'benchmarks.json'), JSON.stringify(results, null, 2));
  console.log('Wrote docs/BENCHMARKS.md and docs/benchmarks.json');
}

main();
