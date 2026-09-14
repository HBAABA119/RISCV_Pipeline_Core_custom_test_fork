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

`ifndef BRANCH_PREDICTOR_V
`define BRANCH_PREDICTOR_V
`include "Riscv_Defs.v"

// ============================================================================
//  Branch_Predictor
//
//  Branch prediction unit for the parameterized core family.
//
//  Prediction modes (parameterized to match node profiles):
//    MODE_BIMODAL = 0 : 2-bit saturating counters + BTB (legacy profile)
//    MODE_GSHARE  = 1 : global-history-indexed 2-bit counters + BTB + RAS
//                       (mainstream profile)
//    MODE_TAGE_LITE = 2 : gshare core + longer history + larger tables +
//                         deeper RAS (modern profile)
//
//  Features:
//    - Branch target buffer (BTB) with configurable entries
//    - Return address stack (RAS) with configurable depth
//    - Global history register folded into the prediction index (gshare)
//    - Mispredict tracking for the performance model
//    - Enable/disable via configuration
// ============================================================================

module Branch_Predictor #(
    parameter PRED_MODE    = 1,    // 0=bimodal, 1=gshare, 2=tage-lite
    parameter BTB_ENTRIES  = 128,
    parameter RAS_DEPTH    = 8,
    parameter HIST_BITS    = 10
)(
    input  wire              clk,
    input  wire              rst,

    input  wire              enable,

    // From fetch stage
    input  wire [31:0]       fetch_pc,
    input  wire [31:0]       fetch_instr,
    input  wire              fetch_is_call,   // JAL with rd=x1 (call)
    input  wire              fetch_is_ret,    // JALR with rs1=x1 (return)
    output wire              predict_taken,
    output wire [31:0]       predict_target,

    // From execute stage resolution
    input  wire              branch_taken,
    input  wire [31:0]       branch_target,
    input  wire [31:0]       branch_addr,
    input  wire [31:0]       branch_instr,
    output wire              mispredict,

    // Performance counters
    output wire [31:0]       perf_branch_mispredict
);

    // -----------------------------------------------------------------------
    //  Derived geometry from mode
    // -----------------------------------------------------------------------
    localparam MODE_BIMODAL   = 0;
    localparam MODE_GSHARE    = 1;
    localparam MODE_TAGE_LITE = 2;

    // Table sizes scale with prediction capability
    localparam PRED_TABLE_ENTRIES = (PRED_MODE == MODE_TAGE_LITE) ? 4096 :
                                    (PRED_MODE == MODE_GSHARE)    ? 512  :
                                                                    64;
    localparam IDX_BITS = (PRED_TABLE_ENTRIES == 4096) ? 12 :
                          (PRED_TABLE_ENTRIES == 512)  ? 9  : 6;
    localparam BTB_INDEX_BITS = $clog2(BTB_ENTRIES);

    // Effective history length: gshare uses HIST_BITS, tage-lite doubles it
    localparam EFF_HIST_BITS = (PRED_MODE == MODE_TAGE_LITE) ? (HIST_BITS * 2) :
                               (PRED_MODE == MODE_GSHARE)    ? HIST_BITS       : 1;

    localparam PRED_COUNTER_BITS = 2;
    localparam PRED_STRONG_NOT_TAKEN = 2'b00;
    localparam PRED_WEAK_NOT_TAKEN   = 2'b01;
    localparam PRED_WEAK_TAKEN       = 2'b10;
    localparam PRED_STRONG_TAKEN     = 2'b11;

    // -----------------------------------------------------------------------
    //  Tables
    // -----------------------------------------------------------------------
    reg [31:0] btb_target [BTB_ENTRIES-1:0];
    reg        btb_valid  [BTB_ENTRIES-1:0];
    reg [PRED_COUNTER_BITS-1:0] pred_table [PRED_TABLE_ENTRIES-1:0];

    reg [EFF_HIST_BITS-1:0] global_history;
    reg [31:0] ras [RAS_DEPTH-1:0];
    reg [$clog2(RAS_DEPTH)-1:0] ras_ptr;
    reg [31:0] perf_mispredict_reg;

    integer i;

    // -----------------------------------------------------------------------
    //  Prediction indexing
    // -----------------------------------------------------------------------
    wire [BTB_INDEX_BITS-1:0] btb_index = fetch_pc[BTB_INDEX_BITS+1:2];

    // Fold the global history into the PC for the gshare/TAGE index
    wire [IDX_BITS-1:0] pc_folded  = fetch_pc[IDX_BITS+1:2];
    wire [IDX_BITS-1:0] hist_folded;
    wire [IDX_BITS-1:0] pred_index;

    generate
        if (EFF_HIST_BITS <= IDX_BITS) begin : FOLD_NARROW
            assign hist_folded = {{(IDX_BITS-EFF_HIST_BITS){1'b0}}, global_history}
                                 ^ pc_folded;
        end else begin : FOLD_WIDE
            // XOR-fold the wider history down to the index width
            reg [IDX_BITS-1:0] folded;
            integer b;
            always @(*) begin
                folded = {IDX_BITS{1'b0}};
                for (b = 0; b < EFF_HIST_BITS; b = b + 1) begin
                    folded[b % IDX_BITS] = folded[b % IDX_BITS] ^ global_history[b];
                end
            end
            assign hist_folded = folded ^ pc_folded;
        end
    endgenerate

    assign pred_index = (PRED_MODE == MODE_BIMODAL) ? pc_folded : hist_folded;

    // -----------------------------------------------------------------------
    //  Prediction
    // -----------------------------------------------------------------------
    wire btb_entry_valid = btb_valid[btb_index];
    wire [31:0] btb_entry_target = btb_target[btb_index];
    wire [PRED_COUNTER_BITS-1:0] pred_counter = pred_table[pred_index];

    wire pred_taken_raw = btb_entry_valid &&
        (pred_counter == PRED_WEAK_TAKEN || pred_counter == PRED_STRONG_TAKEN);

    wire [31:0] predict_target_raw = btb_entry_valid ? btb_entry_target
                                                     : (fetch_pc + 32'd4);

    // RAS-based return prediction takes priority for returns
    wire ras_predict = enable && fetch_is_ret && (ras_ptr > 0);

    assign predict_taken  = enable ? (ras_predict || pred_taken_raw) : 1'b0;
    assign predict_target = enable ?
        (ras_predict ? ras[ras_ptr - 1] : predict_target_raw) : 32'd4;

    // -----------------------------------------------------------------------
    //  Mispredict detection
    // -----------------------------------------------------------------------
    wire mispredict_raw = enable ?
        ( (predict_taken && !branch_taken) ||
          (!predict_taken && branch_taken) ||
          (predict_taken && branch_taken && (predict_target != branch_target)) ) : 1'b0;

    assign mispredict = mispredict_raw;

    // -----------------------------------------------------------------------
    //  Update on branch resolution
    // -----------------------------------------------------------------------
    wire [BTB_INDEX_BITS-1:0] update_index = branch_addr[BTB_INDEX_BITS+1:2];
    wire [IDX_BITS-1:0] update_pc_folded = branch_addr[IDX_BITS+1:2];
    wire [IDX_BITS-1:0] update_hist_folded;
    wire [IDX_BITS-1:0] update_pred_index;

    generate
        if (EFF_HIST_BITS <= IDX_BITS) begin : UFOLD_NARROW
            assign update_hist_folded =
                {{(IDX_BITS-EFF_HIST_BITS){1'b0}}, global_history} ^ update_pc_folded;
        end else begin : UFOLD_WIDE
            reg [IDX_BITS-1:0] ufolded;
            integer ub;
            always @(*) begin
                ufolded = {IDX_BITS{1'b0}};
                for (ub = 0; ub < EFF_HIST_BITS; ub = ub + 1) begin
                    ufolded[ub % IDX_BITS] = ufolded[ub % IDX_BITS] ^ global_history[ub];
                end
            end
            assign update_hist_folded = ufolded ^ update_pc_folded;
        end
    endgenerate

    assign update_pred_index = (PRED_MODE == MODE_BIMODAL) ? update_pc_folded
                                                           : update_hist_folded;

    // Update the history register: shift in the resolved direction.
    // NOTE: for accuracy this should happen at decode-time in program order;
    // updating at resolve is an approximation acceptable for the model.
    wire hist_shift = enable && (branch_instr[6:0] == OP_BRANCH);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            global_history <= {EFF_HIST_BITS{1'b0}};
            ras_ptr <= {$clog2(RAS_DEPTH){1'b0}};
            perf_mispredict_reg <= 32'd0;
            for (i = 0; i < PRED_TABLE_ENTRIES; i = i + 1)
                pred_table[i] <= PRED_WEAK_TAKEN;
        end else begin
            // Update prediction counter
            if (enable && branch_addr != 32'd0 &&
                (branch_instr[6:0] == OP_BRANCH ||
                 branch_instr[6:0] == OP_JAL ||
                 branch_instr[6:0] == OP_JALR)) begin
                if (branch_taken) begin
                    btb_target[update_index] <= branch_target;
                    btb_valid[update_index]  <= 1'b1;
                    if (pred_table[update_pred_index] != PRED_STRONG_TAKEN)
                        pred_table[update_pred_index] <= pred_table[update_pred_index] + 1'd1;
                end else begin
                    if (pred_table[update_pred_index] != PRED_STRONG_NOT_TAKEN)
                        pred_table[update_pred_index] <= pred_table[update_pred_index] - 1'd1;
                end

                if (mispredict_raw)
                    perf_mispredict_reg <= perf_mispredict_reg + 1'd1;
            end

            // History register update
            if (hist_shift) begin
                global_history <= {global_history[EFF_HIST_BITS-2:0], branch_taken};
            end

            // Return address stack: push on call (JAL w/ link), pop on return
            if (enable && branch_addr != 32'd0) begin
                if (branch_instr[6:0] == OP_JALR) begin
                    // Return: pop (predicted via RAS at fetch)
                    if (ras_ptr > 0)
                        ras_ptr <= ras_ptr - 1'd1;
                end else if (branch_instr[6:0] == OP_JAL) begin
                    // Call: push return address
                    if (ras_ptr < RAS_DEPTH-1) begin
                        ras[ras_ptr] <= branch_addr + 32'd4;
                        ras_ptr <= ras_ptr + 1'd1;
                    end
                end
            end
        end
    end

    assign perf_branch_mispredict = perf_mispredict_reg;

endmodule

`endif
