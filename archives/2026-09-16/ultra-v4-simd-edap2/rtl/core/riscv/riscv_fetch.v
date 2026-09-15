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

module riscv_fetch
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MMU      = 1
    ,parameter SUPPORT_BRANCH_PREDICTION = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           fetch_accept_i
    ,input           icache_accept_i
    ,input           icache_valid_i
    ,input           icache_error_i
    ,input  [ 31:0]  icache_inst_i
    ,input           icache_page_fault_i
    ,input           fetch_invalidate_i
     ,input           branch_request_i
     ,input  [ 31:0]  branch_pc_i
     ,input  [  1:0]  branch_priv_i
    ,input           prediction_taken_i
    ,input  [ 31:0]  prediction_target_i

    // Outputs
    ,output          fetch_valid_o
    ,output [ 31:0]  fetch_instr_o
    ,output [ 31:0]  fetch_pc_o
    ,output          fetch_fault_fetch_o
    ,output          fetch_fault_page_o
    ,output          icache_rd_o
    ,output          icache_flush_o
    ,output          icache_invalidate_o
     ,output [ 31:0]  icache_pc_o
     ,output [  1:0]  icache_priv_o
    ,output [ 31:0]  prediction_pc_o
    ,output          fetch_pred_taken_o
     ,output          squash_decode_o
`ifdef ULTRA_PERF_COUNTERS
    ,output          perf_branch_redirect_o
    ,output          perf_branch_flush_o
    ,output          perf_fetch_starve_o
`endif
);



//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "riscv_defs.v"

//-------------------------------------------------------------
// Registers / Wires
//-------------------------------------------------------------
reg         active_q;

wire        icache_busy_w;
wire        stall_w       = !fetch_accept_i || icache_busy_w || !icache_accept_i;

//-------------------------------------------------------------
// Buffered branch
//-------------------------------------------------------------
reg         branch_q;
reg [31:0]  branch_pc_q;
reg [1:0]   branch_priv_q;

// Valid state keeps the original priority and handshake expression.  The
// address/privilege payload is intentionally maintained separately so that
// an instruction-consume event cannot toggle its CE or feed a clear value.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    branch_q <= 1'b0;
else if (branch_request_i)
    branch_q <= 1'b1;
else if (icache_rd_o && icache_accept_i)
    branch_q <= 1'b0;

// Recovery payload is written only by reset or a new request.  It remains
// stable after consumption; branch_q gates all uses of this stale payload.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    branch_pc_q    <= 32'b0;
    branch_priv_q  <= `PRIV_MACHINE;
end
else if (branch_request_i)
begin
    branch_pc_q    <= branch_pc_i;
    branch_priv_q  <= branch_priv_i;
end

wire        branch_w      = branch_q;
wire [31:0] branch_pc_w   = branch_pc_q;
wire [1:0]  branch_priv_w = branch_priv_q;

assign squash_decode_o    = branch_request_i;

//-------------------------------------------------------------
// Active flag
//-------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    active_q    <= 1'b0;
else if (branch_w && ~stall_w)
    active_q    <= 1'b1;

//-------------------------------------------------------------
// Stall flag
//-------------------------------------------------------------
reg stall_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    stall_q    <= 1'b0;
else
    stall_q    <= stall_w;

//-------------------------------------------------------------
// Request tracking
//-------------------------------------------------------------
reg icache_fetch_q;
reg icache_invalidate_q;

// ICACHE fetch tracking
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    icache_fetch_q <= 1'b0;
else if (icache_rd_o && icache_accept_i)
    icache_fetch_q <= 1'b1;
else if (icache_valid_i)
    icache_fetch_q <= 1'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    icache_invalidate_q <= 1'b0;
else if (icache_invalidate_o && !icache_accept_i)
    icache_invalidate_q <= 1'b1;
else
    icache_invalidate_q <= 1'b0;

//-------------------------------------------------------------
// PC
//-------------------------------------------------------------
reg [31:0]  pc_f_q;
reg [31:0]  pc_d_q;

wire [31:0] icache_pc_w;
wire [1:0]  icache_priv_w;
wire        fetch_resp_drop_w;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pc_f_q  <= 32'b0;
// Branch request
else if (branch_w && ~stall_w)
    pc_f_q  <= branch_pc_w;
// NPC
else if (!stall_w)
    pc_f_q  <= (SUPPORT_BRANCH_PREDICTION && prediction_taken_i) ?
               prediction_target_i : {icache_pc_w[31:2],2'b0} + 32'd4;

reg [1:0] priv_f_q;
reg       branch_d_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    priv_f_q  <= `PRIV_MACHINE;
// Branch request
else if (branch_w && ~stall_w)
    priv_f_q  <= branch_priv_w;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    branch_d_q  <= 1'b0;
// Branch request
else if (branch_w && ~stall_w)
    branch_d_q  <= 1'b1;
// NPC
else if (!stall_w)
    branch_d_q  <= 1'b0;

assign icache_pc_w       = pc_f_q;
assign icache_priv_w     = priv_f_q;
assign fetch_resp_drop_w = branch_w | branch_d_q;
assign prediction_pc_o   = pc_f_q;

// Prediction direction is request metadata. It is captured only when the
// instruction request is accepted, using the same event as pc_d_q.
reg prediction_taken_q;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    prediction_taken_q <= 1'b0;
else if (icache_rd_o && icache_accept_i)
    prediction_taken_q <= SUPPORT_BRANCH_PREDICTION ? prediction_taken_i : 1'b0;

// Last fetch address
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pc_d_q <= 32'b0;
else if (icache_rd_o && icache_accept_i)
    pc_d_q <= icache_pc_w;

//-------------------------------------------------------------
// Outputs
//-------------------------------------------------------------
assign icache_rd_o         = active_q & fetch_accept_i & !icache_busy_w;
assign icache_pc_o         = {icache_pc_w[31:2],2'b0};
assign icache_priv_o       = icache_priv_w;
assign icache_flush_o      = fetch_invalidate_i | icache_invalidate_q;
assign icache_invalidate_o = 1'b0;

assign icache_busy_w       =  icache_fetch_q && !icache_valid_i;

//-------------------------------------------------------------
// Response Buffer
//-------------------------------------------------------------
reg [66:0]  skid_buffer_q;
reg         skid_valid_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    skid_buffer_q  <= 67'b0;
    skid_valid_q   <= 1'b0;
end 
// Instruction output back-pressured - hold in skid buffer
else if (fetch_valid_o && !fetch_accept_i)
begin
    skid_valid_q  <= 1'b1;
    skid_buffer_q <= {fetch_fault_page_o, fetch_fault_fetch_o,
                       fetch_pred_taken_o, fetch_pc_o, fetch_instr_o};
end
else
begin
    skid_valid_q  <= 1'b0;
    skid_buffer_q <= 67'b0;
end

assign fetch_valid_o       = (icache_valid_i || skid_valid_q) & !fetch_resp_drop_w;
assign fetch_pc_o          = skid_valid_q ? skid_buffer_q[63:32] : {pc_d_q[31:2],2'b0};
assign fetch_instr_o       = skid_valid_q ? skid_buffer_q[31:0]  : icache_inst_i;
assign fetch_pred_taken_o  = skid_valid_q ? skid_buffer_q[64] : prediction_taken_q;

`ifdef ULTRA_PERF_COUNTERS
// A redirect is counted when the buffered target is actually applied. The
// flush counter covers cycles in which returned instructions are suppressed
// while the redirect is being consumed. Fetch starvation excludes those
// cycles and all fetch/backend backpressure represented by stall_w.
assign perf_branch_redirect_o = branch_w && !stall_w;
assign perf_branch_flush_o    = fetch_resp_drop_w;
assign perf_fetch_starve_o    = !fetch_valid_o && !fetch_resp_drop_w && !stall_w;
`endif

// Faults
assign fetch_fault_fetch_o = skid_valid_q ? skid_buffer_q[65] : icache_error_i;
assign fetch_fault_page_o  = skid_valid_q ? skid_buffer_q[66] : icache_page_fault_i;



endmodule
