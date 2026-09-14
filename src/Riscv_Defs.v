// Copyright 2023-2026 MERL-DSU

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at
//
//        http://www.apache.org/licenses/LICENSE-2.0
//
//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.

// ============================================================================
//  Riscv_Defs
//
//  Shared constants and records for the parameterized RISC-V core family.
// ============================================================================

`ifndef RISCV_DEFS_V
`define RISCV_DEFS_V

// -----------------------------------------------------------------------
//  Xlen
// -----------------------------------------------------------------------
localparam XLEN = 32;

// -----------------------------------------------------------------------
//  Register file indices
// -----------------------------------------------------------------------
localparam REG_BITS = 5;
localparam REG_COUNT = 32;

// -----------------------------------------------------------------------
//  Pipeline stage names for documentation and debug
// -----------------------------------------------------------------------
localparam FETCH_STAGE  = 0;
localparam DECODE_STAGE = 1;
localparam EXECUTE_STAGE = 2;
localparam MEMORY_STAGE  = 3;
localparam WRITEBACK_STAGE = 4;

// -----------------------------------------------------------------------
//  Opcode groups
// -----------------------------------------------------------------------
localparam OP_LUI      = 7'b0110111;
localparam OP_AUIPC   = 7'b0010111;
localparam OP_JAL     = 7'b1101111;
localparam OP_JALR    = 7'b1100111;
localparam OP_BRANCH  = 7'b1100011;
localparam OP_LOAD    = 7'b0000011;
localparam OP_STORE   = 7'b0100011;
localparam OP_OPIMM   = 7'b0010011;
localparam OP_OP      = 7'b0110011;
localparam OP_FENCE   = 7'b0001111;
localparam OP_CUSTOM0 = 7'b0001000;

// -----------------------------------------------------------------------
//  Privileged / system opcode
// -----------------------------------------------------------------------
localparam OP_SYSTEM  = 7'b1110011;

// -----------------------------------------------------------------------
//  Funct3 values of interest
// -----------------------------------------------------------------------
localparam F3_ADD_SUB = 3'b000;
localparam F3_SLL     = 3'b001;
localparam F3_SLT     = 3'b010;
localparam F3_SLTU    = 3'b011;
localparam F3_XOR     = 3'b100;
localparam F3_SRL_SRA = 3'b101;
localparam F3_OR      = 3'b110;
localparam F3_AND     = 3'b111;

// -----------------------------------------------------------------------
//  Branch relation codes
// -----------------------------------------------------------------------
localparam B_EQ  = 3'b000;
localparam B_NE  = 3'b001;
localparam B_LT  = 3'b100;
localparam B_GT  = 3'b101;
localparam B_LTU = 3'b110;
localparam B_GTU = 3'b111;

// -----------------------------------------------------------------------
//  Load/store width codes
// -----------------------------------------------------------------------
localparam WIDTH_BYTE   = 2'b00;
localparam WIDTH_HALF   = 2'b01;
localparam WIDTH_WORD   = 2'b10;
localparam WIDTH_RESERVED = 2'b11;

// -----------------------------------------------------------------------
//  Result mux selection
// -----------------------------------------------------------------------
localparam RES_ALU   = 2'b00;
localparam RES_MEM   = 2'b01;
localparam RES_PC_PLUS4 = 2'b10;
localparam RES_FP    = 2'b11;

// -----------------------------------------------------------------------
//  Forwarding select codes
// -----------------------------------------------------------------------
localparam FWD_NONE   = 2'b00;
localparam FWD_WB     = 2'b01;
localparam FWD_MEM    = 2'b10;
localparam FWD_EX     = 2'b11;

// -----------------------------------------------------------------------
//  Accelerator command opcodes (custom)
// -----------------------------------------------------------------------
localparam ACC_OP_MATRIX_MUL   = 8'h01;
localparam ACC_OP_DOT_PRODUCT  = 8'h02;
localparam ACC_OP_BLend_FILTER = 8'h03;
localparam ACC_OP_TONE_MAP     = 8'h04;
localparam ACC_OP_TENSOR_MAC   = 8'h05;
localparam ACC_OP_READ_STATUS  = 8'hFE;
localparam ACC_OP_RESET        = 8'hFF;

// -----------------------------------------------------------------------
//  Accelerator status codes
// -----------------------------------------------------------------------
localparam ACC_STATUS_IDLE   = 8'h00;
localparam ACC_STATUS_BUSY   = 8'h01;
localparam ACC_STATUS_DONE   = 8'h02;
localparam ACC_STATUS_ERR    = 8'hFF;

// -----------------------------------------------------------------------
//  Number of pipeline stages (maximum supported)
// -----------------------------------------------------------------------
localparam MAX_PIPELINE_STAGES = 8;

// -----------------------------------------------------------------------
//  Cache geometry defaults (used by Cache_Core and performance model)
// -----------------------------------------------------------------------
localparam CACHE_LINE_BYTES    = 64;
localparam CACHE_LINE_BITS     = 6; // log2(64)

// -----------------------------------------------------------------------
//  Performance event IDs used by the estimation model
// -----------------------------------------------------------------------
localparam PERF_CYCLES         = 0;
localparam PERF_INST_RETIRED  = 1;
localparam PERF_BRANCH_MISPREDICT = 2;
localparam PERF_LOAD_STALL    = 3;
localparam PERF_ACC_COMMANDS  = 4;
localparam PERF_ICACHE_MISS   = 5;
localparam PERF_DCACHE_MISS   = 6;
localparam PERF_PREDICT_TAKEN = 7;
localparam PERF_PREDICT_NOT_TAKEN = 8;
localparam PERF_MUL_CYCLES    = 9;
localparam PERF_DIV_CYCLES    = 10;
localparam PERF_FP_CYCLES     = 11;

`endif
