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
//  Branch prediction unit for the parameterized core.
//
//  Features:
//    - 2-bit saturating counter predictor table
//    - Branch target buffer (BTB) for target caching
//    - Return-address stack for call/return prediction
//    - Mispredict tracking for the performance model
//    - Enable/disable via configuration
// ============================================================================

module Branch_Predictor(
    input  wire              clk,
    input  wire              rst,

    input  wire              enable,

    // From fetch stage
    input  wire [31:0]       fetch_pc,
    input  wire [31:0]       fetch_instr,
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
    //  Predictor configuration
    // -----------------------------------------------------------------------
    localparam BTB_ENTRIES     = 16;
    localparam BTB_INDEX_BITS = 4;
    localparam RAS_SIZE       = 8;

    localparam PRED_COUNTER_BITS = 2;
    localparam PRED_STRONG_NOT_TAKEN = 2'b00;
    localparam PRED_WEAK_NOT_TAKEN  = 2'b01;
    localparam PRED_WEAK_TAKEN     = 2'b10;
    localparam PRED_STRONG_TAKEN     = 2'b11;

    // -----------------------------------------------------------------------
    //  BTB / predictor tables
    // -----------------------------------------------------------------------
    reg [31:0] btb_target [BTB_ENTRIES-1:0];
    reg [PRED_COUNTER_BITS-1:0] btb_pred [BTB_ENTRIES-1:0];
    reg        btb_valid [BTB_ENTRIES-1:0];

    reg [31:0] ras [RAS_SIZE-1:0];
    reg [3:0]  ras_ptr;

    reg [31:0] perf_mispredict_reg;

    // -----------------------------------------------------------------------
    //  Index / tag from PC
    // -----------------------------------------------------------------------
    wire [BTB_INDEX_BITS-1:0] btb_index;
    wire [31:0] btb_tag;

    assign btb_index = fetch_pc[BTB_INDEX_BITS+1:2];
    assign btb_tag   = fetch_pc[31:BTB_INDEX_BITS+2];

    // -----------------------------------------------------------------------
    //  Prediction
    // -----------------------------------------------------------------------
    wire [31:0] btb_entry_target;
    wire [PRED_COUNTER_BITS-1:0] btb_entry_pred;
    wire        btb_entry_valid;

    assign btb_entry_target = btb_target[btb_index];
    assign btb_entry_pred   = btb_pred[btb_index];
    assign btb_entry_valid  = btb_valid[btb_index];

    // Predict taken if strong or weak taken
    wire pred_taken_raw;

    assign pred_taken_raw = (btb_entry_valid && (btb_entry_pred == PRED_WEAK_TAKEN || btb_entry_pred == PRED_STRONG_TAKEN));

    // Predict target is either BTB target or PC+4
    wire [31:0] predict_target_raw;

    assign predict_target_raw = btb_entry_valid ? btb_entry_target : (fetch_pc + 32'd4);

    // -----------------------------------------------------------------------
    //  Final prediction outputs
    // -----------------------------------------------------------------------
    assign predict_taken = enable ? pred_taken_raw : 1'b0;
    assign predict_target = enable ? predict_target_raw : 32'd4;

    // -----------------------------------------------------------------------
    //  Mispredict detection
    // -----------------------------------------------------------------------
    // A mispredict occurs when:
    //   - We predicted taken but branch was not taken
    //   - We predicted not taken but branch was taken
    //   - Predicted target differs from actual target
    wire mispredict_raw;

    assign mispredict_raw = enable ?
        ( (predict_taken && !branch_taken) ||
          (!predict_taken && branch_taken) ||
          (predict_taken && branch_taken && (predict_target != branch_target)) ) : 1'b0;

    assign mispredict = mispredict_raw;

    // -----------------------------------------------------------------------
    //  BTB / predictor update on mispredict or correct prediction
    // -----------------------------------------------------------------------
    wire [BTB_INDEX_BITS-1:0] update_index;
    wire [31:0] update_target;
    wire [PRED_COUNTER_BITS-1:0] update_pred;

    assign update_index = branch_addr[BTB_INDEX_BITS+1:2];
    assign update_target = branch_target;

    // Update predictor state on branch resolution
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            perf_mispredict_reg <= 32'd0;
            ras_ptr <= 4'd0;
        end else if (enable && branch_addr != 32'd0) begin
            // Update BTB entry
            if (branch_taken) begin
                btb_target[update_index] <= update_target;
                btb_valid[update_index]  <= 1'b1;

                // Update 2-bit counter: taken -> increment
                if (btb_pred[update_index] != PRED_STRONG_TAKEN) begin
                    btb_pred[update_index] <= btb_pred[update_index] + 1'd1;
                end
            end else begin
                // Update 2-bit counter: not taken -> decrement
                if (btb_pred[update_index] != PRED_STRONG_NOT_TAKEN) begin
                    btb_pred[update_index] <= btb_pred[update_index] - 1'd1;
                end
            end

            // Track mispredicts
            if (mispredict_raw) begin
                perf_mispredict_reg <= perf_mispredict_reg + 1'd1;
            end

            // Return-address stack management
            // On call (jal with rd == x1 or jalr to link), push return address
            // On return (jalr from link), pop
            if (branch_instr[6:0] == 7'b1100111) begin // JALR
                // Return: pop
                if (ras_ptr > 0) begin
                    ras_ptr <= ras_ptr - 1'd1;
                end
            end else if (branch_instr[6:0] == 7'b1101111) begin // JAL
                // Call: push PC+4
                if (ras_ptr < RAS_SIZE-1) begin
                    ras[ras_ptr] <= branch_addr + 32'd4;
                    ras_ptr <= ras_ptr + 1'd1;
                end
            end
        end
    end

    assign perf_branch_mispredict = perf_mispredict_reg;

endmodule

`endif