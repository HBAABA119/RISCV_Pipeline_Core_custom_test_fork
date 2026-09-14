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

`ifndef ISSUE_UNIT_V
`define ISSUE_UNIT_V
`include "Riscv_Defs.v"

// ============================================================================
//  Issue_Unit
//
//  Dual-issue dispatch logic for the parameterized core family.
//
//  Policy (in-order, issue-limited, no OoO):
//    - Slot 0 (primary): any instruction. Goes to the ALU/branch/load-store pipe.
//    - Slot 1 (secondary): an independent instruction immediately following
//      slot 0, issued only when:
//        * ISSUE_WIDTH == 2
//        * slot 1 is not a load, store, branch, jump, or accelerator op
//          (those use the single primary pipe to keep the design simple and
//          timing-friendly)
//        * slot 1 does not depend on slot 0's destination
//        * neither writes the same register (WAW/WAR avoidance)
//
//  This gives real dual-issue throughput on independent ALU pairs (common in
//  address arithmetic + loop bodies) without the verification burden of
//  full out-of-order.
// ============================================================================

module Issue_Unit(
    // Slot 0 (always issued when not stalled)
    input  wire        i0_valid,
    input  wire [6:0]  i0_op,
    input  wire [4:0]  i0_rd,
    input  wire [4:0]  i0_rs1,
    input  wire [4:0]  i0_rs2,

    // Slot 1 (candidate for dual issue)
    input  wire        i1_valid,
    input  wire [6:0]  i1_op,
    input  wire [4:0]  i1_rd,
    input  wire [4:0]  i1_rs1,
    input  wire [4:0]  i1_rs2,

    // Configuration
    input  wire [31:0] issue_width,       // 1 = single, 2 = dual

    // Outputs
    output wire        dual_issue         // both slots issue this cycle
);

    // -----------------------------------------------------------------------
    //  Slot classification
    // -----------------------------------------------------------------------
    // Slot 1 must be a simple ALU op (OP-IMM or OP register forms). Loads,
    // stores, branches, jumps, and system ops stay on the primary pipe.
    wire i1_is_simple_alu =
        (i1_op == OP_OPIMM) || (i1_op == OP_OP);

    wire i0_is_simple_alu =
        (i0_op == OP_OPIMM) || (i0_op == OP_OP);

    // -----------------------------------------------------------------------
    //  Dependency checks
    // -----------------------------------------------------------------------
    // Slot 1 must not read any register slot 0 writes
    wire i1_reads_i0_rd =
        ((i0_rd != 5'd0) && i0_valid &&
         ((i1_rs1 == i0_rd) || (i1_rs2 == i0_rd)));

    // No write-after-write hazard on the same destination
    wire waw = (i0_valid && i1_valid && (i0_rd == i1_rd) && (i0_rd != 5'd0));

    // Slot 1 must not read registers slot 0 reads when slot 0 writes them
    // (covered above); also require slot 0 to be a simple ALU op so the
    // bypass from slot0->slot1 in EX is straightforward.
    wire can_dual =
        (issue_width >= 32'd2) &&
        i0_valid && i1_valid &&
        i0_is_simple_alu && i1_is_simple_alu &&
        !i1_reads_i0_rd &&
        !waw;

    assign dual_issue = can_dual;

endmodule

`endif
