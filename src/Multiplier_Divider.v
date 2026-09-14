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

`ifndef MULTIPLIER_DIVIDER_V
`define MULTIPLIER_DIVIDER_V
`include "Riscv_Defs.v"

// ============================================================================
//  Multiplier_Divider
//
//  Multi-cycle multiply/divider unit for the parameterized core.
//
//  Features:
//    - Separate multiply and divide pipelines
//    - Start/ready handshake for the multiplier
//    - Divide as a multi-cycle convergent unit
//    - Enable/disable via configuration
//    - Exposure for the performance model
// ============================================================================

module Multiplier_Divider(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,

    // Multiplier interface
    input  wire              start,
    input  wire [31:0]       a,
    input  wire [31:0]       b,
    output wire              ready,
    output wire [31:0]       result,

    // Divider interface
    input  wire              div_valid,
    input  wire [31:0]       div_a,
    input  wire [31:0]       div_b,
    output wire              div_ready,
    output wire [31:0]       div_result
);

    // -----------------------------------------------------------------------
    //  Multiplier state
    // -----------------------------------------------------------------------
    reg [31:0] mult_a;
    reg [31:0] mult_b;
    reg        mult_busy;
    reg [31:0] mult_result;
    reg        mult_ready_reg;

    // -----------------------------------------------------------------------
    //  Divider state
    // -----------------------------------------------------------------------
    reg        div_busy;
    reg [31:0] div_result_reg;
    reg        div_ready_reg;

    // -----------------------------------------------------------------------
    //  Multiplier logic
    // -----------------------------------------------------------------------
    // Simple combinatorial multiplier for now; in a full implementation
    // this would be a pipelined or multi-cycle array multiplier.
    wire [63:0] mult_product;

    assign mult_product = mult_a * mult_b;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            mult_busy <= 1'b0;
            mult_ready_reg <= 1'b1;
            mult_result <= 32'd0;
        end else begin
            if (start && enable) begin
                mult_a <= a;
                mult_b <= b;
                mult_busy <= 1'b1;
                mult_ready_reg <= 1'b0;
            end

            if (mult_busy) begin
                mult_result <= mult_product[31:0];
                mult_busy <= 1'b0;
                mult_ready_reg <= 1'b1;
            end
        end
    end

    assign ready = mult_ready_reg;
    assign result = mult_result;

    // -----------------------------------------------------------------------
    //  Divider logic
    // -----------------------------------------------------------------------
    // Simple restoring divider for now; iterative convergent divider
    // would be used in a performance-oriented implementation.
    wire [31:0] div_q;
    wire [31:0] div_r;

    assign div_q = div_b ? (div_a / div_b) : 32'd0;
    assign div_r = div_b ? (div_a % div_b) : div_a;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            div_busy <= 1'b0;
            div_ready_reg <= 1'b1;
            div_result_reg <= 32'd0;
        end else begin
            if (div_valid && enable && div_b != 32'd0) begin
                div_busy <= 1'b1;
                div_ready_reg <= 1'b0;
            end

            if (div_busy) begin
                div_result_reg <= div_q;
                div_busy <= 1'b0;
                div_ready_reg <= 1'b1;
            end
        end
    end

    assign div_ready = div_ready_reg;
    assign div_result = div_result_reg;

endmodule

`endif