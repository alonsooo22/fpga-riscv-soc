//-----------------------------------------------------------------
//                         RISC-V Top
//                            V0.6
//                     Ultra-Embedded.com
//                     Copyright 2014-2019
//
//                   admin@ultra-embedded.com
//
//                       License: BSD
//-----------------------------------------------------------------
//
// Copyright (c) 2014, Ultra-Embedded.com
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

//-----------------------------------------------------------------
//                          Generated File
//-----------------------------------------------------------------
module dport_mux
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter TCM_MEM_BASE     = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
     ,input  [ 31:0]  mem_addr_i
     ,input  [ 31:0]  mem_data_wr_i
     ,input           mem_rd_i
     ,input  [  3:0]  mem_wr_i
     ,input           mem_early_valid_i
     ,input  [ 31:0]  mem_early_addr_i
     ,input  [ 31:0]  mem_early_data_wr_i
     ,input           mem_early_rd_i
     ,input           mem_cacheable_i
    ,input  [ 10:0]  mem_req_tag_i
    ,input           mem_invalidate_i
    ,input           mem_writeback_i
    ,input           mem_flush_i
    ,input  [ 31:0]  mem_tcm_data_rd_i
    ,input           mem_tcm_accept_i
    ,input           mem_tcm_ack_i
    ,input           mem_tcm_error_i
    ,input  [ 10:0]  mem_tcm_resp_tag_i
    ,input  [ 31:0]  mem_ext_data_rd_i
    ,input           mem_ext_accept_i
    ,input           mem_ext_ack_i
    ,input           mem_ext_error_i
    ,input  [ 10:0]  mem_ext_resp_tag_i

    // Outputs
     ,output [ 31:0]  mem_data_rd_o
     ,output          mem_accept_o
     ,output          mem_early_accept_o
     ,output          mem_ack_o
    ,output          mem_error_o
    ,output [ 10:0]  mem_resp_tag_o
    ,output [ 31:0]  mem_tcm_addr_o
    ,output [ 31:0]  mem_tcm_data_wr_o
    ,output          mem_tcm_rd_o
    ,output [  3:0]  mem_tcm_wr_o
    ,output          mem_tcm_cacheable_o
    ,output [ 10:0]  mem_tcm_req_tag_o
    ,output          mem_tcm_invalidate_o
    ,output          mem_tcm_writeback_o
    ,output          mem_tcm_flush_o
    ,output [ 31:0]  mem_ext_addr_o
    ,output [ 31:0]  mem_ext_data_wr_o
    ,output          mem_ext_rd_o
    ,output [  3:0]  mem_ext_wr_o
    ,output          mem_ext_cacheable_o
    ,output [ 10:0]  mem_ext_req_tag_o
    ,output          mem_ext_invalidate_o
    ,output          mem_ext_writeback_o
    ,output          mem_ext_flush_o
);



//-----------------------------------------------------------------
// Dcache_if mux
//-----------------------------------------------------------------
/* verilator lint_off UNSIGNED */
wire tcm_access_w = (mem_addr_i >= TCM_MEM_BASE && mem_addr_i < (TCM_MEM_BASE + 32'd65536));
/* verilator lint_on UNSIGNED */

reg       tcm_access_q;
reg [4:0] pending_q;

wire normal_request_w = mem_rd_i || mem_wr_i != 4'b0 || mem_flush_i ||
                         mem_invalidate_i || mem_writeback_i;
wire normal_tcm_request_w = normal_request_w && tcm_access_w;
wire normal_ext_request_w = normal_request_w && !tcm_access_w;
wire normal_hold_w = (|pending_q) && (tcm_access_q != tcm_access_w);
// The early sideband is a TCM read only.  A pending external response keeps
// the early offer visible to the LSU but suppresses the physical request until
// the shared response source is free; the LSU then takes its normal fallback.
wire early_hold_w = (|pending_q) && !tcm_access_q;
wire early_active_w = mem_early_valid_i && !normal_request_w && !early_hold_w;
wire normal_tcm_active_w = normal_tcm_request_w && !normal_hold_w;
wire normal_ext_active_w = normal_ext_request_w && !normal_hold_w;
wire normal_accept_w = normal_request_w &&
                       (tcm_access_w ? mem_tcm_accept_i : mem_ext_accept_i) &&
                       !normal_hold_w;
wire early_accept_w = early_active_w && mem_tcm_accept_i;
wire selected_accept_w = normal_accept_w || early_accept_w;
wire request_w = normal_request_w || early_active_w;
wire selected_tcm_access_w = early_active_w ? 1'b1 : tcm_access_w;

// Address is the only TCM field selected from the early sideband.  All normal
// data, write enables, maintenance controls, cache attributes and tags stay
// on the registered normal request path; the early path cannot reach the
// external port or generate a write.
assign mem_tcm_addr_o       = early_active_w ? mem_early_addr_i : mem_addr_i;
assign mem_tcm_data_wr_o    = mem_data_wr_i;
assign mem_tcm_rd_o         = early_active_w ? 1'b1 :
                              (normal_tcm_active_w ? mem_rd_i : 1'b0);
assign mem_tcm_wr_o         = normal_tcm_active_w ? mem_wr_i : 4'b0;
assign mem_tcm_cacheable_o  = normal_tcm_active_w ? mem_cacheable_i : 1'b0;
assign mem_tcm_req_tag_o    = normal_tcm_active_w ? mem_req_tag_i : 11'b0;
assign mem_tcm_invalidate_o = normal_tcm_active_w ? mem_invalidate_i : 1'b0;
assign mem_tcm_writeback_o  = normal_tcm_active_w ? mem_writeback_i : 1'b0;
assign mem_tcm_flush_o      = normal_tcm_active_w ? mem_flush_i : 1'b0;

assign mem_ext_addr_o       = mem_addr_i;
assign mem_ext_data_wr_o    = mem_data_wr_i;
assign mem_ext_rd_o         = normal_ext_active_w ? mem_rd_i : 1'b0;
assign mem_ext_wr_o         = normal_ext_active_w ? mem_wr_i : 4'b0;
assign mem_ext_cacheable_o  = normal_ext_active_w ? mem_cacheable_i : 1'b0;
assign mem_ext_req_tag_o    = normal_ext_active_w ? mem_req_tag_i : 11'b0;
assign mem_ext_invalidate_o = normal_ext_active_w ? mem_invalidate_i : 1'b0;
assign mem_ext_writeback_o  = normal_ext_active_w ? mem_writeback_i : 1'b0;
assign mem_ext_flush_o      = normal_ext_active_w ? mem_flush_i : 1'b0;

assign mem_accept_o         = normal_accept_w;
assign mem_early_accept_o   = early_accept_w;
assign mem_data_rd_o        = tcm_access_q ? mem_tcm_data_rd_i  : mem_ext_data_rd_i;
assign mem_ack_o            = tcm_access_q ? mem_tcm_ack_i      : mem_ext_ack_i;
assign mem_error_o          = tcm_access_q ? mem_tcm_error_i    : mem_ext_error_i;
assign mem_resp_tag_o       = tcm_access_q ? mem_tcm_resp_tag_i : mem_ext_resp_tag_i;

reg [4:0] pending_r;
always @ *
begin
    pending_r = pending_q;

    if ((request_w && selected_accept_w) && !mem_ack_o)
        pending_r = pending_r + 5'd1;
    else if (!(request_w && selected_accept_w) && mem_ack_o)
        pending_r = pending_r - 5'd1;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pending_q <= 5'b0;
else
    pending_q <= pending_r;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    tcm_access_q <= 1'b0;
else if (request_w && selected_accept_w)
    tcm_access_q <= selected_tcm_access_w;

`ifdef verilator
// dport-level checks observe the physical TCM/AXI pins, not just the LSU
// candidate.  In particular, an early offer may never turn into a normal
// write, maintenance operation, or external transaction.
always @ (posedge clk_i)
if (!rst_i)
begin
    if (early_active_w && normal_request_w)
        $fatal(1, "E-TCM v3 normal request overlaps early TCM selection");

    if (early_active_w &&
        (mem_tcm_wr_o != 4'b0 || mem_ext_rd_o || (|mem_ext_wr_o) ||
         mem_tcm_invalidate_o || mem_tcm_writeback_o || mem_tcm_flush_o))
        $fatal(1, "E-TCM v3 early selection drives normal side effects");

    if (mem_early_accept_o && !early_active_w)
        $fatal(1, "E-TCM v3 physical early accept without active TCM read");
end
`endif



endmodule
