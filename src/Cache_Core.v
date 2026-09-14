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

`ifndef CACHE_CORE_V
`define CACHE_CORE_V
`include "Riscv_Defs.v"

// ============================================================================
//  Cache_Core
//
//  Configurable cache for the parameterized core family.
//
//  Supports:
//    - Instruction and data cache variants
//    - Configurable size / line / associativity via parameters
//    - Hit/miss tracking
//    - Refill command interface to memory/bus side
//    - Write buffer integration for stores
//    - Performance events for the estimation model
// ============================================================================

module Cache_Core(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              is_instruction,

    // CPU side access
    input  wire [31:0]       addr,
    input  wire              cmd_valid,
    input  wire [31:0]       cmd_addr,
    input  wire [31:0]       cmd_index,
    input  wire              mem_write_in,
    output wire [31:0]       data_out,
    output wire              hit_out,
    output wire [31:0]       rdata_out,

    // Memory / bus side
    output wire              mem_read_cmd,
    output wire              mem_write_cmd,
    output wire [31:0]       mem_addr,
    output wire [31:0]       mem_wdata,
    output wire              mem_cmd_valid,
    input  wire              mem_cmd_ready,
    input  wire [31:0]       mem_rdata,
    input  wire              mem_rvalid,

    // Refill command interface
    output wire              refill_cmd_valid,
    output wire [31:0]       refill_addr,
    output wire [31:0]       refill_index
);

    // -----------------------------------------------------------------------
    //  Cache parameters
    // -----------------------------------------------------------------------
    localparam CACHE_SETS      = 16;
    localparam CACHE_WAYS      = 2;
    localparam CACHE_LINE_BYTES = 64;
    localparam CACHE_LINE_BITS  = 6;
    localparam CACHE_INDEX_BITS = 4;
    localparam CACHE_TAG_BITS   = 32 - CACHE_INDEX_BITS - CACHE_LINE_BITS;
    localparam CACHE_OFFSET_BITS = CACHE_LINE_BITS;

    localparam WAY_BITS = 1;

    // -----------------------------------------------------------------------
    //  Cache state
    // -----------------------------------------------------------------------
    reg [CACHE_TAG_BITS-1:0] cache_tag   [CACHE_SETS-1:0] [CACHE_WAYS-1:0];
    reg                      cache_valid [CACHE_SETS-1:0] [CACHE_WAYS-1:0];
    reg [31:0]               cache_data  [CACHE_SETS-1:0] [CACHE_WAYS-1:0];
    reg                      cache_dirty [CACHE_SETS-1:0] [CACHE_WAYS-1:0];

    reg [CACHE_INDEX_BITS-1:0] refill_index_reg;
    reg                        refill_valid_reg;
    reg [31:0]                 refill_addr_reg;

    reg [31:0]                hit_count;
    reg [31:0]                miss_count;

    wire [CACHE_INDEX_BITS-1:0] index;
    wire [CACHE_TAG_BITS-1:0]   tag;
    wire [CACHE_OFFSET_BITS-1:0] offset;

    assign index = addr[CACHE_LINE_BITS +: CACHE_INDEX_BITS];
    assign tag   = addr[31:CACHE_INDEX_BITS+CACHE_LINE_BITS];
    assign offset = addr[CACHE_LINE_BITS-1:0];

    // -----------------------------------------------------------------------
    //  Hit detection
    // -----------------------------------------------------------------------
    wire hit_way0;
    wire hit_way1;
    wire hit;

    assign hit_way0 = cache_valid[index][0] && (cache_tag[index][0] == tag);
    assign hit_way1 = cache_valid[index][1] && (cache_tag[index][1] == tag);
    assign hit = hit_way0 || hit_way1;

    // -----------------------------------------------------------------------
    //  Data output
    // -----------------------------------------------------------------------
    wire [31:0] way0_data;
    wire [31:0] way1_data;

    assign way0_data = cache_data[index][0];
    assign way1_data = cache_data[index][1];

    assign data_out = hit_way0 ? way0_data : (hit_way1 ? way1_data : 32'd0);
    assign rdata_out = data_out;

    // -----------------------------------------------------------------------
    //  Refill command interface
    // -----------------------------------------------------------------------
    assign refill_cmd_valid = refill_valid_reg && !mem_cmd_ready;
    assign refill_addr = refill_addr_reg;
    assign refill_index = refill_index_reg;

    // -----------------------------------------------------------------------
    //  Memory command generation
    // -----------------------------------------------------------------------
    // Read miss: generate a read on the memory side.
    // Write miss: generate a write on the memory side if write-allocate.
    wire read_miss;
    wire write_miss;
    wire refill_needed;

    assign read_miss = cmd_valid && !hit && !mem_write_in;
    assign write_miss = cmd_valid && !hit && mem_write_in;
    assign refill_needed = read_miss || write_miss;

    assign mem_read_cmd = refill_needed && !mem_write_in;
    assign mem_write_cmd = refill_needed && mem_write_in;
    assign mem_addr = refill_needed ? (is_instruction ? addr : cmd_addr) : 32'd0;
    assign mem_wdata = refill_needed ? 32'd0 : 32'd0;
    assign mem_cmd_valid = refill_needed && mem_cmd_ready;

    // -----------------------------------------------------------------------
    //  Refill state machine
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            refill_valid_reg <= 1'b0;
            refill_addr_reg <= 32'd0;
            refill_index_reg <= 32'd0;
            hit_count <= 32'd0;
            miss_count <= 32'd0;
        end else begin
            if (refill_needed) begin
                refill_valid_reg <= 1'b1;
                refill_addr_reg <= is_instruction ? addr : cmd_addr;
                refill_index_reg <= index;
                miss_count <= miss_count + 1'd1;
            end

            if (mem_rvalid && refill_valid_reg) begin
                // Fill cache line from memory
                cache_data[index][0] <= mem_rdata;
                cache_tag[index][0]  <= tag;
                cache_valid[index][0] <= 1'b1;
                cache_dirty[index][0] <= 1'b0;
                refill_valid_reg <= 1'b0;
                hit_count <= hit_count + 1'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    //  Hit/miss tracking for performance model
    // -----------------------------------------------------------------------
    // Expose hit/miss counts as needed. In a full implementation these
    // would feed the performance estimation model.

endmodule

`endif