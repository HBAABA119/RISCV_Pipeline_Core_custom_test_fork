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

`ifndef PIPELINE_FETCH_V
`define PIPELINE_FETCH_V
`include "Riscv_Defs.v"
`include "PC.v"
`include "PC_Adder.v"

// ============================================================================
//  Pipeline_Fetch
//
//  Fetch stage for the parameterized core.
//
//  Features:
//    - Prediction-aware PC next selection
//    - Stall / flush control from downstream stages
//    - Interaction with instruction cache and external bus / refill path
//    - PC register and PC+4 generation
// ============================================================================

module Pipeline_Fetch(
    input  wire              clk,
    input  wire              rst,

    // Outputs to decode stage
    output wire [31:0]       instr_out,
    output wire [31:0]       pc_out,
    output wire [31:0]       pc_next,

    // Redirect from execute / branch resolution
    input  wire              branch_taken,
    input  wire [31:0]       branch_target,
    input  wire              predict_taken,
    input  wire [31:0]       predict_target,
    input  wire              predict_mispredict,

    // Stall / flush from downstream
    input  wire              stall_fetch,
    input  wire              flush_decode,

    // Cache / bus configuration
    input  wire              icache_enable,
    input  wire              ibus_valid,
    input  wire  [31:0]      ibus_addr,    input  wire [31:0]       ibus_wdata,
    input  wire              ibus_write,
    output wire              ibus_ready,
    input  wire [31:0]       ibus_rdata_ext,

    // Instruction fill interface to cache
    input  wire              icache_refill_valid,
    input  wire [31:0]       icache_refill_data,
    input  wire [31:0]       icache_refill_addr
);

    // -----------------------------------------------------------------------
    //  PC generation
    // -----------------------------------------------------------------------
    wire [31:0] pc_current;
    wire [31:0] pc_plus4;
    wire [31:0] pc_branch;
    wire [31:0] pc_pred;
    wire [31:0] pc_select;
    wire        use_branch;
    wire        use_predict;
    wire        use_flush;

    // PC register output (driven by PC_Module below)
    wire [31:0] pc_current_reg;

    // PC + 4
    assign pc_plus4 = pc_current + 32'd4;

    // Branch redirect target comes from execute as an absolute address
    assign pc_branch = branch_target;

    // Predict target comes from the predictor as an absolute address
    assign pc_pred = predict_target;

    // -----------------------------------------------------------------------
    //  PC next selection logic
    // -----------------------------------------------------------------------
    // Priority:
    //   1) Mispredict flush or explicit branch taken from execute
    //   2) Prediction taken target from predictor
    //   3) Sequential PC + 4
    assign use_flush = flush_decode;
    assign use_branch = branch_taken;
    assign use_predict = predict_taken;

    assign pc_select = (use_flush || use_branch) ? pc_branch :
                       (use_predict)             ? pc_pred   :
                       pc_plus4;

    // -----------------------------------------------------------------------
    //  PC register
    // -----------------------------------------------------------------------
    PC_Module pc_module (
        .clk(clk),
        .rst(rst),
        .PC(pc_current),
        .PC_Next(pc_next)
    );

    // Hold PC on stall: re-apply current PC
    assign pc_next = stall_fetch ? pc_current : pc_select;

    // -----------------------------------------------------------------------
    //  Instruction fetch
    // -----------------------------------------------------------------------
    // If instruction cache is enabled, fetch from cache and allow refill
    // from the memory side via icache_refill interface.
    //
    // If instruction cache is disabled, fetch from the external bus interface.
    //
    // This matches the top-level configuration for legacy vs modern nodes.
    wire [31:0] instr_raw;
    wire        fetch_valid;

    // -----------------------------------------------------------------------
    //  Instruction source selection
    // -----------------------------------------------------------------------
    // When cache is enabled, the cache drives instr_out. Otherwise we use
    // the external bus interface.
    //
    // In the legacy configuration, the 'memory' side is just a memory array
    // that is accessed directly. In modern configurations, it goes through
    // the cache hierarchy.
    assign instr_raw = icache_enable ?
        icache_refill_data : ibus_rdata;

    // -----------------------------------------------------------------------
    //  Fetch valid signal
    // -----------------------------------------------------------------------
    // The fetch is stalled when the pipeline stalls upstream. Otherwise the
    // fetched instruction is valid as long as we are not in reset.
    assign fetch_valid = (!rst) && (!stall_fetch);

    // -----------------------------------------------------------------------
    //  Output assignments
    // -----------------------------------------------------------------------
    assign instr_out = fetch_valid ? instr_raw : 32'd0;
    assign pc_out    = (!rst) ? pc_current : 32'd0;

    // -----------------------------------------------------------------------
    //  External bus handshake (for legacy / reload paths)
    // -----------------------------------------------------------------------
    assign ibus_ready = (!rst) && !icache_enable && ibus_valid;
    assign ibus_rdata = (!rst) ? 32'd0 : ibus_rdata_ext;

endmodule

`endif