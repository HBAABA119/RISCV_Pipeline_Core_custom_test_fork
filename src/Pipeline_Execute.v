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

`ifndef PIPELINE_EXECUTE_V
`define PIPELINE_EXECUTE_V
`include "Riscv_Defs.v"
`include "ALU.v"
`include "Mux.v"
`include "PC_Adder.v"

// ============================================================================
//  Pipeline_Execute
//
//  Execute stage for the parameterized core.
//
//  Features:
//    - Full ALU operation set
//    - Multiplier/divider start interface for multi-cycle units
//    - Forwarding from writeback/memory
//    - Branch resolution and target calculation
//    - LSU address generation
//    - Stall / flush handling
// ============================================================================

module Pipeline_Execute(
    input  wire              clk,
    input  wire              rst,

    input  wire              flush_execute,
    input  wire              stall_fetch,

    // From decode stage
    input  wire [31:0]       pc_in,
    input  wire [31:0]       instr_in,
    input  wire [31:0]       a_in,
    input  wire [31:0]       b_in,
    input  wire [31:0]       imm_in,
    input  wire [4:0]        rs1,
    input  wire [4:0]        rs2,
    input  wire [4:0]        rd_in,
    input  wire [6:0]        op_in,
    input  wire [2:0]        funct3_in,
    input  wire [6:0]        funct7_in,
    input  wire              reg_write_in,
    input  wire              mem_read_in,
    input  wire              mem_write_in,
    input  wire              branch_in,
    input  wire              jal_in,
    input  wire              jalr_in,
    input  wire              alusrc_in,
    input  wire [2:0]        alu_control_in,
    input  wire [1:0]        result_src_in,
    input  wire [31:0]       pred_target_in,
    input  wire              pred_taken_in,

    // To memory stage
    output wire [31:0]       pc_out,
    output wire [31:0]       instr_out,
    output wire [31:0]       a_out,
    output wire [31:0]       b_out,
    output wire [31:0]       result_out,
    output wire [4:0]        rd_out,
    output wire              reg_write_out,
    output wire              mem_read_out,
    output wire              mem_write_out,
    output wire              branch_out,
    output wire              jal_out,
    output wire              jalr_out,
    output wire [1:0]        result_src_out,
    output wire [31:0]       ex_result_out,
    output wire              zero_out,

    // Multiplier / divider interface
    input  wire              mul_div_enable,
    output wire              mult_ready,
    output wire [31:0]       mult_result,
    output wire              div_valid,
    output wire [31:0]       div_result,
    input  wire              mult_start,
    input  wire [31:0]       mult_a,
    input  wire [31:0]       mult_b,

    // Forwarding from writeback / memory
    input  wire [31:0]       fwd_wdata,
    input  wire [31:0]       fwd_mdata,
    input  wire [4:0]        fwd_waddr,
    input  wire [4:0]        fwd_maddr,
    input  wire              fwd_wreg,
    input  wire              fwd_mreg,

    // Branch resolution outputs
    output wire              branch_taken_out,
    output wire [31:0]       branch_target_out,

    // LSU address generation
    output wire [31:0]       lsu_addr,
    output wire [31:0]       lsu_wdata,
    output wire              lsu_valid,
    input  wire              lsu_ready
);

    // -----------------------------------------------------------------------
    //  Forwarding muxes on A and B
    // -----------------------------------------------------------------------
    reg  [31:0] a_fwd;
    reg  [31:0] b_fwd;

    // Source A forwarding
    always @(*) begin
        if (fwd_wreg && (fwd_waddr == rs1)) begin
            a_fwd = fwd_wdata;
        end else if (fwd_mreg && (fwd_maddr == rs1)) begin
            a_fwd = fwd_mdata;
        end else begin
            a_fwd = a_in;
        end
    end

    // Source B forwarding
    always @(*) begin
        if (fwd_wreg && (fwd_waddr == rs2)) begin
            b_fwd = fwd_wdata;
        end else if (fwd_mreg && (fwd_maddr == rs2)) begin
            b_fwd = fwd_mdata;
        end else begin
            b_fwd = b_in;
        end
    end

    // -----------------------------------------------------------------------
    //  ALU source mux
    // -----------------------------------------------------------------------
    wire [31:0] alu_b;

    Mux alu_src_mux (
        .a(b_fwd),
        .b(imm_in),
        .s(alusrc_in),
        .c(alu_b)
    );

    // -----------------------------------------------------------------------
    //  ALU execution
    // -----------------------------------------------------------------------
    wire [31:0] alu_result;
    wire        alu_zero;
    wire        alu_carry;
    wire        alu_overflow;
    wire        alu_negative;

    ALU alu (
        .A          (a_fwd),
        .B          (alu_b),
        .Result     (alu_result),
        .ALUControl (alu_control_in),
        .OverFlow   (alu_overflow),
        .Carry      (alu_carry),
        .Zero       (alu_zero),
        .Negative   (alu_negative)
    );

    // -----------------------------------------------------------------------
    //  Branch condition evaluation
    // -----------------------------------------------------------------------
    // Branch is taken when the appropriate condition holds and the branch
    // instruction is present. For conditional branches the ALU zero flag
    // and comparison bits are used depending on funct3.
    wire branch_cond;
    wire branch_is_conditional;

    assign branch_is_conditional = (op_in == 7'b1100011);
    assign branch_cond = branch_is_conditional ?
        ( (funct3_in == 3'b000 && alu_zero) ||  // EQ
          (funct3_in == 3'b001 && !alu_zero) || // NE
          (funct3_in == 3'b100 && alu_negative) || // LT
          (funct3_in == 3'b101 && !alu_negative) || // GT
          (funct3_in == 3'b110 && alu_zero && alu_carry) || // LTU
          (funct3_in == 3'b111 && !(alu_zero && alu_carry)) // GTU
        ) : 1'b0;

    // -----------------------------------------------------------------------
    //  Branch taken output
    // -----------------------------------------------------------------------
    // Branch is taken if:
    //   - unconditional jump (jal/jalr) -> always taken
    //   - conditional branch and condition true
    assign branch_taken_out = (jal_in || jalr_in) ?
        1'b1 :
        (branch_in && branch_cond) ? 1'b1 : 1'b0;

    // -----------------------------------------------------------------------
    //  Branch target calculation
    // -----------------------------------------------------------------------
    // For jal: PC + imm
    // For jalr: RS1 + imm (with LSB cleared for alignment)
    // For conditional branch: PC + imm (branch offset)
    wire [31:0] jal_target;
    wire [31:0] jalr_target;

    PC_Adder jal_target_block (
        .a(pc_in),
        .b(imm_in),
        .c(jal_target)
    );

    PC_Adder jalr_target_block (
        .a(a_fwd),
        .b(imm_in),
        .c(jalr_target)
    );

    // Branch target for conditional branches is also PC + imm
    wire [31:0] branch_target_val;

    PC_Adder branch_target_block (
        .a(pc_in),
        .b(imm_in),
        .c(branch_target_val)
    );

    // -----------------------------------------------------------------------
    //  Final branch target
    // -----------------------------------------------------------------------
    reg  [31:0] branch_target_final;

    always @(*) begin
        if (jal_in) begin
            branch_target_final = jal_target;
        end else if (jalr_in) begin
            // Clear LSB for alignment on jalr
            branch_target_final = jalr_target & 32'hFFFFFFFE;
        end else if (branch_in && branch_cond) begin
            branch_target_final = branch_target_val;
        end else begin
            branch_target_final = 32'd0;
        end
    end

    assign branch_target_out = branch_target_final;

    // -----------------------------------------------------------------------
    //  LSU address generation
    // -----------------------------------------------------------------------
    // For loads/stores, the address is RS1 + immediate.
    assign lsu_addr = a_fwd + imm_in;

    // Write data for stores comes from RS2.
    assign lsu_wdata = b_fwd;
    assign lsu_valid = mem_read_in | mem_write_in;

    // -----------------------------------------------------------------------
    //  Result selection
    // -----------------------------------------------------------------------
    // EX result is the ALU result for now; multiplier/divider results are
    // merged in the memory stage.
    wire [31:0] ex_result_w;
    wire        zero_w;

    assign ex_result_w = alu_result;
    assign zero_w = alu_zero;

    // Unused multiplier/divider inputs kept for interface compatibility
    wire unused_mult_start = mult_start;
    wire [31:0] unused_mult_a = mult_a;
    wire [31:0] unused_mult_b = mult_b;

    // -----------------------------------------------------------------------
    //  Pipeline register stage
    // -----------------------------------------------------------------------
    reg [31:0] pc_reg;
    reg [31:0] instr_reg;
    reg [31:0] a_reg;
    reg [31:0] b_reg;
    reg [31:0] result_reg;
    reg [4:0]  rd_reg;
    reg        reg_write_reg;
    reg        mem_read_reg;
    reg        mem_write_reg;
    reg        branch_reg;
    reg        jal_reg;
    reg        jalr_reg;
    reg [1:0]  result_src_reg;
    reg [31:0] ex_result_reg;
    reg        zero_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc_reg <= 32'd0;
            instr_reg <= 32'd0;
            a_reg <= 32'd0;
            b_reg <= 32'd0;
            result_reg <= 32'd0;
            rd_reg <= 5'd0;
            reg_write_reg <= 1'b0;
            mem_read_reg <= 1'b0;
            mem_write_reg <= 1'b0;
            branch_reg <= 1'b0;
            jal_reg <= 1'b0;
            jalr_reg <= 1'b0;
            result_src_reg <= 2'd0;
            ex_result_reg <= 32'd0;
            zero_reg <= 1'b0;
        end else if (!stall_fetch && !flush_execute) begin
            pc_reg <= pc_in;
            instr_reg <= instr_in;
            a_reg <= a_fwd;
            b_reg <= b_fwd;
            result_reg <= alu_result;
            rd_reg <= rd_in;
            reg_write_reg <= reg_write_in;
            mem_read_reg <= mem_read_in;
            mem_write_reg <= mem_write_in;
            branch_reg <= branch_in;
            jal_reg <= jal_in;
            jalr_reg <= jalr_in;
            result_src_reg <= result_src_in;
            ex_result_reg <= ex_result_w;
            zero_reg <= zero_w;
        end
    end

    // -----------------------------------------------------------------------
    //  Output assignments
    // -----------------------------------------------------------------------
    assign pc_out = (!rst) ? pc_reg : 32'd0;
    assign instr_out = (!rst) ? instr_reg : 32'd0;
    assign a_out = (!rst) ? a_reg : 32'd0;
    assign b_out = (!rst) ? b_reg : 32'd0;
    assign result_out = (!rst) ? result_reg : 32'd0;
    assign rd_out = (!rst) ? rd_reg : 5'd0;
    assign reg_write_out = (!rst) ? reg_write_reg : 1'b0;
    assign mem_read_out = (!rst) ? mem_read_reg : 1'b0;
    assign mem_write_out = (!rst) ? mem_write_reg : 1'b0;
    assign branch_out = (!rst) ? branch_reg : 1'b0;
    assign jal_out = (!rst) ? jal_reg : 1'b0;
    assign jalr_out = (!rst) ? jalr_reg : 1'b0;
    assign result_src_out = (!rst) ? result_src_reg : 2'd0;
    assign ex_result_out = (!rst) ? ex_result_reg : 32'd0;
    assign zero_out = (!rst) ? zero_reg : 1'b0;

endmodule

`endif