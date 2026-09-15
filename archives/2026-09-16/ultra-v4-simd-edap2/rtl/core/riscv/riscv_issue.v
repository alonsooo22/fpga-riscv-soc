//-----------------------------------------------------------------
//                         RISC-V Core
//                            V1.0.1
//                     Ultra-Embedded.com
//                     Copyright 2014-2019
//
//                   admin@ultra-embedded.com
//
//                       License: BSD
//-----------------------------------------------------------------
//
// Copyright (c) 2014-2019, Ultra-Embedded.com
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions 
// are met:
//   - Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//   - Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer 
//     in the documentation and/or other materials provided with the 
//     distribution.
//   - Neither the name of the author nor the names of its contributors 
//     may be used to endorse or promote products derived from this 
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR 
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE 
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
// THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF 
// SUCH DAMAGE.
//-----------------------------------------------------------------

module riscv_issue #(
    parameter SUPPORT_XBEXTU = 0,
    parameter SUPPORT_XPACK16 = 0,
    parameter SUPPORT_XDOT2H = 0,
    parameter SUPPORT_XADD16 = 0,
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
     parameter SUPPORT_MULDIV   = 1
    ,parameter SUPPORT_DUAL_ISSUE = 1
    ,parameter SUPPORT_LOAD_BYPASS = 1
    ,parameter SUPPORT_MUL_BYPASS = 1
    ,parameter SUPPORT_REGFILE_XILINX = 0
    ,parameter SUPPORT_EARLY_TCM_LOAD = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
     ,input           fetch_valid_i
     ,input  [ 31:0]  fetch_instr_i
     ,input  [ 31:0]  fetch_pc_i
    ,input           fetch_pred_taken_i
     ,input           fetch_fault_fetch_i
    ,input           fetch_fault_page_i
    ,input           fetch_instr_exec_i
    ,input           fetch_instr_lsu_i
    ,input           fetch_instr_branch_i
    ,input           fetch_instr_mul_i
    ,input           fetch_instr_div_i
    ,input           fetch_instr_csr_i
    ,input           fetch_instr_rd_valid_i
    ,input           fetch_instr_invalid_i
    ,input           branch_exec_request_i
    ,input           branch_exec_is_taken_i
    ,input           branch_exec_is_not_taken_i
    ,input  [ 31:0]  branch_exec_source_i
    ,input           branch_exec_is_call_i
    ,input           branch_exec_is_ret_i
    ,input           branch_exec_is_jmp_i
    ,input  [ 31:0]  branch_exec_pc_i
    ,input           branch_d_exec_taken_i
    ,input  [ 31:0]  branch_d_exec_target_i
    ,input           branch_d_exec_mispredict_i
    ,input  [ 31:0]  branch_d_exec_correction_pc_i
     ,input  [  1:0]  branch_d_exec_priv_i
    ,input           branch_csr_request_i
    ,input  [ 31:0]  branch_csr_pc_i
    ,input  [  1:0]  branch_csr_priv_i
    ,input  [ 31:0]  writeback_exec_value_i
    ,input           writeback_mem_valid_i
    ,input  [ 31:0]  writeback_mem_value_i
    ,input  [  5:0]  writeback_mem_exception_i
    ,input  [ 31:0]  writeback_mul_value_i
    ,input           writeback_div_valid_i
    ,input  [ 31:0]  writeback_div_value_i
    ,input  [ 31:0]  csr_result_e1_value_i
    ,input           csr_result_e1_write_i
    ,input  [ 31:0]  csr_result_e1_wdata_i
    ,input  [  5:0]  csr_result_e1_exception_i
    ,input           lsu_stall_i
    ,input           take_interrupt_i
    ,input           early_load_accept_i
    ,input           early_result_valid_i
    ,input  [31:0]   early_result_value_i
    ,input  [  4:0]  early_result_rd_i

    // Outputs
    ,output          fetch_accept_o
    ,output          branch_request_o
    ,output [ 31:0]  branch_pc_o
    ,output [  1:0]  branch_priv_o
     ,output          exec_opcode_valid_o
    ,output          lsu_opcode_valid_o
    ,output          csr_opcode_valid_o
    ,output          mul_opcode_valid_o
    ,output          div_opcode_valid_o
     ,output [ 31:0]  opcode_opcode_o
     ,output [ 31:0]  opcode_pc_o
    ,output          opcode_pred_taken_o
     ,output          opcode_invalid_o
    ,output [  4:0]  opcode_rd_idx_o
    ,output [  4:0]  opcode_ra_idx_o
    ,output [  4:0]  opcode_rb_idx_o
    ,output [ 31:0]  opcode_ra_operand_o
    ,output [ 31:0]  opcode_rb_operand_o
    ,output [ 31:0]  lsu_opcode_opcode_o
    ,output [ 31:0]  lsu_opcode_pc_o
    ,output          lsu_opcode_invalid_o
    ,output [  4:0]  lsu_opcode_rd_idx_o
    ,output [  4:0]  lsu_opcode_ra_idx_o
    ,output [  4:0]  lsu_opcode_rb_idx_o
    ,output [ 31:0]  lsu_opcode_ra_operand_o
    ,output [ 31:0]  lsu_opcode_rb_operand_o
    ,output [ 31:0]  mul_opcode_opcode_o
    ,output [ 31:0]  mul_opcode_pc_o
    ,output          mul_opcode_invalid_o
    ,output [  4:0]  mul_opcode_rd_idx_o
    ,output [  4:0]  mul_opcode_ra_idx_o
    ,output [  4:0]  mul_opcode_rb_idx_o
    ,output [ 31:0]  mul_opcode_ra_operand_o
    ,output [ 31:0]  mul_opcode_rb_operand_o
    ,output [ 31:0]  csr_opcode_opcode_o
    ,output [ 31:0]  csr_opcode_pc_o
    ,output          csr_opcode_invalid_o
    ,output [  4:0]  csr_opcode_rd_idx_o
    ,output [  4:0]  csr_opcode_ra_idx_o
    ,output [  4:0]  csr_opcode_rb_idx_o
    ,output [ 31:0]  csr_opcode_ra_operand_o
    ,output [ 31:0]  csr_opcode_rb_operand_o
    ,output          csr_writeback_write_o
    ,output [ 11:0]  csr_writeback_waddr_o
    ,output [ 31:0]  csr_writeback_wdata_o
    ,output [  5:0]  csr_writeback_exception_o
    ,output [ 31:0]  csr_writeback_exception_pc_o
    ,output [ 31:0]  csr_writeback_exception_addr_o
    ,output          exec_hold_o
    ,output          mul_hold_o
     ,output          interrupt_inhibit_o
     ,output          early_base_ok_o
     ,output [31:0]   early_base_value_o
     ,output          early_result_consume_o
`ifdef ULTRA_PERF_COUNTERS
    ,output          retire_valid_o
    ,output [31:0]   retire_count_o
    ,output          perf_scoreboard_stall_o
    ,output          perf_pipe_stall_o
    ,output          perf_div_wait_o
    ,output          perf_csr_wait_o
`endif
);



`include "riscv_defs.v"

wire enable_muldiv_w     = SUPPORT_MULDIV;
wire enable_mul_bypass_w = SUPPORT_MUL_BYPASS;

wire stall_w;
wire squash_w;

//-------------------------------------------------------------
// Priv level
//-------------------------------------------------------------
reg [1:0] priv_x_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    priv_x_q <= `PRIV_MACHINE;
else if (branch_csr_request_i)
    priv_x_q <= branch_csr_priv_i;

//-------------------------------------------------------------
// Issue Select
//-------------------------------------------------------------
wire opcode_valid_w = fetch_valid_i & ~squash_w & ~branch_csr_request_i;

// Branch request (CSR branch - ecall, xret, or branch instruction)
assign branch_request_o     = branch_csr_request_i | branch_d_exec_mispredict_i;
assign branch_pc_o          = branch_csr_request_i ? branch_csr_pc_i : branch_d_exec_correction_pc_i;
assign branch_priv_o        = branch_csr_request_i ? branch_csr_priv_i : priv_x_q;

//-------------------------------------------------------------
// Instruction Decoder
//-------------------------------------------------------------
wire [4:0] issue_ra_idx_w   = fetch_instr_i[19:15];
// XBEXTU carries immediate bits in the raw rs2 field; it has no rs2 source.
wire xbextu_issue_w = SUPPORT_XBEXTU &&
    ((fetch_instr_i & `INST_XBEXTU_MASK) == `INST_XBEXTU);
wire [4:0] issue_rb_idx_w = xbextu_issue_w ? 5'b0 : fetch_instr_i[24:20];
wire [4:0] issue_rd_idx_w   = fetch_instr_i[11:7];
wire       issue_sb_alloc_w = fetch_instr_rd_valid_i;
wire       issue_exec_w     = fetch_instr_exec_i;
wire       issue_lsu_w      = fetch_instr_lsu_i;
wire       issue_branch_w   = fetch_instr_branch_i;
wire       issue_mul_w      = fetch_instr_mul_i;
wire       issue_div_w      = fetch_instr_div_i;
wire       issue_csr_w      = fetch_instr_csr_i;
wire       issue_invalid_w  = fetch_instr_invalid_i;

//-------------------------------------------------------------
// Pipeline status tracking
//------------------------------------------------------------- 
wire        pipe_squash_e1_e2_w;

reg         opcode_issue_r;
reg         opcode_accept_r;
wire        pipe_stall_raw_w;

wire        pipe_load_e1_w;
wire        pipe_store_e1_w;
wire        pipe_mul_e1_w;
wire        pipe_branch_e1_w;
wire [4:0]  pipe_rd_e1_w;

wire [31:0] pipe_pc_e1_w;
wire [31:0] pipe_opcode_e1_w;
wire [31:0] pipe_operand_ra_e1_w;
wire [31:0] pipe_operand_rb_e1_w;

wire        pipe_load_e2_w;
wire        pipe_mul_e2_w;
wire [4:0]  pipe_rd_e2_w;
wire [31:0] pipe_result_e2_w;
wire        fast_load_e1_w;
wire        fast_load_e2_w;
wire        early_result_consume_w;

wire        pipe_valid_wb_w;
wire        pipe_csr_wb_w;
wire [4:0]  pipe_rd_wb_w;
wire [31:0] pipe_result_wb_w;
wire [31:0] pipe_pc_wb_w;
wire [31:0] pipe_opc_wb_w;
wire [31:0] pipe_ra_val_wb_w;
wire [31:0] pipe_rb_val_wb_w;
wire [`EXCEPTION_W-1:0] pipe_exception_wb_w;

wire [`EXCEPTION_W-1:0] issue_fault_w = fetch_fault_fetch_i ? `EXCEPTION_FAULT_FETCH:
                                        fetch_fault_page_i  ? `EXCEPTION_PAGE_FAULT_INST: `EXCEPTION_W'b0;

riscv_pipe_ctrl
#( 
     .SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
)
u_pipe_ctrl
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)    

    // Issue
    ,.issue_valid_i(opcode_issue_r)
    ,.issue_accept_i(opcode_accept_r)
    ,.issue_stall_i(stall_w)
    ,.issue_lsu_i(issue_lsu_w)
    ,.issue_csr_i(issue_csr_w)
    ,.issue_div_i(issue_div_w)
    ,.issue_mul_i(issue_mul_w)
    ,.issue_branch_i(issue_branch_w)
    ,.issue_rd_valid_i(issue_sb_alloc_w)
    ,.issue_rd_i(issue_rd_idx_w)
    ,.issue_exception_i(issue_fault_w)
    ,.issue_pc_i(opcode_pc_o)
    ,.issue_opcode_i(opcode_opcode_o)
    ,.issue_operand_ra_i(opcode_ra_operand_o)
    ,.issue_operand_rb_i(opcode_rb_operand_o)
    ,.issue_branch_taken_i(branch_d_exec_taken_i)
    ,.issue_branch_target_i(branch_d_exec_target_i)
    ,.take_interrupt_i(take_interrupt_i)
    ,.early_load_accept_i(early_load_accept_i)
    ,.early_result_valid_i(early_result_valid_i)
    ,.early_result_value_i(early_result_value_i)
    ,.early_result_rd_i(early_result_rd_i)

    // Execution stage 1: ALU result
    ,.alu_result_e1_i(writeback_exec_value_i)
    ,.csr_result_value_e1_i(csr_result_e1_value_i)
    ,.csr_result_write_e1_i(csr_result_e1_write_i)
    ,.csr_result_wdata_e1_i(csr_result_e1_wdata_i)
    ,.csr_result_exception_e1_i(csr_result_e1_exception_i)

    // Execution stage 1
    ,.load_e1_o(pipe_load_e1_w)
    ,.store_e1_o(pipe_store_e1_w)
    ,.mul_e1_o(pipe_mul_e1_w)
    ,.branch_e1_o(pipe_branch_e1_w)
    ,.rd_e1_o(pipe_rd_e1_w)
    ,.pc_e1_o(pipe_pc_e1_w)
    ,.opcode_e1_o(pipe_opcode_e1_w)
    ,.operand_ra_e1_o(pipe_operand_ra_e1_w)
    ,.operand_rb_e1_o(pipe_operand_rb_e1_w)

    // Execution stage 2: Other results
    ,.mem_complete_i(writeback_mem_valid_i)
    ,.mem_result_e2_i(writeback_mem_value_i)
    ,.mem_exception_e2_i(writeback_mem_exception_i)
    ,.mul_result_e2_i(writeback_mul_value_i)

    // Execution stage 2
    ,.load_e2_o(pipe_load_e2_w)
    ,.mul_e2_o(pipe_mul_e2_w)
    ,.rd_e2_o(pipe_rd_e2_w)
    ,.result_e2_o(pipe_result_e2_w)
    ,.fast_load_e1_o(fast_load_e1_w)
    ,.fast_load_e2_o(fast_load_e2_w)
    ,.early_result_consume_o(early_result_consume_w)

    ,.stall_o(pipe_stall_raw_w)
    ,.squash_e1_e2_o(pipe_squash_e1_e2_w)
    ,.squash_e1_e2_i(1'b0)
    ,.squash_wb_i(1'b0)

    // Out of pipe: Divide Result
    ,.div_complete_i(writeback_div_valid_i)
    ,.div_result_i(writeback_div_value_i)

    // Commit
    ,.valid_wb_o(pipe_valid_wb_w)
    ,.csr_wb_o(pipe_csr_wb_w)
    ,.rd_wb_o(pipe_rd_wb_w)
    ,.result_wb_o(pipe_result_wb_w)
    ,.pc_wb_o(pipe_pc_wb_w)
    ,.opcode_wb_o(pipe_opc_wb_w)
    ,.operand_ra_wb_o(pipe_ra_val_wb_w)
    ,.operand_rb_wb_o(pipe_rb_val_wb_w)
    ,.exception_wb_o(pipe_exception_wb_w)
    ,.csr_write_wb_o(csr_writeback_write_o)
    ,.csr_waddr_wb_o(csr_writeback_waddr_o)
    ,.csr_wdata_wb_o(csr_writeback_wdata_o)   
);

assign exec_hold_o = stall_w;
assign mul_hold_o  = stall_w;
`ifdef ULTRA_PERF_COUNTERS
/* Performance-only observer: this is the same writeback/commit valid used
 * by the existing Verilator completion hook below. */
assign retire_valid_o = pipe_valid_wb_w;
reg [31:0] retire_count_q;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    retire_count_q <= 32'b0;
else if (pipe_valid_wb_w)
    retire_count_q <= retire_count_q + 32'd1;

assign retire_count_o = retire_count_q;
`endif

//-------------------------------------------------------------
// Pipe1 - Status tracking
//-------------------------------------------------------------
assign csr_writeback_exception_o      = pipe_exception_wb_w;
assign csr_writeback_exception_pc_o   = pipe_pc_wb_w;
assign csr_writeback_exception_addr_o = pipe_result_wb_w;

//-------------------------------------------------------------
// Blocking events (division, CSR unit access)
//-------------------------------------------------------------
reg div_pending_q;
reg csr_pending_q;
`ifdef ULTRA_PERF_COUNTERS
reg csr_diag_pending_q;
wire csr_diag_opcode_w =
       (opcode_opcode_o[31:20] == `CSR_MCYCLE)
    || (opcode_opcode_o[31:20] == `CSR_MTIME)
    || (opcode_opcode_o[31:20] == `CSR_MINSTRET)
    || (opcode_opcode_o[31:20] == `CSR_INSTRET)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_SCOREBOARD)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_LSU)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_PIPE)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_DIV)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_CSR)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_BRANCH_REQUEST)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_BRANCH_REDIRECT)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_BRANCH_FLUSH)
    || (opcode_opcode_o[31:20] == `CSR_ULTRA_FETCH_STARVE);
`endif

// Division operations take 2 - 34 cycles and stall
// the pipeline (complete out-of-pipe) until completed.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    div_pending_q <= 1'b0;
else if (pipe_squash_e1_e2_w)
    div_pending_q <= 1'b0;
else if (div_opcode_valid_o && issue_div_w)
    div_pending_q <= 1'b1;
else if (writeback_div_valid_i)
    div_pending_q <= 1'b0;

// CSR operations are infrequent - avoid any complications of pipelining them.
// These only take a 2-3 cycles anyway and may result in a pipe flush (e.g. ecall, ebreak..).
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    csr_pending_q <= 1'b0;
else if (pipe_squash_e1_e2_w)
    csr_pending_q <= 1'b0;
else if (csr_opcode_valid_o && issue_csr_w)
    csr_pending_q <= 1'b1;
else if (pipe_csr_wb_w)
    csr_pending_q <= 1'b0;

`ifdef ULTRA_PERF_COUNTERS
// Exclude the cycle/minstret/HPM reads used by the measurement port from the
// CSR-wait event itself. The normal CSR pending state remains unchanged.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    csr_diag_pending_q <= 1'b0;
else if (pipe_squash_e1_e2_w)
    csr_diag_pending_q <= 1'b0;
else if (csr_opcode_valid_o && issue_csr_w)
    csr_diag_pending_q <= csr_diag_opcode_w;
else if (pipe_csr_wb_w)
    csr_diag_pending_q <= 1'b0;
`endif

assign squash_w = pipe_squash_e1_e2_w;

//-------------------------------------------------------------
// Issue / scheduling logic
//-------------------------------------------------------------
reg [31:0] scoreboard_r;
`ifdef ULTRA_PERF_COUNTERS
reg        scoreboard_hazard_r;
`endif

// Keep the pre-allocation dependency set separate from scoreboard_r.  The
// latter is also used to reserve the current destination, while this vector
// is used by the narrow E-TCM release predicate and cannot form a feedback
// path through that reservation.
wire [31:0] scoreboard_base_w =
       (((SUPPORT_LOAD_BYPASS == 0) && pipe_load_e2_w) ?
        (32'b1 << pipe_rd_e2_w) : 32'b0)
     | (((SUPPORT_MUL_BYPASS == 0) && pipe_mul_e2_w) ?
        (32'b1 << pipe_rd_e2_w) : 32'b0)
     | ((pipe_load_e1_w || pipe_mul_e1_w) ?
        (32'b1 << pipe_rd_e1_w) : 32'b0);

wire [6:0] issue_major_w = fetch_instr_i[6:0];
wire early_alu_imm_w = issue_exec_w && (issue_major_w == 7'b0010011);
wire early_alu_reg_w = issue_exec_w && (issue_major_w == 7'b0110011);
wire early_branch_w  = issue_branch_w && (issue_major_w == 7'b1100011);
wire early_store_w   = issue_lsu_w && !issue_sb_alloc_w &&
                       (issue_major_w == 7'b0100011);
wire early_consumer_w = !issue_invalid_w &&
                        (early_alu_imm_w || early_alu_reg_w ||
                         early_branch_w || early_store_w);
wire early_uses_ra_w = early_alu_imm_w || early_alu_reg_w ||
                       early_branch_w || early_store_w;
wire early_uses_rb_w = early_alu_reg_w || early_branch_w || early_store_w;

// The early load result is an alternative value for the single current E1
// producer. Keep its validity/identity separate from the consumer release
// predicate so the 32-bit value mux is shared by both operands.
wire early_e1_value_valid_w = fast_load_e1_w && early_result_valid_i &&
                              (pipe_rd_e1_w != 5'b0) &&
                              (early_result_rd_i == pipe_rd_e1_w);
wire [31:0] e1_producer_value_w = early_e1_value_valid_w ?
                                  early_result_value_i :
                                  writeback_exec_value_i;
wire fast_match_ra_w = early_e1_value_valid_w &&
                       (issue_ra_idx_w != 5'b0) &&
                       (pipe_rd_e1_w == issue_ra_idx_w);
wire fast_match_rb_w = early_e1_value_valid_w &&
                       (issue_rb_idx_w != 5'b0) &&
                       (pipe_rd_e1_w == issue_rb_idx_w);
wire fast_single_dep_w = fast_match_ra_w ^ fast_match_rb_w;
wire early_other_raw_w =
       (early_uses_ra_w && (issue_ra_idx_w != 5'b0) &&
        scoreboard_base_w[issue_ra_idx_w] && !fast_match_ra_w)
     || (early_uses_rb_w && (issue_rb_idx_w != 5'b0) &&
        scoreboard_base_w[issue_rb_idx_w] && !fast_match_rb_w);
wire early_waw_w = issue_sb_alloc_w && (issue_rd_idx_w != 5'b0) &&
                   scoreboard_base_w[issue_rd_idx_w];

// Only one current E1 fast-LW dependency may be released.  Backend, DIV,
// CSR, structural, other RAW, and WAW protections remain on the normal path.
wire early_release_w = (SUPPORT_EARLY_TCM_LOAD != 0) && opcode_valid_w &&
                       !take_interrupt_i && early_consumer_w &&
                       fast_single_dep_w && !early_other_raw_w &&
                       !early_waw_w;

// The early load address may be generated only when the final base source is
// RF or WB.  The ordinary mux priority is E1 > E2 > WB > RF, so an E1/E2
// match is explicitly excluded; x0 is the architectural RF-zero case.
wire early_base_e1_w = (issue_ra_idx_w != 5'b0) &&
                       (pipe_rd_e1_w == issue_ra_idx_w);
wire early_base_e2_w = (issue_ra_idx_w != 5'b0) &&
                       (pipe_rd_e2_w == issue_ra_idx_w);
assign early_base_ok_o = (issue_ra_idx_w == 5'b0) ||
                         (!early_base_e1_w && !early_base_e2_w);

// The early AGU has a deliberately smaller source contract than the normal
// operand mux.  It may use the physical register-file read or the actual WB
// result saved by pipe_ctrl, but never an E1/E2 result or the early result
// itself.  early_base_ok_o above excludes an E1/E2 producer; this value is
// therefore safe to present to the LSU whenever that contract is true.
wire early_base_wb_hit_w = pipe_valid_wb_w &&
                           (issue_ra_idx_w != 5'b0) &&
                           (pipe_rd_wb_w == issue_ra_idx_w);
reg [31:0] early_base_value_r;
always @ *
begin
    early_base_value_r = issue_ra_value_w;

    if (early_base_wb_hit_w)
        early_base_value_r = pipe_result_wb_w;

    if (issue_ra_idx_w == 5'b0)
        early_base_value_r = 32'b0;
end
assign early_base_value_o = early_base_value_r;

always @ *
begin
    opcode_issue_r     = 1'b0;
    opcode_accept_r    = 1'b0;
    scoreboard_r       = scoreboard_base_w;
`ifdef ULTRA_PERF_COUNTERS
    scoreboard_hazard_r = 1'b0;
`endif

    // Do not start multiply, division or CSR operation in the cycle after a load (leaving only ALU operations and branches)
    if ((pipe_load_e1_w || pipe_store_e1_w) && (issue_mul_w || issue_div_w || issue_csr_w))
        scoreboard_r = 32'hFFFFFFFF;

`ifdef ULTRA_PERF_COUNTERS
    // Capture the dependency condition before the current instruction's
    // destination is allocated into scoreboard_r below.
    if (opcode_valid_w &&
        (scoreboard_base_w[issue_ra_idx_w] ||
         scoreboard_base_w[issue_rb_idx_w] ||
         scoreboard_base_w[issue_rd_idx_w]))
        scoreboard_hazard_r = 1'b1;
`endif

    // Stall - no issues...
    if (lsu_stall_i || stall_w || div_pending_q || csr_pending_q)
        ;
    // Primary slot (lsu, branch, alu, mul, div, csr)
    else if (opcode_valid_w &&
        (!(scoreboard_r[issue_ra_idx_w] ||
           scoreboard_r[issue_rb_idx_w] ||
           scoreboard_r[issue_rd_idx_w]) || early_release_w))
    begin
        opcode_issue_r  = 1'b1;
        opcode_accept_r = 1'b1;

        if (opcode_accept_r && issue_sb_alloc_w && (|issue_rd_idx_w))
            scoreboard_r[issue_rd_idx_w] = 1'b1;
    end 
end

assign lsu_opcode_valid_o   = opcode_issue_r & ~take_interrupt_i;
assign exec_opcode_valid_o  = opcode_issue_r;
assign mul_opcode_valid_o   = enable_muldiv_w & opcode_issue_r;
assign div_opcode_valid_o   = enable_muldiv_w & opcode_issue_r;
assign interrupt_inhibit_o  = csr_pending_q || issue_csr_w;
assign early_result_consume_o = early_result_consume_w;

assign fetch_accept_o       = opcode_valid_w ? (opcode_accept_r & ~take_interrupt_i) : 1'b1;

assign stall_w              = pipe_stall_raw_w;

`ifdef ULTRA_PERF_COUNTERS
// This isolates a scoreboard dependency from the independent backend blocks.
wire perf_backend_block_w = lsu_stall_i || stall_w || div_pending_q || csr_pending_q;
wire perf_scoreboard_stall_w = opcode_valid_w && !take_interrupt_i &&
                               !perf_backend_block_w && scoreboard_hazard_r &&
                               !early_release_w;
assign perf_scoreboard_stall_o = perf_scoreboard_stall_w;
assign perf_pipe_stall_o       = stall_w;
assign perf_div_wait_o         = div_pending_q;
assign perf_csr_wait_o         = csr_pending_q && !csr_diag_pending_q;
`endif

// Follow-up diagnostics are compiled only into the isolated experiment.
// The accepted baseline has no scoreboard observer or extra control logic.
`ifdef ULTRA_SCOREBOARD_TRACE
`ifdef verilator
`include "scoreboard_trace.vh"
`endif
`endif

//-------------------------------------------------------------
// Register File
//------------------------------------------------------------- 
wire [31:0] issue_ra_value_w;
wire [31:0] issue_rb_value_w;
wire [31:0] issue_b_ra_value_w;
wire [31:0] issue_b_rb_value_w;

// Register file: 1W2R
riscv_regfile
#(
     .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX)
)
u_regfile
(
    .clk_i(clk_i),
    .rst_i(rst_i),

    // Write ports
    .rd0_i(pipe_rd_wb_w),
    .rd0_value_i(pipe_result_wb_w),

    // Read ports
    .ra0_i(issue_ra_idx_w),
    .rb0_i(issue_rb_idx_w),
    .ra0_value_o(issue_ra_value_w),
    .rb0_value_o(issue_rb_value_w)
);

//-------------------------------------------------------------
// Issue Slot 0
//------------------------------------------------------------- 
assign opcode_opcode_o = fetch_instr_i;
assign opcode_pc_o     = fetch_pc_i;
assign opcode_pred_taken_o = fetch_pred_taken_i;
assign opcode_rd_idx_o = issue_rd_idx_w;
assign opcode_ra_idx_o = issue_ra_idx_w;
assign opcode_rb_idx_o = issue_rb_idx_w;
assign opcode_invalid_o= 1'b0; 

reg [31:0] issue_ra_value_r;
reg [31:0] issue_rb_value_r;

always @ *
begin
    // NOTE: Newest version of operand takes priority
    issue_ra_value_r = issue_ra_value_w;
    issue_rb_value_r = issue_rb_value_w;

    // Bypass - WB
    if (pipe_rd_wb_w == issue_ra_idx_w)
        issue_ra_value_r = pipe_result_wb_w;
    if (pipe_rd_wb_w == issue_rb_idx_w)
        issue_rb_value_r = pipe_result_wb_w;

    // Bypass - E2
    if (pipe_rd_e2_w == issue_ra_idx_w)
        issue_ra_value_r = pipe_result_e2_w;
    if (pipe_rd_e2_w == issue_rb_idx_w)
        issue_rb_value_r = pipe_result_e2_w;

    // Bypass - E1. The producer value is shared: an accepted fast load uses
    // the early result, while every other E1 instruction uses the ordinary
    // execution result.
    if (pipe_rd_e1_w == issue_ra_idx_w)
        issue_ra_value_r = e1_producer_value_w;
    if (pipe_rd_e1_w == issue_rb_idx_w)
        issue_rb_value_r = e1_producer_value_w;

    // Reg 0 source
    if (issue_ra_idx_w == 5'b0)
        issue_ra_value_r = 32'b0;
    if (issue_rb_idx_w == 5'b0)
        issue_rb_value_r = 32'b0;
end

assign opcode_ra_operand_o = issue_ra_value_r;
assign opcode_rb_operand_o = issue_rb_value_r;

//-------------------------------------------------------------
// Load store unit
//-------------------------------------------------------------
assign lsu_opcode_opcode_o      = opcode_opcode_o;
assign lsu_opcode_pc_o          = opcode_pc_o;
assign lsu_opcode_rd_idx_o      = opcode_rd_idx_o;
assign lsu_opcode_ra_idx_o      = opcode_ra_idx_o;
assign lsu_opcode_rb_idx_o      = opcode_rb_idx_o;
assign lsu_opcode_ra_operand_o  = opcode_ra_operand_o;
assign lsu_opcode_rb_operand_o  = opcode_rb_operand_o;
assign lsu_opcode_invalid_o     = 1'b0;

//-------------------------------------------------------------
// Multiply
//-------------------------------------------------------------
assign mul_opcode_opcode_o      = opcode_opcode_o;
assign mul_opcode_pc_o          = opcode_pc_o;
assign mul_opcode_rd_idx_o      = opcode_rd_idx_o;
assign mul_opcode_ra_idx_o      = opcode_ra_idx_o;
assign mul_opcode_rb_idx_o      = opcode_rb_idx_o;
assign mul_opcode_ra_operand_o  = opcode_ra_operand_o;
assign mul_opcode_rb_operand_o  = opcode_rb_operand_o;
assign mul_opcode_invalid_o     = 1'b0;

//-------------------------------------------------------------
// CSR unit
//-------------------------------------------------------------
assign csr_opcode_valid_o       = opcode_issue_r & ~take_interrupt_i;
assign csr_opcode_opcode_o      = opcode_opcode_o;
assign csr_opcode_pc_o          = opcode_pc_o;
assign csr_opcode_rd_idx_o      = opcode_rd_idx_o;
assign csr_opcode_ra_idx_o      = opcode_ra_idx_o;
assign csr_opcode_rb_idx_o      = opcode_rb_idx_o;
assign csr_opcode_ra_operand_o  = opcode_ra_operand_o;
assign csr_opcode_rb_operand_o  = opcode_rb_operand_o;
assign csr_opcode_invalid_o     = opcode_issue_r && issue_invalid_w;


//-------------------------------------------------------------
// Checker Interface
//-------------------------------------------------------------
`ifdef verilator
riscv_trace_sim
u_pipe_dec0_verif
(
     .valid_i(pipe_valid_wb_w)
    ,.pc_i(pipe_pc_wb_w)
    ,.opcode_i(pipe_opc_wb_w)
);

wire [4:0] v_pipe_rs1_w = pipe_opc_wb_w[19:15];
wire [4:0] v_pipe_rs2_w = pipe_opc_wb_w[24:20];

function [0:0] complete_valid0; /*verilator public*/
begin
    complete_valid0 = pipe_valid_wb_w;
end
endfunction
function [31:0] complete_pc0; /*verilator public*/
begin
    complete_pc0 = pipe_pc_wb_w;
end
endfunction
function [31:0] complete_opcode0; /*verilator public*/
begin
    complete_opcode0 = pipe_opc_wb_w;
end
endfunction
function [4:0] complete_ra0; /*verilator public*/
begin
    complete_ra0 = v_pipe_rs1_w;
end
endfunction
function [4:0] complete_rb0; /*verilator public*/
begin
    complete_rb0 = v_pipe_rs2_w;
end
endfunction
function [4:0] complete_rd0; /*verilator public*/
begin
    complete_rd0 = pipe_rd_wb_w;
end
endfunction
function [31:0] complete_ra_val0; /*verilator public*/
begin
    complete_ra_val0 = pipe_ra_val_wb_w;
end
endfunction
function [31:0] complete_rb_val0; /*verilator public*/
begin
    complete_rb_val0 = pipe_rb_val_wb_w;
end
endfunction
function [31:0] complete_rd_val0; /*verilator public*/
begin
    if (|pipe_rd_wb_w)
        complete_rd_val0 = pipe_result_wb_w;
    else
        complete_rd_val0 = 32'b0;
end
endfunction
function [5:0] complete_exception; /*verilator public*/
begin
    complete_exception = pipe_exception_wb_w;
end
endfunction

// RAW-feasibility observer.  These readers expose existing issue, pipeline,
// and LSU-facing values to the bounded directed-test harness only.  They do
// not add state and are compiled only in the Verilator simulation copy.
function [0:0] raw_decode_valid; /*verilator public*/
begin raw_decode_valid = opcode_valid_w; end
endfunction
function [0:0] raw_issue_valid; /*verilator public*/
begin raw_issue_valid = opcode_issue_r; end
endfunction
function [0:0] raw_issue_accept; /*verilator public*/
begin raw_issue_accept = opcode_accept_r; end
endfunction
function [31:0] raw_issue_pc; /*verilator public*/
begin raw_issue_pc = opcode_pc_o; end
endfunction
function [31:0] raw_issue_opcode; /*verilator public*/
begin raw_issue_opcode = opcode_opcode_o; end
endfunction
function [4:0] raw_issue_ra; /*verilator public*/
begin raw_issue_ra = issue_ra_idx_w; end
endfunction
function [4:0] raw_issue_rb; /*verilator public*/
begin raw_issue_rb = issue_rb_idx_w; end
endfunction
function [4:0] raw_issue_rd; /*verilator public*/
begin raw_issue_rd = issue_rd_idx_w; end
endfunction
function [31:0] raw_issue_ra_value; /*verilator public*/
begin raw_issue_ra_value = opcode_ra_operand_o; end
endfunction
function [31:0] raw_issue_rb_value; /*verilator public*/
begin raw_issue_rb_value = opcode_rb_operand_o; end
endfunction
function [0:0] raw_scoreboard_hazard; /*verilator public*/
begin raw_scoreboard_hazard = scoreboard_hazard_r; end
endfunction
function [0:0] raw_stall; /*verilator public*/
begin raw_stall = stall_w; end
endfunction
function [0:0] raw_lsu_stall; /*verilator public*/
begin raw_lsu_stall = lsu_stall_i; end
endfunction
function [0:0] raw_squash; /*verilator public*/
begin raw_squash = squash_w; end
endfunction
function [0:0] raw_pipe_load_e1; /*verilator public*/
begin raw_pipe_load_e1 = pipe_load_e1_w; end
endfunction
function [0:0] raw_pipe_store_e1; /*verilator public*/
begin raw_pipe_store_e1 = pipe_store_e1_w; end
endfunction
function [0:0] raw_pipe_mul_e1; /*verilator public*/
begin raw_pipe_mul_e1 = pipe_mul_e1_w; end
endfunction
function [4:0] raw_pipe_rd_e1; /*verilator public*/
begin raw_pipe_rd_e1 = pipe_rd_e1_w; end
endfunction
function [31:0] raw_pipe_pc_e1; /*verilator public*/
begin raw_pipe_pc_e1 = pipe_pc_e1_w; end
endfunction
function [31:0] raw_pipe_opcode_e1; /*verilator public*/
begin raw_pipe_opcode_e1 = pipe_opcode_e1_w; end
endfunction
function [0:0] raw_pipe_load_e2; /*verilator public*/
begin raw_pipe_load_e2 = pipe_load_e2_w; end
endfunction
function [0:0] raw_pipe_mul_e2; /*verilator public*/
begin raw_pipe_mul_e2 = pipe_mul_e2_w; end
endfunction
function [4:0] raw_pipe_rd_e2; /*verilator public*/
begin raw_pipe_rd_e2 = pipe_rd_e2_w; end
endfunction
function [31:0] raw_pipe_pc_e2; /*verilator public*/
begin raw_pipe_pc_e2 = u_pipe_ctrl.pc_e2_q; end
endfunction
function [31:0] raw_pipe_opcode_e2; /*verilator public*/
begin raw_pipe_opcode_e2 = u_pipe_ctrl.opcode_e2_q; end
endfunction
function [31:0] raw_pipe_result_e2; /*verilator public*/
begin raw_pipe_result_e2 = pipe_result_e2_w; end
endfunction
function [0:0] raw_valid_wb; /*verilator public*/
begin raw_valid_wb = pipe_valid_wb_w; end
endfunction
function [4:0] raw_rd_wb; /*verilator public*/
begin raw_rd_wb = pipe_rd_wb_w; end
endfunction
function [31:0] raw_pc_wb; /*verilator public*/
begin raw_pc_wb = pipe_pc_wb_w; end
endfunction
function [31:0] raw_opcode_wb; /*verilator public*/
begin raw_opcode_wb = pipe_opc_wb_w; end
endfunction
function [31:0] raw_result_wb; /*verilator public*/
begin raw_result_wb = pipe_result_wb_w; end
endfunction
function [0:0] raw_lsu_opcode_valid; /*verilator public*/
begin raw_lsu_opcode_valid = lsu_opcode_valid_o; end
endfunction
function [0:0] early_fast_load_e1_value; /*verilator public*/
begin early_fast_load_e1_value = fast_load_e1_w; end
endfunction
function [0:0] early_fast_load_e2_value; /*verilator public*/
begin early_fast_load_e2_value = fast_load_e2_w; end
endfunction
function [0:0] early_release_value; /*verilator public*/
begin early_release_value = early_release_w; end
endfunction
function [0:0] early_base_ok_value; /*verilator public*/
begin early_base_ok_value = early_base_ok_o; end
endfunction
function [0:0] early_match_ra_value; /*verilator public*/
begin early_match_ra_value = fast_match_ra_w; end
endfunction
function [0:0] early_match_rb_value; /*verilator public*/
begin early_match_rb_value = fast_match_rb_w; end
endfunction
function [31:0] raw_lsu_pc; /*verilator public*/
begin raw_lsu_pc = lsu_opcode_pc_o; end
endfunction
function [31:0] raw_lsu_opcode; /*verilator public*/
begin raw_lsu_opcode = lsu_opcode_opcode_o; end
endfunction
function [4:0] raw_lsu_ra; /*verilator public*/
begin raw_lsu_ra = lsu_opcode_ra_idx_o; end
endfunction
function [4:0] raw_lsu_rb; /*verilator public*/
begin raw_lsu_rb = lsu_opcode_rb_idx_o; end
endfunction
function [31:0] raw_lsu_ra_value; /*verilator public*/
begin raw_lsu_ra_value = lsu_opcode_ra_operand_o; end
endfunction
function [31:0] raw_lsu_rb_value; /*verilator public*/
begin raw_lsu_rb_value = lsu_opcode_rb_operand_o; end
endfunction

// Exact scoreboard-trace classifications used by the early-load observer.
// They are read-only aliases of the existing simulation observer wires; no
// scheduler decision uses them.
function [0:0] early_trace_load_raw; /*verilator public*/
begin early_trace_load_raw = trace_load_raw_w; end
endfunction
function [0:0] early_trace_mul_raw; /*verilator public*/
begin early_trace_mul_raw = trace_mul_raw_w; end
endfunction
function [0:0] early_trace_waw; /*verilator public*/
begin early_trace_waw = trace_waw_w; end
endfunction
function [0:0] early_trace_blanket; /*verilator public*/
begin early_trace_blanket = trace_blanket_w; end
endfunction
function [0:0] early_trace_false_only; /*verilator public*/
begin early_trace_false_only = trace_false_only_w; end
endfunction
function [0:0] early_trace_unused_rs1; /*verilator public*/
begin early_trace_unused_rs1 = trace_unused_rs1_w; end
endfunction
function [0:0] early_trace_unused_rs2; /*verilator public*/
begin early_trace_unused_rs2 = trace_unused_rs2_w; end
endfunction
function [0:0] early_trace_invalid_rd; /*verilator public*/
begin early_trace_invalid_rd = trace_invalid_rd_w; end
endfunction
function [0:0] early_trace_x0_field; /*verilator public*/
begin early_trace_x0_field = trace_x0_field_w; end
endfunction
function [0:0] early_trace_system_or_invalid; /*verilator public*/
begin early_trace_system_or_invalid = trace_system_or_invalid_w; end
endfunction
function [0:0] early_trace_uses_rs1; /*verilator public*/
begin early_trace_uses_rs1 = trace_sem_uses_rs1_w; end
endfunction
function [0:0] early_trace_uses_rs2; /*verilator public*/
begin early_trace_uses_rs2 = trace_sem_uses_rs2_w; end
endfunction
function [0:0] early_trace_writes_rd; /*verilator public*/
begin early_trace_writes_rd = trace_sem_writes_rd_w; end
endfunction
function [0:0] early_trace_scoreboard_stall; /*verilator public*/
begin early_trace_scoreboard_stall = perf_scoreboard_stall_w; end
endfunction
`endif


endmodule
