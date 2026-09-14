// ============================================================================
//  pipeline_tb.v - Accelerator dispatch + branch prediction verification
//
//  Verifies:
//    1. Core loop program executes through the pipeline (branch/jump path)
//    2. Accelerator command path: GPU blend, GPU dot product, NPU tensor MAC
//    3. Performance counters at end of simulation
// ============================================================================
`timescale 1ns/1ps

module tb();

    reg clk = 0, rst;

    always begin
        clk = ~clk;
        #50;
    end

    // Accelerator command encoding (matches Riscv_Defs.v)
    localparam [7:0] OP_ACC_BLEND = 8'h03;  // ACC_OP_BLend_FILTER
    localparam [7:0] OP_ACC_DOT   = 8'h02;  // ACC_OP_DOT_PRODUCT
    localparam [7:0] OP_ACC_TMAC  = 8'h05;  // ACC_OP_TENSOR_MAC
    localparam [7:0] OP_ACC_READ  = 8'hFE;  // ACC_OP_READ_STATUS

    // -----------------------------------------------------------------------
    //  DUT
    // -----------------------------------------------------------------------
    reg         acc_cmd_valid_r = 0;
    reg  [31:0] acc_cmd_r = 0, acc_a0_r = 0, acc_a1_r = 0;

    wire        acc_result_valid, acc_ready, acc_valid;
    wire [31:0] acc_result, acc_cmd, acc_a0, acc_a1;
    wire [31:0] perf_mispredict, perf_acc_cmds, perf_gpu, perf_npu;

    Pipeline_Top dut (
        .clk(clk),
        .rst(rst),
        .acc_cmd_valid(acc_cmd_valid_r),
        .acc_cmd_in(acc_cmd_r),
        .acc_a0_in(acc_a0_r),
        .acc_a1_in(acc_a1_r),
        .acc_result_valid(acc_result_valid),
        .acc_result(acc_result),
        .acc_valid(acc_valid),
        .acc_cmd(acc_cmd),
        .acc_a0(acc_a0),
        .acc_a1(acc_a1),
        .acc_ready(acc_ready),
        .profile_sel(2'd1),
        .perf_branch_mispredict(perf_mispredict),
        .perf_acc_commands(perf_acc_cmds),
        .perf_gpu_ops(perf_gpu),
        .perf_npu_ops(perf_npu)
    );

    // -----------------------------------------------------------------------
    //  Command push task
    // -----------------------------------------------------------------------
    integer npu_acc = 0;
    integer last_mac = 0;
    integer results_seen = 0;

    task push_cmd(input [7:0] op, input [31:0] a0, input [31:0] a1);
    begin
        @(negedge clk);
        acc_cmd_valid_r <= 1'b1;
        acc_cmd_r       <= {24'd0, op};
        acc_a0_r        <= a0;
        acc_a1_r        <= a1;
        @(negedge clk);
        acc_cmd_valid_r <= 1'b0;
        repeat (4) @(negedge clk);
    end
    endtask

    // Result monitor: track NPU accumulation
    always @(posedge clk) begin
        if (acc_result_valid) begin
            results_seen <= results_seen + 1;
            $display("TB: acc result #%0d = 0x%08x (%0d)", results_seen, acc_result, acc_result);
        end
    end

    // -----------------------------------------------------------------------
    //  Main sequence
    // -----------------------------------------------------------------------
    initial begin
        rst <= 1'b0;
        #200;
        rst <= 1'b1;

        // Let the core loop program run (branch/jump path through predictor)
        #3000;

        $display("==== Phase 1: NPU tensor MAC x2 (accumulate) ====");
        // 4-lane MAC: {5,4,3,2} · {1,1,1,1} = 14
        push_cmd(OP_ACC_TMAC, 32'h02030405, 32'h01010101);
        // second accumulation: {10,20,30,40} · {1,1,1,1} = 100 -> acc = 114
        push_cmd(OP_ACC_TMAC, 32'h281E140A, 32'h01010101);

        $display("==== Phase 2: GPU blend (src=200, dst=100, w=0xFF) ====");
        push_cmd(OP_ACC_BLEND, 32'h000000C8, 32'h6400FF64);

        $display("==== Phase 3: GPU dot product ====");
        // {4,3,2,1} · {1,2,3,4} = 4+6+6+4 = 20
        push_cmd(OP_ACC_DOT, 32'h01020304, 32'h04030201);

        $display("==== Phase 4: NPU read accumulator (expect 114) ====");
        push_cmd(OP_ACC_READ, 32'h0, 32'h0);

        #500;

        $display("==== Performance counters ====");
        $display("Accelerator commands : %0d", perf_acc_cmds);
        $display("GPU ops              : %0d", perf_gpu);
        $display("NPU ops              : %0d", perf_npu);
        $display("Branch mispredicts   : %0d", perf_mispredict);

        $display("TB: DONE");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb);
    end
endmodule
