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

`include "Pipeline_Fetch.v"
`include "Pipeline_Decode.v"
`include "Pipeline_Execute.v"
`include "Pipeline_Memory.v"
`include "Pipeline_Writeback.v"
`include "Branch_Predictor.v"
`include "Cache_Core.v"
`include "Multiplier_Divider.v"
`include "Accelerator_Dispatch.v"
`include "Core_Params.v"
`include "Riscv_Defs.v"

// ============================================================================
//  Pipeline_Top
//
//  Rewritten top-level for the parameterized RISC-V core family.
//  See docs/ARCHITECTURE_DIRECTION.md for the target microarchitecture.
// ============================================================================

module Pipeline_Top(
    input  wire             clk,
    input  wire             rst,

    // Accelerator command interface (CPU custom instructions / MMIO)
    input  wire             acc_cmd_valid,
    input  wire [31:0]      acc_cmd_in,
    input  wire [31:0]      acc_a0_in,
    input  wire [31:0]      acc_a1_in,
    output wire             acc_result_valid,
    output wire [31:0]      acc_result,

    // Accelerator dispatch interface (CPU -> accelerators)
    output wire             acc_valid,
    output wire [31:0]      acc_cmd,
    output wire [31:0]      acc_a0,
    output wire [31:0]      acc_a1,
    input  wire             acc_ready,

    // Node profile select: 0=legacy, 1=mainstream, 2=modern
    input  wire [1:0]       profile_sel,

    // Performance counters exposed for the estimation model
    output wire [31:0]      perf_branch_mispredict,
    output wire [31:0]      perf_acc_commands,
    output wire [31:0]      perf_gpu_ops,
    output wire [31:0]      perf_npu_ops
);

    // -----------------------------------------------------------------------
    //  Parameterized core configuration
    // -----------------------------------------------------------------------
    wire [31:0] p_pipeline_stages;
    wire [31:0] p_issue_width;
    wire        p_has_icache;
    wire        p_has_dcache;
    wire        p_has_predictor;
    wire        p_has_mul_div;
    wire        p_has_fp;
    wire        p_has_accelerator;

    Core_Params params(
        .clk(clk),
        .rst(rst),
        .profile_sel(profile_sel),
        .pipeline_stages(p_pipeline_stages),
        .issue_width(p_issue_width),
        .has_icache(p_has_icache),
        .has_dcache(p_has_dcache),
        .has_predictor(p_has_predictor),
        .has_mul_div(p_has_mul_div),
        .has_fp(p_has_fp),
        .has_accelerator(p_has_accelerator)
    );

    // -----------------------------------------------------------------------
    //  Fetch -> Decode
    // -----------------------------------------------------------------------
    wire [31:0] f_instr;
    wire [31:0] f_pc;
    wire [31:0] f_pc_next;

    // -----------------------------------------------------------------------
    //  Decode -> Execute
    // -----------------------------------------------------------------------
    wire [31:0] d_pc, d_instr, d_reg_a, d_reg_b, d_imm;
    wire [4:0]  d_rs1, d_rs2, d_rd;
    wire [6:0]  d_op;
    wire [2:0]  d_funct3;
    wire [6:0]  d_funct7;
    wire        d_reg_write, d_mem_read, d_mem_write, d_branch;
    wire        d_jal, d_jalr, d_alusrc;
    wire [2:0]  d_alu_control;
    wire [1:0]  d_result_src;
    wire [31:0] d_pred_target;
    wire        d_pred_taken;

    // -----------------------------------------------------------------------
    //  Execute -> Memory
    // -----------------------------------------------------------------------
    wire [31:0] e_pc, e_instr, e_a, e_b, e_result;
    wire [4:0]  e_rd;
    wire        e_reg_write, e_mem_read, e_mem_write, e_branch;
    wire        e_jal, e_jalr;
    wire [1:0]  e_result_src;
    wire [31:0] e_ex_result;
    wire        e_zero;
    wire        e_mult_ready;
    wire [31:0] e_mult_result;
    wire        e_div_valid;
    wire [31:0] e_div_result;
    wire        e_mult_start;
    wire [31:0] e_mult_a, e_mult_b;
    wire        branch_taken;
    wire [31:0] branch_target;

    // -----------------------------------------------------------------------
    //  Memory -> Writeback
    // -----------------------------------------------------------------------
    wire [31:0] m_pc, m_instr, m_result, m_mem_data;
    wire [4:0]  m_rd;
    wire        m_reg_write;
    wire [1:0]  m_result_src;
    wire        m_mem_read, m_mem_write;
    wire [31:0] m_lsu_addr, m_lsu_wdata;
    wire        m_lsu_valid, m_lsu_ready;

    // -----------------------------------------------------------------------
    //  Writeback
    // -----------------------------------------------------------------------
    wire [31:0] w_result;
    wire [4:0]  w_rd;
    wire        w_reg_write;

    // -----------------------------------------------------------------------
    //  Hazard / stall / flush (simplified: no structural hazards modeled)
    // -----------------------------------------------------------------------
    wire stall_fetch = 1'b0;
    wire flush_decode = mispredict_i;
    wire flush_execute = mispredict_i;
    wire flush_memory = 1'b0;
    wire mispredict_i;

    // Forwarding (EX uses MEM and WB results; simplified assignment)
    wire [1:0] fwd_a = 2'b00;
    wire [1:0] fwd_b = 2'b00;

    // -----------------------------------------------------------------------
    //  Prediction / memory-side wires
    // -----------------------------------------------------------------------
    wire        predict_taken;
    wire [31:0] predict_target;
    wire        predict_mispredict;

    wire        mem_read_cmd, mem_write_cmd, mem_cmd_valid, mem_rvalid;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire        mem_cmd_ready = 1'b1;

    // -----------------------------------------------------------------------
    //  Fetch stage
    // -----------------------------------------------------------------------
    Pipeline_Fetch fetch (
        .clk(clk),
        .rst(rst),
        .instr_out(f_instr),
        .pc_out(f_pc),
        .pc_next(f_pc_next),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .predict_taken(predict_taken),
        .predict_target(predict_target),
        .predict_mispredict(predict_mispredict),
        .stall_fetch(stall_fetch),
        .flush_decode(flush_decode),
        .icache_enable(p_has_icache),
        .ibus_valid(1'b0),
        .ibus_addr(32'd0),
        .ibus_wdata(32'd0),
        .ibus_write(1'b0),
        .ibus_ready(),
        .ibus_rdata_ext(f_instr),
        .icache_refill_valid(mem_rvalid),
        .icache_refill_data(mem_rdata),
        .icache_refill_addr(mem_addr)
    );

    // -----------------------------------------------------------------------
    //  Decode stage
    // -----------------------------------------------------------------------
    Pipeline_Decode decode (
        .clk(clk),
        .rst(rst),
        .stall_fetch(stall_fetch),
        .flush_decode(flush_decode),
        .instr_in(f_instr),
        .pc_in(f_pc),
        .pc_out(d_pc),
        .instr_out(d_instr),
        .reg_a_out(d_reg_a),
        .reg_b_out(d_reg_b),
        .imm_out(d_imm),
        .rs1_out(d_rs1),
        .rs2_out(d_rs2),
        .rd_out(d_rd),
        .op_out(d_op),
        .funct3_out(d_funct3),
        .funct7_out(d_funct7),
        .reg_write_out(d_reg_write),
        .mem_read_out(d_mem_read),
        .mem_write_out(d_mem_write),
        .branch_out(d_branch),
        .jal_out(d_jal),
        .jalr_out(d_jalr),
        .alusrc_out(d_alusrc),
        .alu_control_out(d_alu_control),
        .result_src_out(d_result_src),
        .predict_taken(predict_taken),
        .predict_target(predict_target),
        .pred_target_out(d_pred_target),
        .pred_taken_out(d_pred_taken),
        .rf_we(w_reg_write),
        .rf_wdata(w_result),
        .rf_waddr(w_rd),
        .fwd_a(fwd_a),
        .fwd_b(fwd_b),
        .fwd_wdata(e_result),
        .fwd_mdata(m_result),
        .fwd_waddr(w_rd),
        .fwd_maddr(m_rd),
        .fwd_wreg(w_reg_write),
        .fwd_mreg(m_reg_write)
    );

    // -----------------------------------------------------------------------
    //  Execute stage
    // -----------------------------------------------------------------------
    Pipeline_Execute execute (
        .clk(clk),
        .rst(rst),
        .flush_execute(flush_execute),
        .stall_fetch(stall_fetch),
        .pc_in(d_pc),
        .instr_in(d_instr),
        .a_in(d_reg_a),
        .b_in(d_reg_b),
        .imm_in(d_imm),
        .rs1(d_rs1),
        .rs2(d_rs2),
        .rd_in(d_rd),
        .op_in(d_op),
        .funct3_in(d_funct3),
        .funct7_in(d_funct7),
        .reg_write_in(d_reg_write),
        .mem_read_in(d_mem_read),
        .mem_write_in(d_mem_write),
        .branch_in(d_branch),
        .jal_in(d_jal),
        .jalr_in(d_jalr),
        .alusrc_in(d_alusrc),
        .alu_control_in(d_alu_control),
        .result_src_in(d_result_src),
        .pred_target_in(d_pred_target),
        .pred_taken_in(d_pred_taken),
        .pc_out(e_pc),
        .instr_out(e_instr),
        .a_out(e_a),
        .b_out(e_b),
        .result_out(e_result),
        .rd_out(e_rd),
        .reg_write_out(e_reg_write),
        .mem_read_out(e_mem_read),
        .mem_write_out(e_mem_write),
        .branch_out(e_branch),
        .jal_out(e_jal),
        .jalr_out(e_jalr),
        .result_src_out(e_result_src),
        .ex_result_out(e_ex_result),
        .zero_out(e_zero),
        .mul_div_enable(p_has_mul_div),
        .mult_ready(e_mult_ready),
        .mult_result(e_mult_result),
        .div_valid(e_div_valid),
        .div_result(e_div_result),
        .mult_start(e_mult_start),
        .mult_a(e_mult_a),
        .mult_b(e_mult_b),
        .fwd_wdata(w_result),
        .fwd_mdata(m_result),
        .fwd_waddr(w_rd),
        .fwd_maddr(m_rd),
        .fwd_wreg(w_reg_write),
        .fwd_mreg(m_reg_write),
        .branch_taken_out(branch_taken),
        .branch_target_out(branch_target),
        .lsu_addr(m_lsu_addr),
        .lsu_wdata(m_lsu_wdata),
        .lsu_valid(m_lsu_valid),
        .lsu_ready(m_lsu_ready)
    );

    // -----------------------------------------------------------------------
    //  Memory stage
    // -----------------------------------------------------------------------
    Pipeline_Memory mem (
        .clk(clk),
        .rst(rst),
        .flush_memory(flush_memory),
        .stall_fetch(stall_fetch),
        .pc_in(e_pc),
        .instr_in(e_instr),
        .result_in(e_result),
        .rd_in(e_rd),
        .reg_write_in(e_reg_write),
        .mem_read_in(e_mem_read),
        .mem_write_in(e_mem_write),
        .result_src_in(e_result_src),
        .ex_result_in(e_ex_result),
        .mult_ready(e_mult_ready),
        .mult_result(e_mult_result),
        .div_valid(e_div_valid),
        .div_result(e_div_result),
        .pc_out(m_pc),
        .instr_out(m_instr),
        .result_out(m_result),
        .mem_data_out(m_mem_data),
        .rd_out(m_rd),
        .reg_write_out(m_reg_write),
        .result_src_out(m_result_src),
        .mem_read_out(m_mem_read),
        .mem_write_out(m_mem_write),
        .lsu_addr(m_lsu_addr),
        .lsu_wdata(m_lsu_wdata),
        .lsu_valid(m_lsu_valid),
        .lsu_ready(m_lsu_ready),
        .mem_read_cmd(mem_read_cmd),
        .mem_write_cmd(mem_write_cmd),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_cmd_valid(mem_cmd_valid),
        .mem_cmd_ready(mem_cmd_ready),
        .mem_rdata(mem_rdata),
        .mem_rvalid(mem_rvalid),
        .refill_cmd_valid(),
        .refill_addr(),
        .refill_index()
    );

    // -----------------------------------------------------------------------
    //  Writeback stage
    // -----------------------------------------------------------------------
    Pipeline_Writeback writeback (
        .clk(clk),
        .rst(rst),
        .stall_fetch(stall_fetch),
        .result_in(m_result),
        .mem_data_in(m_mem_data),
        .rd_in(m_rd),
        .reg_write_in(m_reg_write),
        .result_src_in(m_result_src),
        .result_out(w_result),
        .rd_out(w_rd),
        .reg_write_out(w_reg_write)
    );

    // -----------------------------------------------------------------------
    //  Branch predictor
    // -----------------------------------------------------------------------
    Branch_Predictor predictor (
        .clk(clk),
        .rst(rst),
        .enable(p_has_predictor),
        .fetch_pc(f_pc),
        .fetch_instr(f_instr),
        .predict_taken(predict_taken),
        .predict_target(predict_target),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .branch_addr(e_pc),
        .branch_instr(e_instr),
        .mispredict(mispredict_i),
        .perf_branch_mispredict(perf_branch_mispredict)
    );

    // -----------------------------------------------------------------------
    //  Multiplier / divider
    // -----------------------------------------------------------------------
    Multiplier_Divider mul_div (
        .clk(clk),
        .rst(rst),
        .enable(p_has_mul_div),
        .start(e_mult_start),
        .a(e_mult_a),
        .b(e_mult_b),
        .ready(e_mult_ready),
        .result(e_mult_result),
        .div_valid(e_div_valid),
        .div_a(e_a),
        .div_b(e_b),
        .div_ready(),
        .div_result(e_div_result)
    );

    // -----------------------------------------------------------------------
    //  Accelerator dispatch
    // -----------------------------------------------------------------------
    //  Accelerator dispatch
    //  External command interface (CPU custom instructions / MMIO, or a
    //  testbench in simulation) pushes commands; results return through
    //  acc_result_valid / acc_result.
    // -----------------------------------------------------------------------
    wire        acc_result_valid_i;
    wire [31:0] acc_result_data;

    Accelerator_Dispatch acc (
        .clk(clk),
        .rst(rst),
        .enable(p_has_accelerator),
        .cmd_valid(acc_cmd_valid),
        .cmd_ready(acc_ready),
        .cmd_in(acc_cmd_in),
        .a0_in(acc_a0_in),
        .a1_in(acc_a1_in),
        .result_valid(acc_result_valid_i),
        .result_data(acc_result_data),
        .perf_acc_commands(perf_acc_commands),
        .perf_gpu_ops(perf_gpu_ops),
        .perf_npu_ops(perf_npu_ops)
    );

    assign acc_valid = p_has_accelerator && acc_ready; // consumed on accept
    assign acc_result = acc_result_data;
    assign acc_result_valid = acc_result_valid_i;

endmodule
