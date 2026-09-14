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

`ifndef PIPELINE_DECODE_V
`define PIPELINE_DECODE_V
`include "Riscv_Defs.v"
`include "Control_Unit_Top.v"
`include "Register_File.v"
`include "Sign_Extend.v"

// ============================================================================
//  Pipeline_Decode
//
//  Decode stage for the parameterized core.
//
//  Features:
//    - Instruction decode and control generation
//    - Register file read
//    - Sign/immediate extension
//    - Forwarding from writeback and memory stages
//    - Branch predictor interface
//    - Stall / flush handling
// ============================================================================

module Pipeline_Decode(
    input  wire              clk,
    input  wire              rst,

    input  wire              stall_fetch,
    input  wire              flush_decode,

    // From fetch stage
    input  wire [31:0]       instr_in,
    input  wire [31:0]       pc_in,

    // To execute stage
    output wire [31:0]       pc_out,
    output wire [31:0]       instr_out,
    output wire [31:0]       reg_a_out,
    output wire [31:0]       reg_b_out,
    output wire [31:0]       imm_out,
    output wire [4:0]        rs1_out,
    output wire [4:0]        rs2_out,
    output wire [4:0]        rd_out,
    output wire [6:0]        op_out,
    output wire [2:0]        funct3_out,
    output wire [6:0]        funct7_out,
    output wire              reg_write_out,
    output wire              mem_read_out,
    output wire              mem_write_out,
    output wire              branch_out,
    output wire              jal_out,
    output wire              jalr_out,
    output wire              alusrc_out,
    output wire [2:0]        alu_control_out,
    output wire [1:0]        result_src_out,

    // Branch prediction interface
    input  wire              predict_taken,
    input  wire [31:0]       predict_target,
    output wire [31:0]       pred_target_out,
    output wire              pred_taken_out,

    // Register file write interface
    input  wire              rf_we,
    input  wire [31:0]       rf_wdata,
    input  wire [4:0]        rf_waddr,

    // Forwarding from writeback / memory
    input  wire [1:0]        fwd_a,
    input  wire [1:0]        fwd_b,
    input  wire [31:0]       fwd_wdata,
    input  wire [31:0]       fwd_mdata,
    input  wire [4:0]        fwd_waddr,
    input  wire [4:0]        fwd_maddr,
    input  wire              fwd_wreg,
    input  wire              fwd_mreg
);

    // -----------------------------------------------------------------------
    //  Control signals from instruction
    // -----------------------------------------------------------------------
    wire        ctrl_reg_write;
    wire        ctrl_mem_read;
    wire        ctrl_mem_write;
    wire        ctrl_branch;
    wire        ctrl_jal;
    wire        ctrl_jalr;
    wire        ctrl_alusrc;
    wire [2:0]  ctrl_alu_control;
    wire [1:0]  ctrl_result_src;
    wire [1:0]  imm_src;
    wire [1:0]  alu_op;

    // Derive load and jump classes from opcode (control unit covers the rest)
    assign ctrl_mem_read = (instr_in[6:0] == 7'b0000011);
    assign ctrl_jal      = (instr_in[6:0] == 7'b1101111);
    assign ctrl_jalr     = (instr_in[6:0] == 7'b1100111);

    Control_Unit_Top control (
        .Op           (instr_in[6:0]),
        .RegWrite     (ctrl_reg_write),
        .ImmSrc       (imm_src),
        .ALUSrc       (ctrl_alusrc),
        .MemWrite     (ctrl_mem_write),
        .ResultSrc    (ctrl_result_src),
        .Branch       (ctrl_branch),
        .funct3       (instr_in[14:12]),
        .funct7       (instr_in[31:25]),
        .ALUControl   (ctrl_alu_control)
    );

    // -----------------------------------------------------------------------
    //  Immediate extension
    // -----------------------------------------------------------------------
    wire [31:0] imm_ext;

    Sign_Extend sign_extend (
        .In        (instr_in),
        .ImmSrc    (imm_src),
        .Imm_Ext   (imm_ext)
    );

    // -----------------------------------------------------------------------
    //  Register file read
    // -----------------------------------------------------------------------
    wire [31:0] reg_a_raw;
    wire [31:0] reg_b_raw;

    Register_File reg_file (
        .clk       (clk),
        .rst       (rst),
        .WE3       (rf_we),
        .WD3       (rf_wdata),
        .A1        (instr_in[19:15]),
        .A2        (instr_in[24:20]),
        .A3        (rf_waddr),
        .RD1       (reg_a_raw),
        .RD2       (reg_b_raw)
    );

    // -----------------------------------------------------------------------
    //  Forwarding muxes
    // -----------------------------------------------------------------------
    // Source A forwarding
    reg [31:0] reg_a_fwd;
    reg [31:0] reg_b_fwd;

    always @(*) begin
        if (fwd_a == 2'b01) begin
            reg_a_fwd = fwd_wdata;
        end else if (fwd_a == 2'b10) begin
            reg_a_fwd = fwd_mdata;
        end else begin
            reg_a_fwd = reg_a_raw;
        end
    end

    always @(*) begin
        if (fwd_b == 2'b01) begin
            reg_b_fwd = fwd_wdata;
        end else if (fwd_b == 2'b10) begin
            reg_b_fwd = fwd_mdata;
        end else begin
            reg_b_fwd = reg_b_raw;
        end
    end

    // -----------------------------------------------------------------------
    //  Stall / flush handling
    // -----------------------------------------------------------------------
    reg [31:0] pc_reg;
    reg [31:0] instr_reg;
    reg [31:0] reg_a_reg;
    reg [31:0] reg_b_reg;
    reg [31:0] imm_reg;
    reg [4:0]  rs1_reg;
    reg [4:0]  rs2_reg;
    reg [4:0]  rd_reg;
    reg [6:0]  op_reg;
    reg [2:0]  funct3_reg;
    reg [6:0]  funct7_reg;
    reg        reg_write_reg;
    reg        mem_read_reg;
    reg        mem_write_reg;
    reg        branch_reg;
    reg        jal_reg;
    reg        jalr_reg;
    reg        alusrc_reg;
    reg [2:0]  alu_control_reg;
    reg [1:0]  result_src_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pc_reg <= 32'd0;
            instr_reg <= 32'd0;
            reg_a_reg <= 32'd0;
            reg_b_reg <= 32'd0;
            imm_reg <= 32'd0;
            rs1_reg <= 5'd0;
            rs2_reg <= 5'd0;
            rd_reg <= 5'd0;
            op_reg <= 7'd0;
            funct3_reg <= 3'd0;
            funct7_reg <= 7'd0;
            reg_write_reg <= 1'b0;
            mem_read_reg <= 1'b0;
            mem_write_reg <= 1'b0;
            branch_reg <= 1'b0;
            jal_reg <= 1'b0;
            jalr_reg <= 1'b0;
            alusrc_reg <= 1'b0;
            alu_control_reg <= 3'd0;
            result_src_reg <= 2'd0;
        end else if (!stall_fetch) begin
            pc_reg <= pc_in;
            instr_reg <= instr_in;
            reg_a_reg <= reg_a_fwd;
            reg_b_reg <= reg_b_fwd;
            imm_reg <= imm_ext;
            rs1_reg <= instr_in[19:15];
            rs2_reg <= instr_in[24:20];
            rd_reg <= instr_in[11:7];
            op_reg <= instr_in[6:0];
            funct3_reg <= instr_in[14:12];
            funct7_reg <= instr_in[31:25];
            reg_write_reg <= ctrl_reg_write;
            mem_read_reg <= ctrl_mem_read;
            mem_write_reg <= ctrl_mem_write;
            branch_reg <= ctrl_branch;
            jal_reg <= ctrl_jal;
            jalr_reg <= ctrl_jalr;
            alusrc_reg <= ctrl_alusrc;
            alu_control_reg <= ctrl_alu_control;
            result_src_reg <= ctrl_result_src;
        end
    end

    // -----------------------------------------------------------------------
    //  Prediction signals
    // -----------------------------------------------------------------------
    reg [31:0] pred_target_reg;
    reg        pred_taken_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pred_target_reg <= 32'd0;
            pred_taken_reg <= 1'b0;
        end else if (!stall_fetch) begin
            pred_target_reg <= predict_target;
            pred_taken_reg <= predict_taken;
        end
    end

    // -----------------------------------------------------------------------
    //  Output assignments
    // -----------------------------------------------------------------------
    assign pc_out = (!rst) ? pc_reg : 32'd0;
    assign instr_out = (!rst) ? instr_reg : 32'd0;
    assign reg_a_out = (!rst) ? reg_a_reg : 32'd0;
    assign reg_b_out = (!rst) ? reg_b_reg : 32'd0;
    assign imm_out = (!rst) ? imm_reg : 32'd0;
    assign rs1_out = (!rst) ? rs1_reg : 5'd0;
    assign rs2_out = (!rst) ? rs2_reg : 5'd0;
    assign rd_out = (!rst) ? rd_reg : 5'd0;
    assign op_out = (!rst) ? op_reg : 7'd0;
    assign funct3_out = (!rst) ? funct3_reg : 3'd0;
    assign funct7_out = (!rst) ? funct7_reg : 7'd0;
    assign reg_write_out = (!rst) ? reg_write_reg : 1'b0;
    assign mem_read_out = (!rst) ? mem_read_reg : 1'b0;
    assign mem_write_out = (!rst) ? mem_write_reg : 1'b0;
    assign branch_out = (!rst) ? branch_reg : 1'b0;
    assign jal_out = (!rst) ? jal_reg : 1'b0;
    assign jalr_out = (!rst) ? jalr_reg : 1'b0;
    assign alusrc_out = (!rst) ? alusrc_reg : 1'b0;
    assign alu_control_out = (!rst) ? alu_control_reg : 3'd0;
    assign result_src_out = (!rst) ? result_src_reg : 2'd0;
    assign pred_target_out = (!rst) ? pred_target_reg : 32'd0;
    assign pred_taken_out = (!rst) ? pred_taken_reg : 1'b0;

endmodule

`endif