#!/usr/bin/env node
/**
 * Diagram generator for the RISC-V core family.
 *
 * Generates hand-built SVG diagrams (no external dependencies) so documentation
 * diagrams stay aligned with the actual architecture:
 *   docs/diagrams/system_block.svg      - top-level system block diagram
 *   docs/diagrams/pipeline.svg          - 5-stage pipeline with bypass/predictor
 *   docs/diagrams/accelerators.svg      - CPU/accelerator dispatch flow
 *   docs/diagrams/node_profiles.svg     - node profile / feature matrix
 *
 * Run: node tools/generate_diagrams.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, '..', 'docs', 'diagrams');
fs.mkdirSync(OUT_DIR, { recursive: true });

// --- tiny SVG helpers -------------------------------------------------------
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

function box(x, y, w, h, label, opts = {}) {
  const fill = opts.fill || '#1e293b';
  const stroke = opts.stroke || '#38bdf8';
  const txt = opts.color || '#e2e8f0';
  const fs_ = opts.fontSize || 14;
  return `
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="10" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>
  <text x="${x + w / 2}" y="${y + h / 2 + fs_ / 3}" text-anchor="middle"
        font-family="Segoe UI, sans-serif" font-size="${fs_}" fill="${txt}">${esc(label)}</text>`;
}

function arrow(x1, y1, x2, y2, label, opts = {}) {
  const stroke = opts.stroke || '#64748b';
  const lbl = label
    ? `<text x="${(x1 + x2) / 2}" y="${(y1 + y2) / 2 - 6}" text-anchor="middle" font-size="11" fill="${stroke}">${esc(label)}</text>`
    : '';
  return `
  <line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${stroke}" stroke-width="1.5" marker-end="url(#arr)"/>
  ${lbl}`;
}

const svgOpen = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs><marker id="arr" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
    <path d="M0,0 L0,6 L9,3 z" fill="#64748b"/></marker></defs>
  <rect width="${w}" height="${h}" fill="#0f172a"/>`;

const svgClose = () => `\n</svg>\n`;

// ---------------------------------------------------------------------------
//  1. System block diagram
// ---------------------------------------------------------------------------
function systemBlock() {
  const W = 900, H = 560;
  let s = svgOpen(W, H);
  s += `\n  <text x="450" y="40" text-anchor="middle" font-size="22" fill="#f8fafc" font-weight="600">RVX Core Family — System Block Diagram</text>`;

  // CPU core block
  s += box(60, 90, 220, 340, '', { stroke: '#38bdf8' });
  s += `<text x="170" y="115" text-anchor="middle" font-size="14" fill="#38bdf8">Scalar Core</text>`;
  s += box(80, 130, 180, 40, 'Fetch + BTB/RAS', { fontSize: 12 });
  s += box(80, 180, 180, 40, 'Decode + Rename-lite', { fontSize: 12 });
  s += box(80, 230, 180, 40, 'Execute (ALU / MUL / DIV)', { fontSize: 12 });
  s += box(80, 280, 180, 40, 'Memory (LSU + Wbuf)', { fontSize: 12 });
  s += box(80, 330, 180, 40, 'Writeback + Retire', { fontSize: 12 });

  // Branch predictor
  s += box(330, 100, 180, 80, 'Branch Predictor\n(2-bit / Gshare / TAGE-lite)', { stroke: '#f472b6', fontSize: 12 });
  s += arrow(330, 140, 285, 150, 'predict');

  // Caches
  s += box(330, 220, 180, 60, 'I-Cache / D-Cache\n(configurable geometry)', { stroke: '#facc15', fontSize: 12 });
  s += arrow(285, 300, 330, 250, 'req/fill');
  s += box(330, 320, 180, 60, 'Memory Subsystem\n(DDR / AXI bridge)', { stroke: '#94a3b8', fontSize: 12 });
  s += arrow(420, 282, 420, 318, '');

  // Accelerators
  s += box(570, 90, 280, 100, 'Graphics/Math Helper\nTransform · Blend · Tone-map\nCommand queue + completion', { stroke: '#4ade80', fontSize: 12 });
  s += box(570, 220, 280, 100, 'NPU-style MAC Array\nMatrix / Dot-product / Tensor\nINT8 / FP accumulation', { stroke: '#a78bfa', fontSize: 12 });
  s += box(570, 350, 280, 80, 'Shared Accelerator Bus\nMMIO + descriptor + status', { stroke: '#94a3b8', fontSize: 12 });
  s += arrow(570, 390, 430, 350, 'MMIO / DMA');
  s += arrow(570, 140, 570, 380, '', { stroke: '#4ade80' });
  s += arrow(570, 270, 570, 380, '', { stroke: '#a78bfa' });

  // Perf counters
  s += box(60, 460, 790, 60, 'Performance Counters: cycles · IPC · mispredicts · cache misses · accel commands → feeds perf_model.js', { stroke: '#fb923c', fontSize: 13 });

  s += svgClose();
  fs.writeFileSync(path.join(OUT_DIR, 'system_block.svg'), s);
}

// ---------------------------------------------------------------------------
//  2. Pipeline diagram
// ---------------------------------------------------------------------------
function pipeline() {
  const W = 960, H = 360;
  let s = svgOpen(W, H);
  s += `\n  <text x="480" y="40" text-anchor="middle" font-size="22" fill="#f8fafc" font-weight="600">Pipeline with Forwarding and Prediction</text>`;

  const stages = [
    ['IF', 'PC + BTB + RAS\nI-Cache access'],
    ['ID', 'Decode · RegRead\nHazard check'],
    ['EX', 'ALU / MUL / DIV\nBranch resolve'],
    ['MEM', 'D-Cache · LSU\nWrite buffer'],
    ['WB', 'Retire · RegWrite\nPerf update'],
  ];
  const x0 = 60, bw = 150, gap = 40;
  stages.forEach(([name, desc], i) => {
    const x = x0 + i * (bw + gap);
    s += box(x, 90, bw, 90, `${name}\n${desc}`, { fontSize: 12, stroke: i === 2 ? '#4ade80' : '#38bdf8' });
    if (i < stages.length - 1) s += arrow(x + bw, 135, x + bw + gap, 135, '');
  });

  // Forwarding paths
  s += arrow(330, 185, 200, 185, 'fwd M→E', { stroke: '#f472b6' });
  s += arrow(470, 210, 200, 215, 'fwd W→E', { stroke: '#f472b6' });
  // Branch redirect
  s += arrow(360, 182, 120, 60, 'mispredict → flush+redirect', { stroke: '#fb923c' });
  s += `<text x="360" y="55" font-size="12" fill="#fb923c">resolved at EX (penalty: 1–3 cycles)</text>`;

  // Predictor feedback
  s += box(60, 250, 840, 60, 'Branch Predictor feedback: GHR/BTB update at EX · 2-bit counters · Return Address Stack on JAL/JALR', { stroke: '#f472b6', fontSize: 13 });

  s += svgClose();
  fs.writeFileSync(path.join(OUT_DIR, 'pipeline.svg'), s);
}

// ---------------------------------------------------------------------------
//  3. Accelerator dispatch flow
// ---------------------------------------------------------------------------
function accelerators() {
  const W = 900, H = 480;
  let s = svgOpen(W, H);
  s += `\n  <text x="450" y="40" text-anchor="middle" font-size="22" fill="#f8fafc" font-weight="600">Accelerator Dispatch and Completion Flow</text>`;

  s += box(60, 90, 200, 60, 'Core (custom instr / MMIO)', { fontSize: 12 });
  s += box(330, 90, 220, 60, 'Accelerator Dispatch\ncommand queue · op · operands', { fontSize: 12, stroke: '#fb923c' });
  s += box(620, 60, 230, 60, 'GPU Helper\ntransform · blend · tonemap', { fontSize: 12, stroke: '#4ade80' });
  s += box(620, 160, 230, 60, 'NPU MAC Array\nmatrix · dot · tensor', { fontSize: 12, stroke: '#a78bfa' });

  s += arrow(260, 120, 328, 120, 'issue');
  s += arrow(550, 105, 618, 90, '');
  s += arrow(550, 135, 618, 190, '');

  s += box(620, 260, 230, 60, 'Result / Completion\nstatus · IRQ-like notify', { fontSize: 12, stroke: '#facc15' });
  s += arrow(735, 122, 735, 258, 'done', { stroke: '#4ade80' });
  s += arrow(735, 222, 735, 258, '', { stroke: '#a78bfa' });

  s += box(330, 270, 220, 60, 'Completion path → WB stage', { fontSize: 12, stroke: '#facc15' });
  s += arrow(618, 290, 552, 295, 'result');

  s += box(60, 270, 200, 60, 'Core continues / polls / stalls on demand', { fontSize: 12 });
  s += arrow(328, 300, 262, 300, '');

  s += box(60, 370, 790, 60, 'Shared memory region: descriptors in · results out · semaphores for sync (single-machine model, no external bus)', { fontSize: 12, stroke: '#94a3b8' });

  s += svgClose();
  fs.writeFileSync(path.join(OUT_DIR, 'accelerators.svg'), s);
}

// ---------------------------------------------------------------------------
//  4. Node profile / feature matrix
// ---------------------------------------------------------------------------
function nodeProfiles() {
  const W = 900, H = 420;
  let s = svgOpen(W, H);
  s += `\n  <text x="450" y="40" text-anchor="middle" font-size="22" fill="#f8fafc" font-weight="600">Node Profiles and Feature Matrix</text>`;

  const rows = [
    ['Feature', 'Legacy (180nm)', 'Mainstream (28nm)', 'Modern (5nm)'],
    ['Core config', 'RVX-1 Compact', 'RVX-2 Balanced', 'RVX-4 Performance'],
    ['Issue width', '1', '2', '4'],
    ['Pipeline depth', '5', '6', '7'],
    ['I/D cache', '4 KB / 4 KB', '16 KB / 16 KB', '64 KB / 64 KB'],
    ['Predictor', '2-bit + BTB32', 'Gshare + BTB128 + RAS', 'TAGE-lite + BTB1K + RAS'],
    ['GPU helper', 'Yes', 'Yes', 'Yes'],
    ['NPU MAC array', 'No', 'Yes', 'Yes'],
    ['Est. clock', '200 MHz', '800 MHz', '2.8 GHz'],
    ['Est. power', '~0.4 W', '~1.2 W', '~8 W (est.)'],
  ];
  const x0 = 60, y0 = 70, colW = 200, rowH = 32;
  rows.forEach((row, r) => {
    row.forEach((cell, c) => {
      const x = x0 + c * colW, y = y0 + r * rowH;
      const isHeader = r === 0 || c === 0;
      const fill = r === 0 ? '#1d4ed8' : c === 0 ? '#1e293b' : (r % 2 ? '#111827' : '#0f172a');
      const color = isHeader ? '#f8fafc' : '#cbd5e1';
      s += `\n  <rect x="${x}" y="${y}" width="${colW}" height="${rowH}" fill="${fill}" stroke="#334155" stroke-width="0.5"/>`;
      s += `\n  <text x="${x + 10}" y="${y + rowH / 2 + 4}" font-size="12" fill="${color}" font-family="Segoe UI, sans-serif">${esc(cell)}</text>`;
    });
  });

  s += svgClose();
  fs.writeFileSync(path.join(OUT_DIR, 'node_profiles.svg'), s);
}

systemBlock();
pipeline();
accelerators();
nodeProfiles();
console.log('Generated 4 SVG diagrams in docs/diagrams/');
