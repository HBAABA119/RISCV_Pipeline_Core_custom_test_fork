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

`ifndef CORE_PARAMS_V
`define CORE_PARAMS_V
`include "Riscv_Defs.v"

// ============================================================================
//  Core_Params
//
//  Single configuration source for the parameterized core family.
//
//  Node profiles:
//    0 - Legacy node configuration: shallow pipeline, small caches,
//        minimal bypass, no accelerator, lower frequency assumptions.
//    1 - Mainstream node configuration: deeper pipeline, larger caches,
//        predictor, mul/div, optional FP, accelerator optional.
//    2 - Modern node configuration: aggressive pipeline, larger caches,
//        branch prediction + BTB, mul/div, FP, accelerator enabled,
//        higher frequency assumptions.
//
//  The same RTL source tree is reused for all profiles. Only the
//  configuration values change.
// ============================================================================

module Core_Params(
    input  wire        clk,
    input  wire        rst,

    output wire [31:0] pipeline_stages,
    output wire [31:0] issue_width,
    output wire        has_icache,
    output wire        has_dcache,
    output wire        has_predictor,
    output wire        has_mul_div,
    output wire        has_fp,
    output wire        has_accelerator,

    // Optional: allow an external host / debugger to select profile
    input  wire [1:0] profile_sel
);

    // -----------------------------------------------------------------------
    //  Configuration state
    // -----------------------------------------------------------------------
    reg [1:0] cfg_profile;
    reg [31:0] cfg_pipeline_stages;
    reg [31:0] cfg_issue_width;
    reg        cfg_has_icache;
    reg        cfg_has_dcache;
    reg        cfg_has_predictor;
    reg        cfg_has_mul_div;
    reg        cfg_has_fp;
    reg        cfg_has_accelerator;

    // -----------------------------------------------------------------------
    //  Default profile: mainstream class
    // -----------------------------------------------------------------------
    initial begin
        cfg_profile          = 2'd1;
        cfg_pipeline_stages  = 32'd5;
        cfg_issue_width      = 32'd1;
        cfg_has_icache       = 1'b1;
        cfg_has_dcache       = 1'b1;
        cfg_has_predictor    = 1'b1;
        cfg_has_mul_div      = 1'b1;
        cfg_has_fp           = 1'b0;
        cfg_has_accelerator  = 1'b1;
    end

    // -----------------------------------------------------------------------
    //  Profile selection
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cfg_profile <= 2'd1;
        end else if (profile_sel !== 2'd0) begin
            cfg_profile <= profile_sel;
        end
    end

    always @(*) begin
        case (cfg_profile)
            2'd0: begin // Legacy node
                cfg_pipeline_stages  = 32'd4;
                cfg_issue_width      = 32'd1;
                cfg_has_icache       = 1'b0;
                cfg_has_dcache       = 1'b0;
                cfg_has_predictor    = 1'b0;
                cfg_has_mul_div      = 1'b1;
                cfg_has_fp           = 1'b0;
                cfg_has_accelerator  = 1'b0;
            end
            2'd1: begin // Mainstream node
                cfg_pipeline_stages  = 32'd6;
                cfg_issue_width      = 32'd2;
                cfg_has_icache       = 1'b1;
                cfg_has_dcache       = 1'b1;
                cfg_has_predictor    = 1'b1;
                cfg_has_mul_div      = 1'b1;
                cfg_has_fp           = 1'b0;
                cfg_has_accelerator  = 1'b1;
            end
            2'd2: begin // Modern node
                cfg_pipeline_stages  = 32'd7;
                cfg_issue_width      = 32'd2;
                cfg_has_icache       = 1'b1;
                cfg_has_dcache       = 1'b1;
                cfg_has_predictor    = 1'b1;
                cfg_has_mul_div      = 1'b1;
                cfg_has_fp           = 1'b1;
                cfg_has_accelerator  = 1'b1;
            end
            default: begin
                cfg_pipeline_stages  = 32'd6;
                cfg_issue_width      = 32'd2;
                cfg_has_icache       = 1'b1;
                cfg_has_dcache       = 1'b1;
                cfg_has_predictor    = 1'b1;
                cfg_has_mul_div      = 1'b1;
                cfg_has_fp           = 1'b0;
                cfg_has_accelerator  = 1'b1;
            end
        endcase
    end

    assign pipeline_stages  = cfg_pipeline_stages;
    assign issue_width      = cfg_issue_width;
    assign has_icache       = cfg_has_icache;
    assign has_dcache       = cfg_has_dcache;
    assign has_predictor    = cfg_has_predictor;
    assign has_mul_div      = cfg_has_mul_div;
    assign has_fp           = cfg_has_fp;
    assign has_accelerator  = cfg_has_accelerator;

endmodule

`endif