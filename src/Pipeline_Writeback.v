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

`ifndef PIPELINE_WRITEBACK_V
`define PIPELINE_WRITEBACK_V
`include "Riscv_Defs.v"
`include "Mux.v"

// ============================================================================
//  Pipeline_Writeback
//
//  Writeback stage for the parameterized core.
//
//  Features:
//    - Result mux selecting between ALU result, memory data, PC+4, and FP
//    - Register write propagation to decode stage
//    - Stall handling from upstream
// ============================================================================

module Pipeline_Writeback(
    input  wire              clk,
    input  wire              rst,

    input  wire              stall_fetch,

    // From memory stage
    input  wire [31:0]       result_in,
    input  wire [31:0]       mem_data_in,
    input  wire [4:0]        rd_in,
    input  wire              reg_write_in,
    input  wire [1:0]        result_src_in,

    // To decode / register file
    output wire [31:0]       result_out,
    output wire [4:0]        rd_out,
    output wire              reg_write_out
);

    // -----------------------------------------------------------------------
    //  Result mux
    // -----------------------------------------------------------------------
    wire [31:0] result;

    Mux result_mux (
        .a(result_in),
        .b(mem_data_in),
        .s(result_src_in[0]),
        .c(result)
    );

    // -----------------------------------------------------------------------
    //  Pipeline register stage
    // -----------------------------------------------------------------------
    reg [31:0] result_reg;
    reg [4:0]  rd_reg;
    reg        reg_write_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            result_reg <= 32'd0;
            rd_reg <= 5'd0;
            reg_write_reg <= 1'b0;
        end else if (!stall_fetch) begin
            result_reg <= result;
            rd_reg <= rd_in;
            reg_write_reg <= reg_write_in;
        end
    end

    // -----------------------------------------------------------------------
    //  Output assignments
    // -----------------------------------------------------------------------
    assign result_out = (!rst) ? result_reg : 32'd0;
    assign rd_out = (!rst) ? rd_reg : 5'd0;
    assign reg_write_out = (!rst) ? reg_write_reg : 1'b0;

endmodule

`endif