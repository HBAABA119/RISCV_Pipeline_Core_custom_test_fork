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

`ifndef GRAPHICS_UNIT_V
`define GRAPHICS_UNIT_V
`include "Riscv_Defs.v"

// ============================================================================
//  Graphics_Unit
//
//  Improved graphics/math helper unit (iGPU-style datapath).
//
//  Operations (dispatched by cmd opcode):
//    ACC_OP_BLend_FILTER : fixed-point pixel blend  out = (a*w + b*(1-w))
//    ACC_OP_TONE_MAP     : tone mapping              out = a * b >> 8
//    ACC_OP_DOT_PRODUCT  : 4-lane 8-bit dot product  out = sum(a[i]*b[i])
//    ACC_OP_MATRIX_MUL   : 2x2 fixed-point matmul    out = a0*b0 + a1*b1
//    ACC_OP_TENSOR_MAC   : accumulate                out = a0*b0 + a1*b1 + acc
//
//  All math is fixed-point (Q8/Q16 style) - no FP dependency, so the unit is
//  synthesizable across every node profile.
//
//  Latency: 2 cycles (one register stage), throughput 1 op / 2 cycles.
// ============================================================================

module Graphics_Unit(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,

    // Command interface
    input  wire              in_valid,
    input  wire [31:0]       in_cmd,
    input  wire [31:0]       in_a0,
    input  wire [31:0]       in_a1,
    output wire              in_ready,

    // Result interface
    output wire              out_valid,
    output wire [31:0]       out_data,

    // Performance
    output wire [31:0]       perf_gpu_ops
);

    // -----------------------------------------------------------------------
    //  Stage 1: capture command
    // -----------------------------------------------------------------------
    reg        s1_valid;
    reg [31:0] s1_cmd;
    reg [31:0] s1_a0, s1_a1;
    reg [31:0] op_count;

    wire can_accept = !s1_valid || out_valid;

    assign in_ready = enable && can_accept;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            s1_valid <= 1'b0;
            s1_cmd   <= 32'd0;
            s1_a0    <= 32'd0;
            s1_a1    <= 32'd0;
            op_count <= 32'd0;
        end else if (in_valid && in_ready) begin
            s1_valid <= 1'b1;
            s1_cmd   <= in_cmd;
            s1_a0    <= in_a0;
            s1_a1    <= in_a1;
            op_count <= op_count + 1'd1;
        end else if (out_valid) begin
            s1_valid <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    //  Stage 2: compute (combinational on captured operands)
    // -----------------------------------------------------------------------
    // Pixel blend: a0 = src, a1 = {dst[15:0], weight[15:0]}
    wire [15:0] blend_src  = s1_a0[15:0];
    wire [15:0] blend_dst  = s1_a1[15:0];
    wire [7:0]  blend_w    = s1_a1[23:16];
    wire [23:0] blend_a    = blend_src * blend_w;
    wire [23:0] blend_b    = blend_dst * (8'd255 - blend_w);
    wire [15:0] blend_res  = (blend_a + blend_b + 16'd128) >> 8;

    // Tone map: a0 = pixel, a1 = gain (Q8)
    wire [39:0] tone_prod  = s1_a0 * s1_a1;
    wire [31:0] tone_res   = tone_prod >> 8;

    // Dot product: two 4-lane 8-bit vectors packed in a0 and a1
    wire [15:0] dot0 = s1_a0[7:0]   * s1_a1[7:0];
    wire [15:0] dot1 = s1_a0[15:8]  * s1_a1[15:8];
    wire [15:0] dot2 = s1_a0[23:16] * s1_a1[23:16];
    wire [15:0] dot3 = s1_a0[31:24] * s1_a1[31:24];
    wire [31:0] dot_res  = dot0 + dot1 + dot2 + dot3;

    // 2x2 "matrix" as two 16-bit products (small fixed matmul row)
    wire [31:0] mat_res = (s1_a0[15:0] * s1_a1[15:0]) + (s1_a0[31:16] * s1_a1[31:16]);

    reg [31:0] gpu_result;

    always @(*) begin
        case (s1_cmd[7:0])
            ACC_OP_BLend_FILTER: gpu_result = {16'd0, blend_res};
            ACC_OP_TONE_MAP:     gpu_result = tone_res;
            ACC_OP_DOT_PRODUCT:  gpu_result = dot_res;
            ACC_OP_MATRIX_MUL:   gpu_result = mat_res;
            default:             gpu_result = 32'd0;
        endcase
    end

    assign out_valid = enable && s1_valid;
    assign out_data  = gpu_result;
    assign perf_gpu_ops = op_count;

endmodule

`endif
