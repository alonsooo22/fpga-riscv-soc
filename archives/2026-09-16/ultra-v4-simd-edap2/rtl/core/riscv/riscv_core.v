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

module riscv_core #(
    parameter SUPPORT_XBEXTU = 0,
    parameter SUPPORT_XPACK16 = 0,
    parameter SUPPORT_XDOT2H = 0,
    parameter SUPPORT_XADD16 = 0,
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
     parameter SUPPORT_MULDIV   = 1
    ,parameter SUPPORT_SUPER    = 0
    ,parameter SUPPORT_MMU      = 0
    ,parameter SUPPORT_LOAD_BYPASS = 1
    ,parameter SUPPORT_MUL_BYPASS = 1
     ,parameter SUPPORT_REGFILE_XILINX = 0
      ,parameter EXTRA_DECODE_STAGE = 0
     ,parameter SUPPORT_BRANCH_PREDICTION = 0
     ,parameter SUPPORT_EARLY_TCM_LOAD = 0
     ,parameter TCM_MEM_BASE = 32'h00000000
      ,parameter MEM_CACHE_ADDR_MIN = 32'h80000000
    ,parameter MEM_CACHE_ADDR_MAX = 32'h8fffffff
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
     ,input           rst_i
     ,input  [ 31:0]  mem_d_data_rd_i
     ,input           mem_d_accept_i
     ,input           mem_d_early_accept_i
     ,input           mem_d_ack_i
    ,input           mem_d_error_i
    ,input  [ 10:0]  mem_d_resp_tag_i
    ,input           mem_i_accept_i
    ,input           mem_i_valid_i
    ,input           mem_i_error_i
    ,input  [ 31:0]  mem_i_inst_i
    ,input           intr_i
    ,input  [ 31:0]  reset_vector_i
    ,input  [ 31:0]  cpu_id_i

    // Outputs
    ,output [ 31:0]  mem_d_addr_o
     ,output [ 31:0]  mem_d_data_wr_o
     ,output          mem_d_rd_o
     ,output [  3:0]  mem_d_wr_o
     ,output          mem_d_early_valid_o
     ,output [ 31:0]  mem_d_early_addr_o
     ,output [ 31:0]  mem_d_early_data_wr_o
     ,output          mem_d_early_rd_o
     ,output          mem_d_cacheable_o
    ,output [ 10:0]  mem_d_req_tag_o
    ,output          mem_d_invalidate_o
    ,output          mem_d_writeback_o
    ,output          mem_d_flush_o
    ,output          mem_i_rd_o
    ,output          mem_i_flush_o
    ,output          mem_i_invalidate_o
    ,output [ 31:0]  mem_i_pc_o
);

wire           mmu_lsu_writeback_w;
wire  [  1:0]  fetch_in_priv_w;
wire  [  4:0]  mul_opcode_rd_idx_w;
wire           mmu_flush_w;
wire  [ 31:0]  lsu_opcode_pc_w;
wire           fetch_accept_w;
wire  [  4:0]  csr_opcode_rd_idx_w;
wire  [ 31:0]  branch_exec_source_w;
wire  [ 31:0]  csr_opcode_rb_operand_w;
wire  [ 31:0]  writeback_div_value_w;
wire           csr_opcode_valid_w;
wire           branch_csr_request_w;
wire  [ 31:0]  mmu_ifetch_inst_w;
wire  [ 31:0]  opcode_pc_w;
wire  [  4:0]  opcode_rb_idx_w;
wire           mmu_lsu_error_w;
wire           mul_opcode_valid_w;
wire           mmu_mxr_w;
wire  [  1:0]  branch_d_exec_priv_w;
wire           mmu_ifetch_valid_w;
wire           csr_opcode_invalid_w;
wire  [  5:0]  csr_writeback_exception_w;
wire           fetch_instr_mul_w;
wire           branch_exec_is_ret_w;
wire           branch_exec_is_jalr_w;
wire  [ 31:0]  csr_writeback_exception_addr_w;
wire  [  3:0]  mmu_lsu_wr_w;
wire           fetch_in_fault_w;
wire           branch_request_w;
wire  [ 31:0]  csr_opcode_pc_w;
wire           writeback_mem_valid_w;
wire  [  5:0]  csr_result_e1_exception_w;
wire  [ 31:0]  branch_csr_pc_w;
wire  [ 31:0]  mmu_lsu_data_wr_w;
wire           fetch_fault_page_w;
wire  [ 10:0]  mmu_lsu_resp_tag_w;
wire  [ 10:0]  mmu_lsu_req_tag_w;
wire  [ 31:0]  opcode_ra_operand_w;
wire           squash_decode_w;
wire           fetch_dec_fault_page_w;
wire           fetch_dec_pred_taken_w;
wire  [ 31:0]  mul_opcode_opcode_w;
wire           exec_hold_w;
wire           fetch_instr_invalid_w;
wire  [ 31:0]  branch_pc_w;
wire  [  4:0]  mul_opcode_ra_idx_w;
wire  [  4:0]  csr_opcode_rb_idx_w;
wire           lsu_stall_w;
wire           branch_exec_is_not_taken_w;
wire  [ 31:0]  branch_exec_pc_w;
wire  [ 31:0]  opcode_opcode_w;
wire  [ 31:0]  mul_opcode_pc_w;
wire           branch_d_exec_taken_w;
wire  [31:0]   branch_d_exec_target_w;
wire           branch_d_exec_mispredict_w;
wire  [31:0]   branch_d_exec_correction_pc_w;
wire  [ 31:0]  mul_opcode_ra_operand_w;
wire           branch_exec_is_taken_w;
wire           fetch_dec_fault_fetch_w;
wire           fetch_dec_valid_w;
wire           fetch_fault_fetch_w;
wire           lsu_opcode_invalid_w;
wire  [ 31:0]  mmu_lsu_addr_w;
wire           mul_hold_w;
wire           mmu_ifetch_accept_w;
wire           mmu_lsu_ack_w;
wire  [ 31:0]  fetch_pc_w;
wire           mmu_ifetch_invalidate_w;
wire  [ 31:0]  mul_opcode_rb_operand_w;
wire  [  1:0]  branch_csr_priv_w;
wire           branch_exec_request_w;
wire  [ 31:0]  lsu_opcode_ra_operand_w;
wire           div_opcode_valid_w;
wire  [  1:0]  branch_priv_w;
wire           mmu_lsu_rd_w;
wire  [ 31:0]  fetch_dec_pc_w;
wire           interrupt_inhibit_w;
wire           mmu_ifetch_error_w;
wire  [  5:0]  writeback_mem_exception_w;
wire           fetch_instr_lsu_w;
wire  [  1:0]  mmu_priv_d_w;
wire  [  4:0]  opcode_ra_idx_w;
wire  [ 31:0]  csr_opcode_ra_operand_w;
wire  [ 31:0]  writeback_mem_value_w;
wire           writeback_div_valid_w;
wire  [  4:0]  mul_opcode_rb_idx_w;
wire           opcode_invalid_w;
wire           fetch_instr_branch_w;
wire  [ 31:0]  mmu_ifetch_pc_w;
wire           mmu_ifetch_rd_w;
wire           mmu_ifetch_flush_w;
wire  [  4:0]  lsu_opcode_rd_idx_w;
wire  [ 31:0]  lsu_opcode_opcode_w;
wire           mmu_load_fault_w;
wire  [ 31:0]  mmu_satp_w;
wire  [ 31:0]  csr_result_e1_wdata_w;
wire  [ 31:0]  opcode_rb_operand_w;
wire           mmu_lsu_invalidate_w;
wire           fetch_dec_accept_w;
wire  [  4:0]  csr_opcode_ra_idx_w;
wire           ifence_w;
wire           fetch_instr_exec_w;
wire  [  4:0]  opcode_rd_idx_w;
wire  [ 31:0]  csr_writeback_wdata_w;
wire           csr_writeback_write_w;
wire           take_interrupt_w;
wire  [ 31:0]  csr_result_e1_value_w;
wire           fetch_valid_w;
wire  [ 11:0]  csr_writeback_waddr_w;
wire           branch_exec_is_jmp_w;
wire           mmu_lsu_cacheable_w;
wire           fetch_instr_csr_w;
wire           lsu_opcode_valid_w;
wire  [ 31:0]  fetch_dec_instr_w;
wire           csr_result_e1_write_w;
wire  [ 31:0]  csr_opcode_opcode_w;
wire           fetch_instr_div_w;
wire  [ 31:0]  fetch_instr_w;
wire           mul_opcode_invalid_w;
wire           fetch_instr_rd_valid_w;
wire  [ 31:0]  mmu_lsu_data_rd_w;
wire           exec_opcode_valid_w;
wire  [ 31:0]  writeback_mul_value_w;
wire           mmu_lsu_flush_w;
wire  [  4:0]  lsu_opcode_rb_idx_w;
wire           mmu_lsu_accept_w;
wire  [ 31:0]  lsu_opcode_rb_operand_w;
wire           mmu_sum_w;
wire  [ 31:0]  writeback_exec_value_w;
wire  [  4:0]  lsu_opcode_ra_idx_w;
wire  [ 31:0]  csr_writeback_exception_pc_w;
wire           mmu_store_fault_w;
wire           branch_exec_is_call_w;

wire           early_base_ok_w;
wire  [31:0]   early_base_value_w;
wire           early_load_accept_w;
wire           early_result_valid_w;
wire  [31:0]   early_result_value_w;
wire  [ 4:0]   early_result_rd_w;
wire           early_result_consume_w;
wire           early_lsu_valid_w;
wire  [31:0]   early_lsu_addr_w;
wire  [31:0]   early_lsu_data_wr_w;
wire           early_lsu_rd_w;

wire  [31:0]   predictor_pc_w;
wire           predictor_hit_w;
wire           predictor_taken_w;
wire  [31:0]   predictor_target_w;
wire           predictor_update_hit_w;
wire           branch_update_valid_w;
wire  [31:0]   branch_update_pc_w;
wire  [31:0]   branch_update_target_w;
wire           branch_update_is_jal_w;
wire           branch_update_taken_w;
wire           branch_update_pred_taken_w;
wire           branch_update_mispredict_w;
wire           branch_resolved_valid_w;
wire           branch_resolved_conditional_w;
wire           branch_resolved_is_jal_w;
wire           branch_resolved_is_jalr_w;
wire           branch_resolved_pred_taken_w;
wire           branch_resolved_mispredict_w;
wire           fetch_pred_taken_w;
wire           opcode_pred_taken_w;

`ifdef ULTRA_PERF_COUNTERS
wire           retire_valid_w;
wire  [31:0]   retire_count_w;
wire           perf_scoreboard_stall_w;
wire           perf_pipe_stall_w;
wire           perf_div_wait_w;
wire           perf_csr_wait_w;
wire           perf_branch_redirect_w;
wire           perf_branch_flush_w;
wire           perf_fetch_starve_w;

reg   [31:0]   perf_scoreboard_q;
reg   [31:0]   perf_lsu_q;
reg   [31:0]   perf_pipe_q;
reg   [31:0]   perf_div_q;
reg   [31:0]   perf_csr_q;
reg   [31:0]   perf_branch_request_q;
reg   [31:0]   perf_branch_redirect_q;
reg   [31:0]   perf_branch_flush_q;
reg   [31:0]   perf_fetch_starve_q;
reg   [31:0]   perf_branch_resolved_q;
reg   [31:0]   perf_branch_conditional_q;
reg   [31:0]   perf_branch_jal_q;
reg   [31:0]   perf_branch_jalr_q;
reg   [31:0]   perf_branch_btb_hit_q;
reg   [31:0]   perf_branch_btb_miss_q;
reg   [31:0]   perf_branch_pred_taken_q;
reg   [31:0]   perf_branch_correct_q;
reg   [31:0]   perf_branch_mispredict_q;
`endif


riscv_exec
#(
    .SUPPORT_XBEXTU(SUPPORT_XBEXTU),
    .SUPPORT_XPACK16(SUPPORT_XPACK16),
    .SUPPORT_XDOT2H(SUPPORT_XDOT2H),
    .SUPPORT_XADD16(SUPPORT_XADD16)
)
u_exec
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(exec_opcode_valid_w)
    ,.opcode_opcode_i(opcode_opcode_w)
    ,.opcode_pc_i(opcode_pc_w)
    ,.opcode_pred_taken_i(opcode_pred_taken_w)
    ,.opcode_invalid_i(opcode_invalid_w)
    ,.opcode_rd_idx_i(opcode_rd_idx_w)
    ,.opcode_ra_idx_i(opcode_ra_idx_w)
    ,.opcode_rb_idx_i(opcode_rb_idx_w)
    ,.opcode_ra_operand_i(opcode_ra_operand_w)
    ,.opcode_rb_operand_i(opcode_rb_operand_w)
    ,.hold_i(exec_hold_w)
    ,.take_interrupt_i(take_interrupt_w)

    // Outputs
    ,.branch_request_o(branch_exec_request_w)
    ,.branch_is_taken_o(branch_exec_is_taken_w)
    ,.branch_is_not_taken_o(branch_exec_is_not_taken_w)
    ,.branch_source_o(branch_exec_source_w)
    ,.branch_is_call_o(branch_exec_is_call_w)
    ,.branch_is_ret_o(branch_exec_is_ret_w)
    ,.branch_is_jmp_o(branch_exec_is_jmp_w)
    ,.branch_is_jalr_o(branch_exec_is_jalr_w)
    ,.branch_pc_o(branch_exec_pc_w)
    ,.branch_d_exec_taken_o(branch_d_exec_taken_w)
    ,.branch_d_exec_target_o(branch_d_exec_target_w)
    ,.branch_d_exec_mispredict_o(branch_d_exec_mispredict_w)
    ,.branch_d_exec_correction_pc_o(branch_d_exec_correction_pc_w)
    ,.branch_d_priv_o(branch_d_exec_priv_w)
    ,.branch_update_valid_o(branch_update_valid_w)
    ,.branch_update_pc_o(branch_update_pc_w)
    ,.branch_update_target_o(branch_update_target_w)
    ,.branch_update_is_jal_o(branch_update_is_jal_w)
    ,.branch_update_taken_o(branch_update_taken_w)
    ,.branch_update_pred_taken_o(branch_update_pred_taken_w)
    ,.branch_update_mispredict_o(branch_update_mispredict_w)
    ,.branch_resolved_valid_o(branch_resolved_valid_w)
    ,.branch_resolved_conditional_o(branch_resolved_conditional_w)
    ,.branch_resolved_is_jal_o(branch_resolved_is_jal_w)
    ,.branch_resolved_is_jalr_o(branch_resolved_is_jalr_w)
    ,.branch_resolved_pred_taken_o(branch_resolved_pred_taken_w)
    ,.branch_resolved_mispredict_o(branch_resolved_mispredict_w)
    ,.writeback_value_o(writeback_exec_value_w)
);


riscv_decode
#(
    .SUPPORT_XBEXTU(SUPPORT_XBEXTU),
    .SUPPORT_XPACK16(SUPPORT_XPACK16),
    .SUPPORT_XDOT2H(SUPPORT_XDOT2H),
    .SUPPORT_XADD16(SUPPORT_XADD16),
     .EXTRA_DECODE_STAGE(EXTRA_DECODE_STAGE)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
)
u_decode
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.fetch_in_valid_i(fetch_dec_valid_w)
    ,.fetch_in_instr_i(fetch_dec_instr_w)
    ,.fetch_in_pc_i(fetch_dec_pc_w)
    ,.fetch_in_pred_taken_i(fetch_dec_pred_taken_w)
    ,.fetch_in_fault_fetch_i(fetch_dec_fault_fetch_w)
    ,.fetch_in_fault_page_i(fetch_dec_fault_page_w)
    ,.fetch_out_accept_i(fetch_accept_w)
    ,.squash_decode_i(squash_decode_w)

    // Outputs
    ,.fetch_in_accept_o(fetch_dec_accept_w)
    ,.fetch_out_valid_o(fetch_valid_w)
    ,.fetch_out_instr_o(fetch_instr_w)
    ,.fetch_out_pc_o(fetch_pc_w)
    ,.fetch_out_pred_taken_o(fetch_pred_taken_w)
    ,.fetch_out_fault_fetch_o(fetch_fault_fetch_w)
    ,.fetch_out_fault_page_o(fetch_fault_page_w)
    ,.fetch_out_instr_exec_o(fetch_instr_exec_w)
    ,.fetch_out_instr_lsu_o(fetch_instr_lsu_w)
    ,.fetch_out_instr_branch_o(fetch_instr_branch_w)
    ,.fetch_out_instr_mul_o(fetch_instr_mul_w)
    ,.fetch_out_instr_div_o(fetch_instr_div_w)
    ,.fetch_out_instr_csr_o(fetch_instr_csr_w)
    ,.fetch_out_instr_rd_valid_o(fetch_instr_rd_valid_w)
    ,.fetch_out_instr_invalid_o(fetch_instr_invalid_w)
);


riscv_mmu
#(
     .MEM_CACHE_ADDR_MAX(MEM_CACHE_ADDR_MAX)
    ,.SUPPORT_MMU(SUPPORT_MMU)
    ,.MEM_CACHE_ADDR_MIN(MEM_CACHE_ADDR_MIN)
)
u_mmu
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.priv_d_i(mmu_priv_d_w)
    ,.sum_i(mmu_sum_w)
    ,.mxr_i(mmu_mxr_w)
    ,.flush_i(mmu_flush_w)
    ,.satp_i(mmu_satp_w)
    ,.fetch_in_rd_i(mmu_ifetch_rd_w)
    ,.fetch_in_flush_i(mmu_ifetch_flush_w)
    ,.fetch_in_invalidate_i(mmu_ifetch_invalidate_w)
    ,.fetch_in_pc_i(mmu_ifetch_pc_w)
    ,.fetch_in_priv_i(fetch_in_priv_w)
    ,.fetch_out_accept_i(mem_i_accept_i)
    ,.fetch_out_valid_i(mem_i_valid_i)
    ,.fetch_out_error_i(mem_i_error_i)
    ,.fetch_out_inst_i(mem_i_inst_i)
    ,.lsu_in_addr_i(mmu_lsu_addr_w)
    ,.lsu_in_data_wr_i(mmu_lsu_data_wr_w)
    ,.lsu_in_rd_i(mmu_lsu_rd_w)
    ,.lsu_in_wr_i(mmu_lsu_wr_w)
    ,.lsu_in_cacheable_i(mmu_lsu_cacheable_w)
    ,.lsu_in_req_tag_i(mmu_lsu_req_tag_w)
    ,.lsu_in_invalidate_i(mmu_lsu_invalidate_w)
    ,.lsu_in_writeback_i(mmu_lsu_writeback_w)
    ,.lsu_in_flush_i(mmu_lsu_flush_w)
    ,.lsu_out_data_rd_i(mem_d_data_rd_i)
    ,.lsu_out_accept_i(mem_d_accept_i)
    ,.lsu_out_ack_i(mem_d_ack_i)
    ,.lsu_out_error_i(mem_d_error_i)
    ,.lsu_out_resp_tag_i(mem_d_resp_tag_i)

    // Outputs
    ,.fetch_in_accept_o(mmu_ifetch_accept_w)
    ,.fetch_in_valid_o(mmu_ifetch_valid_w)
    ,.fetch_in_error_o(mmu_ifetch_error_w)
    ,.fetch_in_inst_o(mmu_ifetch_inst_w)
    ,.fetch_out_rd_o(mem_i_rd_o)
    ,.fetch_out_flush_o(mem_i_flush_o)
    ,.fetch_out_invalidate_o(mem_i_invalidate_o)
    ,.fetch_out_pc_o(mem_i_pc_o)
    ,.fetch_in_fault_o(fetch_in_fault_w)
    ,.lsu_in_data_rd_o(mmu_lsu_data_rd_w)
    ,.lsu_in_accept_o(mmu_lsu_accept_w)
    ,.lsu_in_ack_o(mmu_lsu_ack_w)
    ,.lsu_in_error_o(mmu_lsu_error_w)
    ,.lsu_in_resp_tag_o(mmu_lsu_resp_tag_w)
    ,.lsu_out_addr_o(mem_d_addr_o)
    ,.lsu_out_data_wr_o(mem_d_data_wr_o)
    ,.lsu_out_rd_o(mem_d_rd_o)
    ,.lsu_out_wr_o(mem_d_wr_o)
    ,.lsu_out_cacheable_o(mem_d_cacheable_o)
    ,.lsu_out_req_tag_o(mem_d_req_tag_o)
    ,.lsu_out_invalidate_o(mem_d_invalidate_o)
    ,.lsu_out_writeback_o(mem_d_writeback_o)
    ,.lsu_out_flush_o(mem_d_flush_o)
    ,.lsu_in_load_fault_o(mmu_load_fault_w)
    ,.lsu_in_store_fault_o(mmu_store_fault_w)
);


riscv_lsu
#(
     .MEM_CACHE_ADDR_MAX(MEM_CACHE_ADDR_MAX)
    ,.MEM_CACHE_ADDR_MIN(MEM_CACHE_ADDR_MIN)
    ,.SUPPORT_EARLY_TCM_LOAD(SUPPORT_EARLY_TCM_LOAD)
    ,.TCM_MEM_BASE(TCM_MEM_BASE)
)
u_lsu
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(lsu_opcode_valid_w)
    ,.opcode_opcode_i(lsu_opcode_opcode_w)
    ,.opcode_pc_i(lsu_opcode_pc_w)
    ,.opcode_invalid_i(lsu_opcode_invalid_w)
    ,.opcode_rd_idx_i(lsu_opcode_rd_idx_w)
    ,.opcode_ra_idx_i(lsu_opcode_ra_idx_w)
    ,.opcode_rb_idx_i(lsu_opcode_rb_idx_w)
    ,.opcode_ra_operand_i(lsu_opcode_ra_operand_w)
    ,.opcode_rb_operand_i(lsu_opcode_rb_operand_w)
     ,.mem_data_rd_i(mmu_lsu_data_rd_w)
     ,.mem_accept_i(mmu_lsu_accept_w)
     ,.early_accept_i(mem_d_early_accept_i)
     ,.mem_ack_i(mmu_lsu_ack_w)
    ,.mem_error_i(mmu_lsu_error_w)
    ,.mem_resp_tag_i(mmu_lsu_resp_tag_w)
     ,.mem_load_fault_i(mmu_load_fault_w)
     ,.mem_store_fault_i(mmu_store_fault_w)
     ,.early_base_ok_i(early_base_ok_w)
     ,.early_base_i(early_base_value_w)
     ,.early_result_consume_i(early_result_consume_w)

    // Outputs
    ,.mem_addr_o(mmu_lsu_addr_w)
    ,.mem_data_wr_o(mmu_lsu_data_wr_w)
    ,.mem_rd_o(mmu_lsu_rd_w)
    ,.mem_wr_o(mmu_lsu_wr_w)
    ,.mem_cacheable_o(mmu_lsu_cacheable_w)
    ,.mem_req_tag_o(mmu_lsu_req_tag_w)
    ,.mem_invalidate_o(mmu_lsu_invalidate_w)
    ,.mem_writeback_o(mmu_lsu_writeback_w)
    ,.mem_flush_o(mmu_lsu_flush_w)
    ,.writeback_valid_o(writeback_mem_valid_w)
    ,.writeback_value_o(writeback_mem_value_w)
     ,.writeback_exception_o(writeback_mem_exception_w)
     ,.stall_o(lsu_stall_w)
     ,.early_load_accept_o(early_load_accept_w)
     ,.early_request_o(early_lsu_valid_w)
     ,.early_addr_o(early_lsu_addr_w)
     ,.early_data_wr_o(early_lsu_data_wr_w)
     ,.early_rd_o(early_lsu_rd_w)
     ,.early_result_valid_o(early_result_valid_w)
     ,.early_result_value_o(early_result_value_w)
     ,.early_result_rd_o(early_result_rd_w)
 );

// E-TCM v3 is a physical no-MMU sideband.  It carries only an aligned TCM LW;
// normal LSU controls remain on the registered MMU path.
assign mem_d_early_valid_o   = (SUPPORT_MMU == 0) ? early_lsu_valid_w : 1'b0;
assign mem_d_early_addr_o    = early_lsu_addr_w;
assign mem_d_early_data_wr_o = early_lsu_data_wr_w;
assign mem_d_early_rd_o      = (SUPPORT_MMU == 0) ? early_lsu_rd_w : 1'b0;

`ifdef verilator
// The physical sideband handshake is checked at the core boundary so a test
// cannot pass by observing only an LSU launch.  These checks disappear from
// synthesis and are active only in the Verilator candidate builds.
always @ (posedge clk_i)
if (!rst_i && (SUPPORT_MMU == 0))
begin
    if (mem_d_early_accept_i && !mem_d_early_valid_o)
        $fatal(1, "E-TCM v3 physical accept without early offer");

    if (mem_d_early_accept_i !== early_load_accept_w)
        $fatal(1, "E-TCM v3 physical accept/LSU registration mismatch");

    if (mem_d_early_accept_i &&
        (mem_d_rd_o || (|mem_d_wr_o) || mem_d_invalidate_o ||
         mem_d_writeback_o || mem_d_flush_o))
        $fatal(1, "E-TCM v3 early and normal ownership overlap");

    if (u_lsu.early_response_w && u_lsu.normal_fifo_pop_w)
        $fatal(1, "E-TCM v3 early response entered normal FIFO");

    if (mem_d_ack_i && !u_lsu.early_live_q && !u_lsu.normal_fifo_valid_w)
        $fatal(1, "E-TCM v3 normal response has no normal FIFO owner");
end
`endif


riscv_csr
#(
     .SUPPORT_SUPER(SUPPORT_SUPER)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
)
u_csr
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.intr_i(intr_i)
    ,.opcode_valid_i(csr_opcode_valid_w)
    ,.opcode_opcode_i(csr_opcode_opcode_w)
    ,.opcode_pc_i(csr_opcode_pc_w)
    ,.opcode_invalid_i(csr_opcode_invalid_w)
    ,.opcode_rd_idx_i(csr_opcode_rd_idx_w)
    ,.opcode_ra_idx_i(csr_opcode_ra_idx_w)
    ,.opcode_rb_idx_i(csr_opcode_rb_idx_w)
    ,.opcode_ra_operand_i(csr_opcode_ra_operand_w)
    ,.opcode_rb_operand_i(csr_opcode_rb_operand_w)
    ,.csr_writeback_write_i(csr_writeback_write_w)
    ,.csr_writeback_waddr_i(csr_writeback_waddr_w)
    ,.csr_writeback_wdata_i(csr_writeback_wdata_w)
    ,.csr_writeback_exception_i(csr_writeback_exception_w)
    ,.csr_writeback_exception_pc_i(csr_writeback_exception_pc_w)
    ,.csr_writeback_exception_addr_i(csr_writeback_exception_addr_w)
    ,.cpu_id_i(cpu_id_i)
    ,.reset_vector_i(reset_vector_i)
    ,.interrupt_inhibit_i(interrupt_inhibit_w)
`ifdef ULTRA_PERF_COUNTERS
    ,.retire_count_i(retire_count_w)
    ,.perf_scoreboard_i(perf_scoreboard_q)
    ,.perf_lsu_i(perf_lsu_q)
    ,.perf_pipe_i(perf_pipe_q)
    ,.perf_div_i(perf_div_q)
    ,.perf_csr_i(perf_csr_q)
    ,.perf_branch_request_i(perf_branch_request_q)
    ,.perf_branch_redirect_i(perf_branch_redirect_q)
    ,.perf_branch_flush_i(perf_branch_flush_q)
    ,.perf_fetch_starve_i(perf_fetch_starve_q)
`endif

    // Outputs
    ,.csr_result_e1_value_o(csr_result_e1_value_w)
    ,.csr_result_e1_write_o(csr_result_e1_write_w)
    ,.csr_result_e1_wdata_o(csr_result_e1_wdata_w)
    ,.csr_result_e1_exception_o(csr_result_e1_exception_w)
    ,.branch_csr_request_o(branch_csr_request_w)
    ,.branch_csr_pc_o(branch_csr_pc_w)
    ,.branch_csr_priv_o(branch_csr_priv_w)
    ,.take_interrupt_o(take_interrupt_w)
    ,.ifence_o(ifence_w)
    ,.mmu_priv_d_o(mmu_priv_d_w)
    ,.mmu_sum_o(mmu_sum_w)
    ,.mmu_mxr_o(mmu_mxr_w)
    ,.mmu_flush_o(mmu_flush_w)
    ,.mmu_satp_o(mmu_satp_w)
);


riscv_multiplier
#(
    .SUPPORT_XBEXTU(SUPPORT_XBEXTU),
    .SUPPORT_XPACK16(SUPPORT_XPACK16),
    .SUPPORT_XDOT2H(SUPPORT_XDOT2H),
    .SUPPORT_XADD16(SUPPORT_XADD16)
)
u_mul
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(mul_opcode_valid_w)
    ,.opcode_opcode_i(mul_opcode_opcode_w)
    ,.opcode_pc_i(mul_opcode_pc_w)
    ,.opcode_invalid_i(mul_opcode_invalid_w)
    ,.opcode_rd_idx_i(mul_opcode_rd_idx_w)
    ,.opcode_ra_idx_i(mul_opcode_ra_idx_w)
    ,.opcode_rb_idx_i(mul_opcode_rb_idx_w)
    ,.opcode_ra_operand_i(mul_opcode_ra_operand_w)
    ,.opcode_rb_operand_i(mul_opcode_rb_operand_w)
    ,.hold_i(mul_hold_w)

    // Outputs
    ,.writeback_value_o(writeback_mul_value_w)
);


riscv_divider
u_div
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(div_opcode_valid_w)
    ,.opcode_opcode_i(opcode_opcode_w)
    ,.opcode_pc_i(opcode_pc_w)
    ,.opcode_invalid_i(opcode_invalid_w)
    ,.opcode_rd_idx_i(opcode_rd_idx_w)
    ,.opcode_ra_idx_i(opcode_ra_idx_w)
    ,.opcode_rb_idx_i(opcode_rb_idx_w)
    ,.opcode_ra_operand_i(opcode_ra_operand_w)
    ,.opcode_rb_operand_i(opcode_rb_operand_w)

    // Outputs
    ,.writeback_valid_o(writeback_div_valid_w)
    ,.writeback_value_o(writeback_div_value_w)
);


riscv_issue
#(
    .SUPPORT_XBEXTU(SUPPORT_XBEXTU),
    .SUPPORT_XPACK16(SUPPORT_XPACK16),
    .SUPPORT_XDOT2H(SUPPORT_XDOT2H),
    .SUPPORT_XADD16(SUPPORT_XADD16),
     .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX)
    ,.SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
    ,.SUPPORT_DUAL_ISSUE(1)
    ,.SUPPORT_EARLY_TCM_LOAD(SUPPORT_EARLY_TCM_LOAD)
)
u_issue
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.fetch_valid_i(fetch_valid_w)
    ,.fetch_instr_i(fetch_instr_w)
    ,.fetch_pc_i(fetch_pc_w)
    ,.fetch_pred_taken_i(fetch_pred_taken_w)
    ,.fetch_fault_fetch_i(fetch_fault_fetch_w)
    ,.fetch_fault_page_i(fetch_fault_page_w)
    ,.fetch_instr_exec_i(fetch_instr_exec_w)
    ,.fetch_instr_lsu_i(fetch_instr_lsu_w)
    ,.fetch_instr_branch_i(fetch_instr_branch_w)
    ,.fetch_instr_mul_i(fetch_instr_mul_w)
    ,.fetch_instr_div_i(fetch_instr_div_w)
    ,.fetch_instr_csr_i(fetch_instr_csr_w)
    ,.fetch_instr_rd_valid_i(fetch_instr_rd_valid_w)
    ,.fetch_instr_invalid_i(fetch_instr_invalid_w)
    ,.branch_exec_request_i(branch_exec_request_w)
    ,.branch_exec_is_taken_i(branch_exec_is_taken_w)
    ,.branch_exec_is_not_taken_i(branch_exec_is_not_taken_w)
    ,.branch_exec_source_i(branch_exec_source_w)
    ,.branch_exec_is_call_i(branch_exec_is_call_w)
    ,.branch_exec_is_ret_i(branch_exec_is_ret_w)
    ,.branch_exec_is_jmp_i(branch_exec_is_jmp_w)
    ,.branch_exec_pc_i(branch_exec_pc_w)
    ,.branch_d_exec_taken_i(branch_d_exec_taken_w)
    ,.branch_d_exec_target_i(branch_d_exec_target_w)
    ,.branch_d_exec_mispredict_i(branch_d_exec_mispredict_w)
    ,.branch_d_exec_correction_pc_i(branch_d_exec_correction_pc_w)
    ,.branch_d_exec_priv_i(branch_d_exec_priv_w)
    ,.branch_csr_request_i(branch_csr_request_w)
    ,.branch_csr_pc_i(branch_csr_pc_w)
    ,.branch_csr_priv_i(branch_csr_priv_w)
    ,.writeback_exec_value_i(writeback_exec_value_w)
    ,.writeback_mem_valid_i(writeback_mem_valid_w)
    ,.writeback_mem_value_i(writeback_mem_value_w)
    ,.writeback_mem_exception_i(writeback_mem_exception_w)
    ,.writeback_mul_value_i(writeback_mul_value_w)
    ,.writeback_div_valid_i(writeback_div_valid_w)
    ,.writeback_div_value_i(writeback_div_value_w)
    ,.csr_result_e1_value_i(csr_result_e1_value_w)
    ,.csr_result_e1_write_i(csr_result_e1_write_w)
    ,.csr_result_e1_wdata_i(csr_result_e1_wdata_w)
    ,.csr_result_e1_exception_i(csr_result_e1_exception_w)
     ,.lsu_stall_i(lsu_stall_w)
     ,.take_interrupt_i(take_interrupt_w)
     ,.early_load_accept_i(early_load_accept_w)
     ,.early_result_valid_i(early_result_valid_w)
     ,.early_result_value_i(early_result_value_w)
     ,.early_result_rd_i(early_result_rd_w)

    // Outputs
    ,.fetch_accept_o(fetch_accept_w)
    ,.branch_request_o(branch_request_w)
    ,.branch_pc_o(branch_pc_w)
    ,.branch_priv_o(branch_priv_w)
    ,.exec_opcode_valid_o(exec_opcode_valid_w)
    ,.lsu_opcode_valid_o(lsu_opcode_valid_w)
    ,.csr_opcode_valid_o(csr_opcode_valid_w)
    ,.mul_opcode_valid_o(mul_opcode_valid_w)
    ,.div_opcode_valid_o(div_opcode_valid_w)
    ,.opcode_opcode_o(opcode_opcode_w)
    ,.opcode_pc_o(opcode_pc_w)
    ,.opcode_pred_taken_o(opcode_pred_taken_w)
    ,.opcode_invalid_o(opcode_invalid_w)
    ,.opcode_rd_idx_o(opcode_rd_idx_w)
    ,.opcode_ra_idx_o(opcode_ra_idx_w)
    ,.opcode_rb_idx_o(opcode_rb_idx_w)
    ,.opcode_ra_operand_o(opcode_ra_operand_w)
    ,.opcode_rb_operand_o(opcode_rb_operand_w)
    ,.lsu_opcode_opcode_o(lsu_opcode_opcode_w)
    ,.lsu_opcode_pc_o(lsu_opcode_pc_w)
    ,.lsu_opcode_invalid_o(lsu_opcode_invalid_w)
    ,.lsu_opcode_rd_idx_o(lsu_opcode_rd_idx_w)
    ,.lsu_opcode_ra_idx_o(lsu_opcode_ra_idx_w)
    ,.lsu_opcode_rb_idx_o(lsu_opcode_rb_idx_w)
    ,.lsu_opcode_ra_operand_o(lsu_opcode_ra_operand_w)
    ,.lsu_opcode_rb_operand_o(lsu_opcode_rb_operand_w)
    ,.mul_opcode_opcode_o(mul_opcode_opcode_w)
    ,.mul_opcode_pc_o(mul_opcode_pc_w)
    ,.mul_opcode_invalid_o(mul_opcode_invalid_w)
    ,.mul_opcode_rd_idx_o(mul_opcode_rd_idx_w)
    ,.mul_opcode_ra_idx_o(mul_opcode_ra_idx_w)
    ,.mul_opcode_rb_idx_o(mul_opcode_rb_idx_w)
    ,.mul_opcode_ra_operand_o(mul_opcode_ra_operand_w)
    ,.mul_opcode_rb_operand_o(mul_opcode_rb_operand_w)
    ,.csr_opcode_opcode_o(csr_opcode_opcode_w)
    ,.csr_opcode_pc_o(csr_opcode_pc_w)
    ,.csr_opcode_invalid_o(csr_opcode_invalid_w)
    ,.csr_opcode_rd_idx_o(csr_opcode_rd_idx_w)
    ,.csr_opcode_ra_idx_o(csr_opcode_ra_idx_w)
    ,.csr_opcode_rb_idx_o(csr_opcode_rb_idx_w)
    ,.csr_opcode_ra_operand_o(csr_opcode_ra_operand_w)
    ,.csr_opcode_rb_operand_o(csr_opcode_rb_operand_w)
    ,.csr_writeback_write_o(csr_writeback_write_w)
    ,.csr_writeback_waddr_o(csr_writeback_waddr_w)
    ,.csr_writeback_wdata_o(csr_writeback_wdata_w)
    ,.csr_writeback_exception_o(csr_writeback_exception_w)
    ,.csr_writeback_exception_pc_o(csr_writeback_exception_pc_w)
    ,.csr_writeback_exception_addr_o(csr_writeback_exception_addr_w)
    ,.exec_hold_o(exec_hold_w)
    ,.mul_hold_o(mul_hold_w)
     ,.interrupt_inhibit_o(interrupt_inhibit_w)
     ,.early_base_ok_o(early_base_ok_w)
     ,.early_base_value_o(early_base_value_w)
     ,.early_result_consume_o(early_result_consume_w)
`ifdef ULTRA_PERF_COUNTERS
    ,.retire_valid_o(retire_valid_w)
    ,.retire_count_o(retire_count_w)
    ,.perf_scoreboard_stall_o(perf_scoreboard_stall_w)
    ,.perf_pipe_stall_o(perf_pipe_stall_w)
    ,.perf_div_wait_o(perf_div_wait_w)
    ,.perf_csr_wait_o(perf_csr_wait_w)
`endif
);


riscv_branch_predict
#(
     .SUPPORT_BRANCH_PREDICTION(SUPPORT_BRANCH_PREDICTION)
)
u_branch_predict
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.invalidate_i(ifence_w)
    ,.lookup_pc_i(predictor_pc_w)
    ,.lookup_hit_o(predictor_hit_w)
    ,.lookup_taken_o(predictor_taken_w)
    ,.lookup_target_o(predictor_target_w)
    ,.update_valid_i(branch_update_valid_w)
    ,.update_pc_i(branch_update_pc_w)
    ,.update_target_i(branch_update_target_w)
    ,.update_is_jal_i(branch_update_is_jal_w)
    ,.update_taken_i(branch_update_taken_w)
    ,.update_hit_o(predictor_update_hit_w)
);

// The short-tag window contract is checked at the real fetch/MMU acceptance
// boundary.  predictor_pc_w is allowed to carry stale or speculative values
// while the fetch request is not valid; inspecting it unconditionally would
// turn those values into false positives.  This block is simulation-only and
// is not present in synthesis.
`ifdef ULTRA_BTB_SHORT_TAG
`ifdef ULTRA_BTB_SHORT_TAG_WINDOW_CHECK
`ifdef verilator
always @ (posedge clk_i)
if (!rst_i && mmu_ifetch_rd_w && mmu_ifetch_accept_w)
begin
    if (mmu_ifetch_pc_w[31:16] != 16'h0000 ||
        predictor_pc_w[31:16] != 16'h0000)
        $fatal(1, "SHORT_TAG_WINDOW_VIOLATION fetch_pc=0x%08x predictor_pc=0x%08x",
               mmu_ifetch_pc_w, predictor_pc_w);
end
`endif
`endif
`endif


riscv_fetch
#(
     .SUPPORT_MMU(SUPPORT_MMU)
    ,.SUPPORT_BRANCH_PREDICTION(SUPPORT_BRANCH_PREDICTION)
)
u_fetch
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.fetch_accept_i(fetch_dec_accept_w)
    ,.icache_accept_i(mmu_ifetch_accept_w)
    ,.icache_valid_i(mmu_ifetch_valid_w)
    ,.icache_error_i(mmu_ifetch_error_w)
    ,.icache_inst_i(mmu_ifetch_inst_w)
    ,.icache_page_fault_i(fetch_in_fault_w)
    ,.fetch_invalidate_i(ifence_w)
    ,.branch_request_i(branch_request_w)
    ,.branch_pc_i(branch_pc_w)
    ,.branch_priv_i(branch_priv_w)
    ,.prediction_taken_i(predictor_taken_w)
    ,.prediction_target_i(predictor_target_w)

    // Outputs
    ,.fetch_valid_o(fetch_dec_valid_w)
    ,.fetch_instr_o(fetch_dec_instr_w)
    ,.fetch_pc_o(fetch_dec_pc_w)
    ,.fetch_pred_taken_o(fetch_dec_pred_taken_w)
    ,.fetch_fault_fetch_o(fetch_dec_fault_fetch_w)
    ,.fetch_fault_page_o(fetch_dec_fault_page_w)
    ,.icache_rd_o(mmu_ifetch_rd_w)
    ,.icache_flush_o(mmu_ifetch_flush_w)
    ,.icache_invalidate_o(mmu_ifetch_invalidate_w)
    ,.icache_pc_o(mmu_ifetch_pc_w)
    ,.icache_priv_o(fetch_in_priv_w)
    ,.prediction_pc_o(predictor_pc_w)
    ,.squash_decode_o(squash_decode_w)
`ifdef ULTRA_PERF_COUNTERS
    ,.perf_branch_redirect_o(perf_branch_redirect_w)
    ,.perf_branch_flush_o(perf_branch_flush_w)
    ,.perf_fetch_starve_o(perf_fetch_starve_w)
`endif
);

`ifdef ULTRA_PERF_COUNTERS
// Performance-only cycle counters. These are deliberately observers: every
// condition is sampled at the existing pipeline boundary and no control path
// uses the counters.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    perf_scoreboard_q       <= 32'b0;
    perf_lsu_q              <= 32'b0;
    perf_pipe_q             <= 32'b0;
    perf_div_q              <= 32'b0;
    perf_csr_q              <= 32'b0;
    perf_branch_request_q   <= 32'b0;
    perf_branch_redirect_q  <= 32'b0;
    perf_branch_flush_q     <= 32'b0;
    perf_fetch_starve_q     <= 32'b0;
    perf_branch_resolved_q    <= 32'b0;
    perf_branch_conditional_q <= 32'b0;
    perf_branch_jal_q         <= 32'b0;
    perf_branch_jalr_q        <= 32'b0;
    perf_branch_btb_hit_q     <= 32'b0;
    perf_branch_btb_miss_q    <= 32'b0;
    perf_branch_pred_taken_q  <= 32'b0;
    perf_branch_correct_q     <= 32'b0;
    perf_branch_mispredict_q  <= 32'b0;
end
else
begin
    if (perf_scoreboard_stall_w)
        perf_scoreboard_q      <= perf_scoreboard_q + 32'd1;
    if (lsu_stall_w)
        perf_lsu_q             <= perf_lsu_q + 32'd1;
    if (perf_pipe_stall_w)
        perf_pipe_q            <= perf_pipe_q + 32'd1;
    if (perf_div_wait_w)
        perf_div_q             <= perf_div_q + 32'd1;
    if (perf_csr_wait_w)
        perf_csr_q             <= perf_csr_q + 32'd1;
    if (branch_d_exec_mispredict_w)
        perf_branch_request_q  <= perf_branch_request_q + 32'd1;
    if (perf_branch_redirect_w)
        perf_branch_redirect_q <= perf_branch_redirect_q + 32'd1;
    if (perf_branch_flush_w)
        perf_branch_flush_q    <= perf_branch_flush_q + 32'd1;
    if (perf_fetch_starve_w)
        perf_fetch_starve_q    <= perf_fetch_starve_q + 32'd1;
    if (branch_resolved_valid_w)
        perf_branch_resolved_q <= perf_branch_resolved_q + 32'd1;
    if (branch_resolved_conditional_w)
        perf_branch_conditional_q <= perf_branch_conditional_q + 32'd1;
    if (branch_resolved_is_jal_w)
        perf_branch_jal_q <= perf_branch_jal_q + 32'd1;
    if (branch_resolved_is_jalr_w)
        perf_branch_jalr_q <= perf_branch_jalr_q + 32'd1;
    if (branch_update_valid_w)
    begin
        if (predictor_update_hit_w)
            perf_branch_btb_hit_q <= perf_branch_btb_hit_q + 32'd1;
        else
            perf_branch_btb_miss_q <= perf_branch_btb_miss_q + 32'd1;
        if (branch_update_pred_taken_w)
            perf_branch_pred_taken_q <= perf_branch_pred_taken_q + 32'd1;
        if (branch_update_mispredict_w)
            perf_branch_mispredict_q <= perf_branch_mispredict_q + 32'd1;
        else
            perf_branch_correct_q <= perf_branch_correct_q + 32'd1;
    end
end
`endif

// Simulation-only readers for the branch statistics. The counters themselves
// are compiled only with ULTRA_PERF_COUNTERS, so normal RTL synthesis has no
// added state or control logic. Keep the public zero-argument functions under
// the same Verilator-only guard used by the existing completion hooks; Vivado
// requires every synthesizable function to have at least one input.
`ifdef verilator
function [31:0] branch_resolved_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_resolved_count = perf_branch_resolved_q;
`else
    branch_resolved_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_conditional_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_conditional_count = perf_branch_conditional_q;
`else
    branch_conditional_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_jal_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_jal_count = perf_branch_jal_q;
`else
    branch_jal_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_jalr_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_jalr_count = perf_branch_jalr_q;
`else
    branch_jalr_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_btb_hit_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_btb_hit_count = perf_branch_btb_hit_q;
`else
    branch_btb_hit_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_btb_miss_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_btb_miss_count = perf_branch_btb_miss_q;
`else
    branch_btb_miss_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_pred_taken_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_pred_taken_count = perf_branch_pred_taken_q;
`else
    branch_pred_taken_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_correct_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_correct_count = perf_branch_correct_q;
`else
    branch_correct_count = 32'b0;
`endif
end
endfunction

function [31:0] branch_mispredict_count; /*verilator public*/
begin
`ifdef ULTRA_PERF_COUNTERS
    branch_mispredict_count = perf_branch_mispredict_q;
`else
    branch_mispredict_count = 32'b0;
`endif
end
endfunction

// Simulation-only architectural/transaction observation points used by the
// closure test fixtures.  They do not feed any RTL control path and are not
// emitted by the normal Vivado build.
function [31:0] irq_exception_pc_value; /*verilator public*/
begin
    irq_exception_pc_value = csr_writeback_exception_pc_w;
end
endfunction

function [5:0] exception_code_value; /*verilator public*/
begin
    exception_code_value = csr_writeback_exception_w;
end
endfunction

function [0:0] take_interrupt_value; /*verilator public*/
begin
    take_interrupt_value = take_interrupt_w;
end
endfunction

function [31:0] csr_mepc_value; /*verilator public*/
begin
    csr_mepc_value = u_csr.u_csrfile.csr_mepc_q;
end
endfunction

function [31:0] csr_mcause_value; /*verilator public*/
begin
    csr_mcause_value = u_csr.u_csrfile.csr_mcause_q;
end
endfunction

function [31:0] csr_mip_value; /*verilator public*/
begin
    csr_mip_value = u_csr.u_csrfile.csr_mip_q;
end
endfunction

function [31:0] data_addr_value; /*verilator public*/
begin
    data_addr_value = mem_d_early_valid_o ? mem_d_early_addr_o : mem_d_addr_o;
end
endfunction

function [31:0] data_write_value; /*verilator public*/
begin
    data_write_value = mem_d_early_valid_o ? mem_d_early_data_wr_o :
                       mem_d_data_wr_o;
end
endfunction

function [3:0] data_write_strobe_value; /*verilator public*/
begin
    data_write_strobe_value = mem_d_early_valid_o ? 4'b0 : mem_d_wr_o;
end
endfunction

function [0:0] data_request_value; /*verilator public*/
begin
    data_request_value = mem_d_early_valid_o ? mem_d_early_rd_o :
                         (mem_d_rd_o | (|mem_d_wr_o));
end
endfunction

function [0:0] csr_commit_write_value; /*verilator public*/
begin
    csr_commit_write_value = csr_writeback_write_w;
end
endfunction

function [11:0] csr_commit_addr_value; /*verilator public*/
begin
    csr_commit_addr_value = csr_writeback_waddr_w;
end
endfunction

function [31:0] csr_commit_data_value; /*verilator public*/
begin
    csr_commit_data_value = csr_writeback_wdata_w;
end
endfunction

// Front-end/branch event observation points for the bounded closure tests.
// These are deliberately simulation-only and do not alter the pipeline.
function [31:0] fetch_pc_value; /*verilator public*/
begin
    fetch_pc_value = fetch_pc_w;
end
endfunction

function [31:0] predictor_pc_value; /*verilator public*/
begin
    predictor_pc_value = predictor_pc_w;
end
endfunction

// Exact predictor event boundaries for the bounded BTB model.  A predictor
// lookup is counted only when the real fetch/MMU request is accepted; the
// predictor PC itself may otherwise remain speculative while fetch is stalled.
// These readers are Verilator-only observation points and do not feed RTL.
function [0:0] predictor_lookup_accept_value; /*verilator public*/
begin
    predictor_lookup_accept_value = mmu_ifetch_rd_w && mmu_ifetch_accept_w;
end
endfunction

function [31:0] predictor_lookup_request_pc_value; /*verilator public*/
begin
    predictor_lookup_request_pc_value = mmu_ifetch_pc_w;
end
endfunction

function [0:0] predictor_lookup_hit_value; /*verilator public*/
begin
    predictor_lookup_hit_value = predictor_hit_w;
end
endfunction

function [0:0] predictor_lookup_taken_value; /*verilator public*/
begin
    predictor_lookup_taken_value = predictor_taken_w;
end
endfunction

function [31:0] predictor_lookup_target_value; /*verilator public*/
begin
    predictor_lookup_target_value = predictor_target_w;
end
endfunction

function [0:0] predictor_update_valid_value; /*verilator public*/
begin
    predictor_update_valid_value = branch_update_valid_w;
end
endfunction

function [31:0] predictor_update_pc_value; /*verilator public*/
begin
    predictor_update_pc_value = branch_update_pc_w;
end
endfunction

function [31:0] predictor_update_target_value; /*verilator public*/
begin
    predictor_update_target_value = branch_update_target_w;
end
endfunction

function [0:0] predictor_update_is_jal_value; /*verilator public*/
begin
    predictor_update_is_jal_value = branch_update_is_jal_w;
end
endfunction

function [0:0] predictor_update_taken_value; /*verilator public*/
begin
    predictor_update_taken_value = branch_update_taken_w;
end
endfunction

function [0:0] predictor_update_pred_taken_value; /*verilator public*/
begin
    predictor_update_pred_taken_value = branch_update_pred_taken_w;
end
endfunction

function [0:0] predictor_update_mispredict_value; /*verilator public*/
begin
    predictor_update_mispredict_value = branch_update_mispredict_w;
end
endfunction

function [0:0] predictor_update_hit_value; /*verilator public*/
begin
    predictor_update_hit_value = predictor_update_hit_w;
end
endfunction

function [0:0] predictor_invalidate_value; /*verilator public*/
begin
    predictor_invalidate_value = ifence_w;
end
endfunction

// Corrected bounded-observation readers.  These expose the real fetch
// acceptance/response/hold boundaries and the exact LSU qualification terms;
// they are intentionally simulation-only and do not alter any datapath.
function [0:0] fetch_decode_valid_value; /*verilator public*/
begin
    fetch_decode_valid_value = fetch_dec_valid_w;
end
endfunction

function [0:0] fetch_decode_accept_value; /*verilator public*/
begin
    fetch_decode_accept_value = fetch_dec_accept_w;
end
endfunction

function [31:0] fetch_decode_pc_value; /*verilator public*/
begin
    fetch_decode_pc_value = fetch_dec_pc_w;
end
endfunction

function [31:0] fetch_decode_instr_value; /*verilator public*/
begin
    fetch_decode_instr_value = fetch_dec_instr_w;
end
endfunction

function [0:0] fetch_decode_pred_taken_value; /*verilator public*/
begin
    fetch_decode_pred_taken_value = fetch_dec_pred_taken_w;
end
endfunction

function [0:0] fetch_response_valid_value; /*verilator public*/
begin
    fetch_response_valid_value = mmu_ifetch_valid_w;
end
endfunction

function [31:0] fetch_response_pc_value; /*verilator public*/
begin
    fetch_response_pc_value = u_fetch.pc_d_q;
end
endfunction

function [0:0] fetch_response_drop_value; /*verilator public*/
begin
    fetch_response_drop_value = u_fetch.fetch_resp_drop_w;
end
endfunction

function [0:0] fetch_skid_valid_value; /*verilator public*/
begin
    fetch_skid_valid_value = u_fetch.skid_valid_q;
end
endfunction

function [0:0] fetch_icache_fetch_value; /*verilator public*/
begin
    fetch_icache_fetch_value = u_fetch.icache_fetch_q;
end
endfunction

function [0:0] fetch_stall_value; /*verilator public*/
begin
    fetch_stall_value = u_fetch.stall_w;
end
endfunction

function [31:0] fetch_pc_f_value; /*verilator public*/
begin
    fetch_pc_f_value = u_fetch.pc_f_q;
end
endfunction

function [31:0] fetch_pc_d_value; /*verilator public*/
begin
    fetch_pc_d_value = u_fetch.pc_d_q;
end
endfunction

function [31:0] branch_exec_pc_value; /*verilator public*/
begin
    branch_exec_pc_value = branch_exec_pc_w;
end
endfunction

function [0:0] branch_exec_request_value; /*verilator public*/
begin
    branch_exec_request_value = branch_exec_request_w;
end
endfunction

function [0:0] branch_request_value; /*verilator public*/
begin
    branch_request_value = branch_request_w;
end
endfunction

function [0:0] branch_mispredict_value; /*verilator public*/
begin
    branch_mispredict_value = branch_d_exec_mispredict_w;
end
endfunction

function [0:0] raw_mem_request_value; /*verilator public*/
begin
    raw_mem_request_value = mem_d_early_valid_o ? mem_d_early_rd_o :
                             (mem_d_rd_o | (|mem_d_wr_o));
end
endfunction
function [0:0] raw_mem_accept_value; /*verilator public*/
begin
    raw_mem_accept_value = mem_d_early_valid_o ? mem_d_early_accept_i :
                           mem_d_accept_i;
end
endfunction
function [0:0] raw_mem_ack_value; /*verilator public*/
begin
    raw_mem_ack_value = mem_d_ack_i;
end
endfunction
function [0:0] raw_mem_writeback_valid_value; /*verilator public*/
begin
    raw_mem_writeback_valid_value = writeback_mem_valid_w;
end
endfunction
function [5:0] raw_mem_exception_value; /*verilator public*/
begin
    raw_mem_exception_value = writeback_mem_exception_w;
end
endfunction
function [0:0] raw_branch_flush_value; /*verilator public*/
begin
    raw_branch_flush_value = branch_request_w | squash_decode_w;
end
endfunction

// Early-TCM feasibility observer.  These readers expose the existing LSU
// combinational address, capture registers, request/response state, and the
// existing MMU-facing handshake.  They are only compiled by Verilator and do
// not participate in functional control or synthesis.
function [31:0] early_lsu_agu_addr_value; /*verilator public*/
begin
    early_lsu_agu_addr_value = u_lsu.early_addr_calc_w;
end
endfunction
function [31:0] early_lsu_addr_q_value; /*verilator public*/
begin
    early_lsu_addr_q_value = u_lsu.mem_addr_q;
end
endfunction
function [31:0] early_lsu_data_r_value; /*verilator public*/
begin
    early_lsu_data_r_value = u_lsu.mem_data_r;
end
endfunction
function [31:0] early_lsu_data_q_value; /*verilator public*/
begin
    early_lsu_data_q_value = u_lsu.mem_data_wr_q;
end
endfunction
function [3:0] early_lsu_wr_r_value; /*verilator public*/
begin
    early_lsu_wr_r_value = u_lsu.mem_wr_r;
end
endfunction
function [3:0] early_lsu_wr_q_value; /*verilator public*/
begin
    early_lsu_wr_q_value = u_lsu.mem_wr_q;
end
endfunction
function [0:0] early_lsu_rd_r_value; /*verilator public*/
begin
    early_lsu_rd_r_value = u_lsu.mem_rd_r;
end
endfunction
function [0:0] early_lsu_rd_q_value; /*verilator public*/
begin
    early_lsu_rd_q_value = u_lsu.mem_rd_q;
end
endfunction
function [0:0] early_lsu_pending_value; /*verilator public*/
begin
    early_lsu_pending_value = u_lsu.pending_lsu_e2_q;
end
endfunction
function [0:0] early_lsu_delay_value; /*verilator public*/
begin
    early_lsu_delay_value = u_lsu.delay_lsu_e2_w;
end
endfunction
function [0:0] early_lsu_unaligned_e1_value; /*verilator public*/
begin
    early_lsu_unaligned_e1_value = u_lsu.mem_unaligned_e1_q;
end
endfunction
function [0:0] early_lsu_unaligned_e2_value; /*verilator public*/
begin
    early_lsu_unaligned_e2_value = u_lsu.mem_unaligned_e2_q;
end
endfunction
function [0:0] early_lsu_issue_value; /*verilator public*/
begin
    early_lsu_issue_value = u_lsu.issue_lsu_e1_w;
end
endfunction
function [0:0] early_lsu_complete_ok_value; /*verilator public*/
begin
    early_lsu_complete_ok_value = u_lsu.complete_ok_e2_w;
end
endfunction
function [0:0] early_lsu_complete_error_value; /*verilator public*/
begin
    early_lsu_complete_error_value = u_lsu.complete_err_e2_w;
end
endfunction
function [0:0] early_lsu_candidate_value; /*verilator public*/
begin
    early_lsu_candidate_value = u_lsu.early_offer_w;
end
endfunction
function [0:0] early_lsu_launch_value; /*verilator public*/
begin
    early_lsu_launch_value = u_lsu.early_launch_w;
end
endfunction
function [0:0] early_lsu_live_value; /*verilator public*/
begin
    early_lsu_live_value = u_lsu.early_live_q;
end
endfunction
function [0:0] early_lsu_hold_valid_value; /*verilator public*/
begin
    early_lsu_hold_valid_value = u_lsu.early_hold_valid_q;
end
endfunction

function [0:0] early_lsu_normal_active_value; /*verilator public*/
begin
    early_lsu_normal_active_value = u_lsu.normal_q_active_w;
end
endfunction

function [0:0] early_lsu_pending_conflict_value; /*verilator public*/
begin
    early_lsu_pending_conflict_value = u_lsu.normal_pending_conflict_w;
end
endfunction

function [0:0] early_lsu_slot_free_value; /*verilator public*/
begin
    early_lsu_slot_free_value = u_lsu.early_slot_free_w;
end
endfunction

function [0:0] early_lsu_early_fire_value; /*verilator public*/
begin
    early_lsu_early_fire_value = u_lsu.early_fire_w;
end
endfunction

function [0:0] early_lsu_response_value; /*verilator public*/
begin
    early_lsu_response_value = u_lsu.early_response_w;
end
endfunction

function [0:0] early_lsu_early_accept_value; /*verilator public*/
begin
    early_lsu_early_accept_value = mem_d_early_accept_i;
end
endfunction

function [31:0] early_lsu_normal_addr_value; /*verilator public*/
begin
    early_lsu_normal_addr_value = u_lsu.mem_addr_r;
end
endfunction

function [0:0] early_lsu_normal_rd_value; /*verilator public*/
begin
    early_lsu_normal_rd_value = u_lsu.mem_rd_r;
end
endfunction

function [0:0] early_lsu_normal_error_value; /*verilator public*/
begin
    early_lsu_normal_error_value = mmu_lsu_error_w;
end
endfunction

function [0:0] early_lsu_opcode_valid_value; /*verilator public*/
begin
    early_lsu_opcode_valid_value = lsu_opcode_valid_w;
end
endfunction

function [31:0] early_lsu_opcode_value; /*verilator public*/
begin
    early_lsu_opcode_value = lsu_opcode_opcode_w;
end
endfunction

function [31:0] early_lsu_opcode_pc_value; /*verilator public*/
begin
    early_lsu_opcode_pc_value = lsu_opcode_pc_w;
end
endfunction

function [31:0] early_lsu_opcode_ra_value; /*verilator public*/
begin
    early_lsu_opcode_ra_value = lsu_opcode_ra_operand_w;
end
endfunction

function [31:0] early_lsu_opcode_rb_value; /*verilator public*/
begin
    early_lsu_opcode_rb_value = lsu_opcode_rb_operand_w;
end
endfunction
function [31:0] early_lsu_early_addr_value; /*verilator public*/
begin
    // v3 removes the redundant launch-address register; expose the same
    // combinational aligned address for the existing simulation observer.
    early_lsu_early_addr_value = u_lsu.early_addr_calc_w;
end
endfunction

function [31:0] early_lsu_request_addr_value; /*verilator public*/
begin
    early_lsu_request_addr_value = early_lsu_addr_w;
end
endfunction

function [31:0] early_base_value_value; /*verilator public*/
begin
    early_base_value_value = early_base_value_w;
end
endfunction
function [4:0] early_lsu_early_rd_value; /*verilator public*/
begin
    early_lsu_early_rd_value = u_lsu.early_rd_q;
end
endfunction
function [31:0] early_lsu_early_data_value; /*verilator public*/
begin
    early_lsu_early_data_value = u_lsu.early_data_hold_q;
end
endfunction
function [0:0] early_result_valid_value; /*verilator public*/
begin
    early_result_valid_value = early_result_valid_w;
end
endfunction
function [31:0] early_result_value_value; /*verilator public*/
begin
    early_result_value_value = early_result_value_w;
end
endfunction
function [4:0] early_result_rd_value; /*verilator public*/
begin
    early_result_rd_value = early_result_rd_w;
end
endfunction
function [0:0] early_result_consume_value; /*verilator public*/
begin
    early_result_consume_value = early_result_consume_w;
end
endfunction
function [0:0] early_load_accept_value; /*verilator public*/
begin
    early_load_accept_value = early_load_accept_w;
end
endfunction
function [0:0] early_support_value; /*verilator public*/
begin
    early_support_value = (SUPPORT_EARLY_TCM_LOAD != 0);
end
endfunction
function [31:0] early_mmu_addr_value; /*verilator public*/
begin
    early_mmu_addr_value = mmu_lsu_addr_w;
end
endfunction
function [0:0] early_mmu_rd_value; /*verilator public*/
begin
    early_mmu_rd_value = mmu_lsu_rd_w;
end
endfunction
function [3:0] early_mmu_wr_value; /*verilator public*/
begin
    early_mmu_wr_value = mmu_lsu_wr_w;
end
endfunction
function [0:0] early_mmu_accept_value; /*verilator public*/
begin
    early_mmu_accept_value = mmu_lsu_accept_w;
end
endfunction
function [0:0] early_mmu_ack_value; /*verilator public*/
begin
    early_mmu_ack_value = mmu_lsu_ack_w;
end
endfunction
function [31:0] early_mmu_data_value; /*verilator public*/
begin
    early_mmu_data_value = mmu_lsu_data_rd_w;
end
endfunction
function [31:0] early_lsu_resp_addr_value; /*verilator public*/
begin
    early_lsu_resp_addr_value = u_lsu.resp_addr_w;
end
endfunction
function [0:0] early_lsu_resp_load_value; /*verilator public*/
begin
    early_lsu_resp_load_value = u_lsu.resp_load_w;
end
endfunction
function [0:0] early_lsu_resp_byte_value; /*verilator public*/
begin
    early_lsu_resp_byte_value = u_lsu.resp_byte_w;
end
endfunction
function [0:0] early_lsu_resp_half_value; /*verilator public*/
begin
    early_lsu_resp_half_value = u_lsu.resp_half_w;
end
endfunction
function [0:0] early_lsu_resp_signed_value; /*verilator public*/
begin
    early_lsu_resp_signed_value = u_lsu.resp_signed_w;
end
endfunction
`endif



endmodule
