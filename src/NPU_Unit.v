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

`ifndef NPU_UNIT_V
`define NPU_UNIT_V
`include "Riscv_Defs.v"

// ============================================================================
//  NPU_Unit
//
//  NPU-style MAC array for the parameterized core family.
//
//  A 4-lane INT8 multiply-accumulate array with a 32-bit accumulator:
//    - ACC_OP_TENSOR_MAC  : acc += sum(a[i]*b[i]) over 4 lanes
//    - ACC_OP_DOT_PRODUCT : acc =  sum(a[i]*b[i]) over 4 lanes (no accumulate)
//
//  The accumulator register is what makes this a real tensor-MAC datapath:
//  consecutive TENSOR_MAC commands accumulate into the running total, which
//  is read back with ACC_OP_READ_STATUS. Accumulator reset via ACC_OP_RESET.
//
//  Throughput: 1 op / cycle (fully pipelined capture + MAC).
// ============================================================================

module NPU_Unit(
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
    output wire [31:0]       perf_npu_ops
);

    // -----------------------------------------------------------------------
    //  Accumulator
    // -----------------------------------------------------------------------
    reg  [31:0] accumulator;
    reg  [31:0] op_count;
    reg         result_valid;
    reg  [31:0] result_data;

    assign in_ready = enable;

    // 4-lane signed 8-bit MAC
    wire signed [7:0] a0 = in_a0[7:0];
    wire signed [7:0] a1 = in_a0[15:8];
    wire signed [7:0] a2 = in_a0[23:16];
    wire signed [7:0] a3 = in_a0[31:24];
    wire signed [7:0] b0 = in_a1[7:0];
    wire signed [7:0] b1 = in_a1[15:8];
    wire signed [7:0] b2 = in_a1[23:16];
    wire signed [7:0] b3 = in_a1[31:24];

    wire signed [15:0] p0 = a0 * b0;
    wire signed [15:0] p1 = a1 * b1;
    wire signed [15:0] p2 = a2 * b2;
    wire signed [15:0] p3 = a3 * b3;

    wire signed [31:0] mac_sum = p0 + p1 + p2 + p3;

    wire do_mac  = in_valid && (in_cmd[7:0] == ACC_OP_TENSOR_MAC ||
                                in_cmd[7:0] == ACC_OP_DOT_PRODUCT);
    wire do_acc  = in_valid && (in_cmd[7:0] == ACC_OP_TENSOR_MAC);
    wire do_read = in_valid && (in_cmd[7:0] == ACC_OP_READ_STATUS);
    wire do_rst  = in_valid && (in_cmd[7:0] == ACC_OP_RESET);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            accumulator  <= 32'd0;
            op_count     <= 32'd0;
            result_valid <= 1'b0;
            result_data  <= 32'd0;
        end else begin
            result_valid <= 1'b0;

            if (do_mac) begin
                if (do_acc)
                    accumulator <= accumulator + mac_sum;
                else
                    accumulator <= mac_sum;
                result_valid <= 1'b1;
                result_data  <= do_acc ? (accumulator + mac_sum) : mac_sum;
                op_count     <= op_count + 1'd1;
            end

            if (do_read) begin
                result_valid <= 1'b1;
                result_data  <= accumulator;
            end

            if (do_rst) begin
                accumulator  <= 32'd0;
                result_valid <= 1'b1;
                result_data  <= 32'd0;
            end
        end
    end

    assign out_valid = enable && result_valid;
    assign out_data  = result_data;
    assign perf_npu_ops = op_count;

endmodule

`endif
