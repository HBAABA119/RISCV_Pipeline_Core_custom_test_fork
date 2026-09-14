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

`ifndef ACCELERATOR_DISPATCH_V
`define ACCELERATOR_DISPATCH_V
`include "Riscv_Defs.v"
`include "Graphics_Unit.v"
`include "NPU_Unit.v"

// ============================================================================
//  Accelerator_Dispatch
//
//  CPU-to-accelerator dispatch for the parameterized core family.
//
//  Routes queued commands to two functional units:
//    - Graphics_Unit (GPU helper): blend, tone-map, dot product, small matmul
//    - NPU_Unit (MAC array): tensor MAC / dot product with accumulation
//
//  Command routing (by opcode):
//    ACC_OP_BLend_FILTER / ACC_OP_TONE_MAP                 -> GPU
//    ACC_OP_MATRIX_MUL                                     -> GPU
//    ACC_OP_DOT_PRODUCT                                    -> GPU
//    ACC_OP_TENSOR_MAC / ACC_OP_READ_STATUS / ACC_OP_RESET -> NPU
//
//  Results from either unit are returned through the same result channel;
//  completion is signaled by result_valid with the originating opcode.
// ============================================================================

module Accelerator_Dispatch(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,

    // CPU side command interface
    input  wire              cmd_valid,
    output wire              cmd_ready,
    input  wire [31:0]       cmd_in,      // {opcode[7:0], reserved[23:0]}
    input  wire [31:0]       a0_in,
    input  wire [31:0]       a1_in,

    // Result interface (to writeback / polling register)
    output wire              result_valid,
    output wire [31:0]       result_data,

    // Performance counters
    output wire [31:0]       perf_acc_commands,
    output wire [31:0]       perf_gpu_ops,
    output wire [31:0]       perf_npu_ops
);

    // -----------------------------------------------------------------------
    //  Command queue
    // -----------------------------------------------------------------------
    localparam CMD_QUEUE_DEPTH = 4;

    reg [31:0] cmd_queue [CMD_QUEUE_DEPTH-1:0];
    reg [31:0] a0_queue  [CMD_QUEUE_DEPTH-1:0];
    reg [31:0] a1_queue  [CMD_QUEUE_DEPTH-1:0];
    reg [CMD_QUEUE_DEPTH-1:0] cmd_valid_q;
    reg [$clog2(CMD_QUEUE_DEPTH)-1:0] cmd_head;
    reg [$clog2(CMD_QUEUE_DEPTH)-1:0] cmd_tail;
    reg [31:0] acc_cmd_count;

    wire queue_full  = (cmd_head == cmd_tail) && cmd_valid_q[cmd_head];
    wire queue_empty = (cmd_head == cmd_tail) && !cmd_valid_q[cmd_head];

    wire head_is_gpu_cmd = (cmd_queue[cmd_head][7:0] == ACC_OP_BLend_FILTER) ||
                           (cmd_queue[cmd_head][7:0] == ACC_OP_TONE_MAP)     ||
                           (cmd_queue[cmd_head][7:0] == ACC_OP_MATRIX_MUL)   ||
                           (cmd_queue[cmd_head][7:0] == ACC_OP_DOT_PRODUCT);

    assign cmd_ready = enable && !queue_full;

    // -----------------------------------------------------------------------
    //  Functional units
    // -----------------------------------------------------------------------
    wire gpu_in_valid  = enable && !queue_empty && cmd_valid_q[cmd_head] &&  head_is_gpu_cmd;
    wire npu_in_valid  = enable && !queue_empty && cmd_valid_q[cmd_head] && !head_is_gpu_cmd;

    wire gpu_ready, npu_ready, gpu_out_valid, npu_out_valid;
    wire [31:0] gpu_out_data, npu_out_data;

    Graphics_Unit gpu_unit (
        .clk(clk), .rst(rst), .enable(enable),
        .in_valid(gpu_in_valid),
        .in_cmd(cmd_queue[cmd_head]),
        .in_a0(a0_queue[cmd_head]),
        .in_a1(a1_queue[cmd_head]),
        .in_ready(gpu_ready),
        .out_valid(gpu_out_valid),
        .out_data(gpu_out_data),
        .perf_gpu_ops(perf_gpu_ops)
    );

    NPU_Unit npu_unit (
        .clk(clk), .rst(rst), .enable(enable),
        .in_valid(npu_in_valid),
        .in_cmd(cmd_queue[cmd_head]),
        .in_a0(a0_queue[cmd_head]),
        .in_a1(a1_queue[cmd_head]),
        .in_ready(npu_ready),
        .out_valid(npu_out_valid),
        .out_data(npu_out_data),
        .perf_npu_ops(perf_npu_ops)
    );

    // A command is consumed when the target unit accepts it
    wire head_consumed = (gpu_in_valid && gpu_ready) || (npu_in_valid && npu_ready);

    // -----------------------------------------------------------------------
    //  Queue management
    // -----------------------------------------------------------------------
    wire enqueue = cmd_valid && cmd_ready;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cmd_head <= 0;
            cmd_tail <= 0;
            cmd_valid_q <= {CMD_QUEUE_DEPTH{1'b0}};
            acc_cmd_count <= 32'd0;
        end else begin
            if (enqueue) begin
                cmd_queue[cmd_tail] <= cmd_in;
                a0_queue[cmd_tail]  <= a0_in;
                a1_queue[cmd_tail]  <= a1_in;
                cmd_valid_q[cmd_tail] <= 1'b1;
                cmd_tail <= (cmd_tail == CMD_QUEUE_DEPTH-1) ? 0 : cmd_tail + 1'd1;
                acc_cmd_count <= acc_cmd_count + 1'd1;
            end

            if (head_consumed) begin
                cmd_valid_q[cmd_head] <= 1'b0;
                cmd_head <= (cmd_head == CMD_QUEUE_DEPTH-1) ? 0 : cmd_head + 1'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    //  Result arbitration: GPU has 2-cycle latency, NPU 1-cycle
    // -----------------------------------------------------------------------
    assign result_valid = gpu_out_valid || npu_out_valid;
    assign result_data  = gpu_out_valid ? gpu_out_data : npu_out_data;

    assign perf_acc_commands = acc_cmd_count;

endmodule

`endif
