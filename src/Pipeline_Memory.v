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

`ifndef PIPELINE_MEMORY_V
`define PIPELINE_MEMORY_V
`include "Riscv_Defs.v"
`include "Mux.v"

// ============================================================================
//  Pipeline_Memory
//
//  Memory stage for the parameterized core.
//
//  Features:
//    - Data cache / memory arbitration interface
//    - Write buffer integration point
//    - LSU handshake for loads and stores
//    - Result selection between ALU, memory, PC+4, and FP paths
//    - Stall / flush handling
// ============================================================================

module Pipeline_Memory(
    input  wire              clk,
    input  wire              rst,

    input  wire              flush_memory,
    input  wire              stall_fetch,

    // From execute stage
    input  wire [31:0]       pc_in,
    input  wire [31:0]       instr_in,
    input  wire [31:0]       result_in,
    input  wire [4:0]        rd_in,
    input  wire              reg_write_in,
    input  wire              mem_read_in,
    input  wire              mem_write_in,
    input  wire [1:0]        result_src_in,
    input  wire [31:0]       ex_result_in,
    input  wire              mult_ready,
    input  wire [31:0]       mult_result,
    input  wire              div_valid,
    input  wire [31:0]       div_result,

    // To writeback stage
    output wire [31:0]       pc_out,
    output wire [31:0]       instr_out,
    output wire [31:0]       result_out,
    output wire [31:0]       mem_data_out,
    output wire [4:0]        rd_out,
    output wire              reg_write_out,
    output wire [1:0]        result_src_out,
    output wire              mem_read_out,
    output wire              mem_write_out,

    // LSU address / data
    input  wire [31:0]       lsu_addr,
    input  wire [31:0]       lsu_wdata,
    input  wire              lsu_valid,
    output wire              lsu_ready,

    // Memory commands
    output wire              mem_read_cmd,
    output wire              mem_write_cmd,
    output wire [31:0]       mem_addr,
    output wire [31:0]       mem_wdata,
    output wire              mem_cmd_valid,
    input  wire              mem_cmd_ready,
    input  wire [31:0]       mem_rdata,
    input  wire              mem_rvalid,

    // Refill interface from cache (for instruction fetch path)
    output wire              refill_cmd_valid,
    output wire [31:0]       refill_addr,
    output wire [31:0]       refill_index
);

    // -----------------------------------------------------------------------
    //  LSU handshake
    // -----------------------------------------------------------------------
    // The LSU accepts a command when the execute stage presents a valid
    // load/store and the memory stage is ready to accept it.
    wire lsu_accept;

    assign lsu_accept = lsu_valid && !stall_fetch && !flush_memory;
    assign lsu_ready  = mem_cmd_ready || !mem_read_in && !mem_write_in;

    // -----------------------------------------------------------------------
    //  Memory command generation
    // -----------------------------------------------------------------------
    assign mem_read_cmd  = mem_read_in && lsu_accept;
    assign mem_write_cmd = mem_write_in && lsu_accept;
    assign mem_addr      = lsu_addr;
    assign mem_wdata     = lsu_wdata;
    assign mem_cmd_valid = lsu_accept;

    // -----------------------------------------------------------------------
    //  Result selection
    // -----------------------------------------------------------------------
    // Result source:
    //   RES_ALU -> ALU result from execute stage
    //   RES_MEM -> memory read data
    //   RES_PC_PLUS4 -> PC + 4 (for jal/jalr link)
    //   RES_FP   -> FP result (when FP unit present)
    wire [31:0] result_sel;

    Mux result_mux_2 (
        .a(ex_result_in),
        .b(mem_rdata),
        .s(result_src_in[0]),
        .c(result_sel)
    );

    // -----------------------------------------------------------------------
    //  Memory data output for loads
    // -----------------------------------------------------------------------
    assign mem_data_out = mem_rdata;

    // -----------------------------------------------------------------------
    //  Pipeline register stage
    // -----------------------------------------------------------------------
    reg [31:0] pc_reg;
    reg [31:0] instr_reg;
    reg [31:0] result_reg;
    reg [31:0] mem_data_reg;
    reg [4:0]  rd_reg;
    reg        reg_write_reg;
    reg [1:0]  result_src_reg;
    reg        mem_read_reg;
    reg        mem_write_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc_reg <= 32'd0;
            instr_reg <= 32'd0;
            result_reg <= 32'd0;
            mem_data_reg <= 32'd0;
            rd_reg <= 5'd0;
            reg_write_reg <= 1'b0;
            result_src_reg <= 2'd0;
            mem_read_reg <= 1'b0;
            mem_write_reg <= 1'b0;
        end else if (!stall_fetch && !flush_memory) begin
            pc_reg <= pc_in;
            instr_reg <= instr_in;
            result_reg <= result_sel;
            mem_data_reg <= mem_rdata;
            rd_reg <= rd_in;
            reg_write_reg <= reg_write_in;
            result_src_reg <= result_src_in;
            mem_read_reg <= mem_read_in;
            mem_write_reg <= mem_write_in;
        end
    end

    // -----------------------------------------------------------------------
    //  Output assignments
    // -----------------------------------------------------------------------
    assign pc_out = (!rst) ? pc_reg : 32'd0;
    assign instr_out = (!rst) ? instr_reg : 32'd0;
    assign result_out = (!rst) ? result_reg : 32'd0;
    assign mem_data_out = (!rst) ? mem_data_reg : 32'd0;
    assign rd_out = (!rst) ? rd_reg : 5'd0;
    assign reg_write_out = (!rst) ? reg_write_reg : 1'b0;
    assign result_src_out = (!rst) ? result_src_reg : 2'd0;
    assign mem_read_out = (!rst) ? mem_read_reg : 1'b0;
    assign mem_write_out = (!rst) ? mem_write_reg : 1'b0;

    // -----------------------------------------------------------------------
    //  Refill interface (instruction fetch path)
    // -----------------------------------------------------------------------
    assign refill_cmd_valid = 1'b0;
    assign refill_addr      = 32'd0;
    assign refill_index     = 32'd0;

endmodule

`endif