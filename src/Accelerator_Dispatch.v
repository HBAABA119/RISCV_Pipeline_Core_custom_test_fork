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

// ============================================================================
//  Accelerator_Dispatch
//
//  CPU-to-accelerator dispatch interface for the parameterized core family.
//
//  Provides:
//    - Command queue / handshake between core and accelerators
//    - Graphics/math helper dispatch
//    - NPU-style MAC / dot-product dispatch
//    - Status and completion interface
//    - Command counter for the performance model
// ============================================================================

module Accelerator_Dispatch(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,

    // CPU side command interface
    input  wire              cmd_valid,
    input  wire              cmd_ready,
    input  wire [31:0]       cmd_in,
    input  wire [31:0]       a0_in,
    input  wire [31:0]       a1_in,
    input  wire [31:0]       result_in,

    // Accelerator side interface
    output wire              out_valid,
    output wire [31:0]       out_cmd,
    output wire [31:0]       out_a0,
    output wire [31:0]       out_a1,

    // Performance counters
    output wire [31:0]       perf_acc_commands
);

    // -----------------------------------------------------------------------
    //  Command queue
    // -----------------------------------------------------------------------
    localparam CMD_QUEUE_DEPTH = 4;

    reg [31:0] cmd_queue [CMD_QUEUE_DEPTH-1:0];
    reg [31:0] a0_queue [CMD_QUEUE_DEPTH-1:0];
    reg [31:0] a1_queue [CMD_QUEUE_DEPTH-1:0];
    reg [3:0]  cmd_valid_q;
    reg [2:0]  cmd_head;
    reg [2:0]  cmd_tail;
    reg [31:0] acc_cmd_count;

    wire cmd_enqueue;
    wire cmd_dequeue;
    wire queue_full;
    wire queue_empty;

    assign cmd_enqueue = cmd_valid && cmd_ready && enable;
    assign cmd_dequeue = out_valid && !cmd_ready && enable;
    assign queue_full = (cmd_head == cmd_tail) && cmd_valid_q[cmd_head];
    assign queue_empty = (cmd_head == cmd_tail) && !cmd_valid_q[cmd_head];

    // -----------------------------------------------------------------------
    //  Command queue management
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cmd_head <= 3'd0;
            cmd_tail <= 3'd0;
            cmd_valid_q <= 4'd0;
            acc_cmd_count <= 32'd0;
        end else begin
            if (cmd_enqueue && !queue_full) begin
                cmd_queue[cmd_tail] <= cmd_in;
                a0_queue[cmd_tail]  <= a0_in;
                a1_queue[cmd_tail]  <= a1_in;
                cmd_valid_q[cmd_tail] <= 1'b1;
                cmd_tail <= cmd_tail + 1'd1;
                acc_cmd_count <= acc_cmd_count + 1'd1;
            end

            if (cmd_dequeue && !queue_empty) begin
                cmd_valid_q[cmd_head] <= 1'b0;
                cmd_head <= cmd_head + 1'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    //  Output assignments
    // -----------------------------------------------------------------------
    assign out_valid = enable && !queue_empty && cmd_valid_q[cmd_head];
    assign out_cmd   = enable ? cmd_queue[cmd_head] : 32'd0;
    assign out_a0    = enable ? a0_queue[cmd_head] : 32'd0;
    assign out_a1    = enable ? a1_queue[cmd_head] : 32'd0;

    assign perf_acc_commands = acc_cmd_count;

endmodule

`endif