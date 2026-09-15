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

module riscv_decode #(
    parameter SUPPORT_XBEXTU = 0,
    parameter SUPPORT_XPACK16 = 0,
    parameter SUPPORT_XDOT2H = 0,
    parameter SUPPORT_XADD16 = 0,
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
     parameter SUPPORT_MULDIV   = 1
    ,parameter EXTRA_DECODE_STAGE = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           fetch_in_valid_i
     ,input  [ 31:0]  fetch_in_instr_i
     ,input  [ 31:0]  fetch_in_pc_i
    ,input           fetch_in_pred_taken_i
     ,input           fetch_in_fault_fetch_i
    ,input           fetch_in_fault_page_i
    ,input           fetch_out_accept_i
    ,input           squash_decode_i

    // Outputs
    ,output          fetch_in_accept_o
    ,output          fetch_out_valid_o
     ,output [ 31:0]  fetch_out_instr_o
     ,output [ 31:0]  fetch_out_pc_o
    ,output          fetch_out_pred_taken_o
     ,output          fetch_out_fault_fetch_o
    ,output          fetch_out_fault_page_o
    ,output          fetch_out_instr_exec_o
    ,output          fetch_out_instr_lsu_o
    ,output          fetch_out_instr_branch_o
    ,output          fetch_out_instr_mul_o
    ,output          fetch_out_instr_div_o
    ,output          fetch_out_instr_csr_o
    ,output          fetch_out_instr_rd_valid_o
    ,output          fetch_out_instr_invalid_o
);



wire        enable_muldiv_w     = SUPPORT_MULDIV;

// Decode classification is only meaningful for a valid buffered slot.  Keep
// the decoder outputs private and apply the slot-valid gate at this wrapper;
// this also prevents stale payload bits from becoming effective operations
// after reset or a decode squash.
wire decoder_invalid_w;
wire decoder_exec_w;
wire decoder_lsu_w;
wire decoder_branch_w;
wire decoder_mul_w;
wire decoder_div_w;
wire decoder_csr_w;
wire decoder_rd_valid_w;

//-----------------------------------------------------------------
// Extra decode stage (to improve cycle time)
//-----------------------------------------------------------------
generate
if (EXTRA_DECODE_STAGE)
begin
    wire [31:0] fetch_in_instr_w = (fetch_in_fault_page_i | fetch_in_fault_fetch_i) ? 32'b0 : fetch_in_instr_i;
    reg         buffer_valid_q;
    reg [66:0]  buffer_payload_q;

    always @(posedge clk_i or posedge rst_i)
    if (rst_i)
        buffer_valid_q <= 1'b0;
    else if (squash_decode_i)
        buffer_valid_q <= 1'b0;
    else if (fetch_out_accept_i || !buffer_valid_q)
    begin
        buffer_valid_q <= fetch_in_valid_i;
    end

    // The payload has no reset or squash side effect.  It is meaningful only
    // while buffer_valid_q is asserted; keeping it in a separate process also
    // prevents synthesis from inferring an artificial set/reset pair for the
    // payload flops.
    always @(posedge clk_i)
    if (fetch_out_accept_i || !buffer_valid_q)
    begin
        if (fetch_in_valid_i)
            buffer_payload_q <= {fetch_in_fault_page_i, fetch_in_fault_fetch_i,
                                 fetch_in_pred_taken_i, fetch_in_instr_w, fetch_in_pc_i};
    end

    assign fetch_out_valid_o = buffer_valid_q;
    assign {fetch_out_fault_page_o,
            fetch_out_fault_fetch_o,
            fetch_out_pred_taken_o,
            fetch_out_instr_o,
            fetch_out_pc_o} = buffer_payload_q;

    riscv_decoder
#(
    .SUPPORT_XBEXTU(SUPPORT_XBEXTU),
    .SUPPORT_XPACK16(SUPPORT_XPACK16),
    .SUPPORT_XDOT2H(SUPPORT_XDOT2H),
    .SUPPORT_XADD16(SUPPORT_XADD16)
)
    u_dec
    (
         .valid_i(fetch_out_valid_o)
        ,.fetch_fault_i(fetch_out_fault_page_o | fetch_out_fault_fetch_o)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_out_instr_o)

        ,.invalid_o(decoder_invalid_w)
        ,.exec_o(decoder_exec_w)
        ,.lsu_o(decoder_lsu_w)
        ,.branch_o(decoder_branch_w)
        ,.mul_o(decoder_mul_w)
        ,.div_o(decoder_div_w)
        ,.csr_o(decoder_csr_w)
        ,.rd_valid_o(decoder_rd_valid_w)
    );

    assign fetch_in_accept_o        = fetch_out_accept_i;
end
//-----------------------------------------------------------------
// Straight through decode
//-----------------------------------------------------------------
else
begin
    wire [31:0] fetch_in_instr_w = (fetch_in_fault_page_i | fetch_in_fault_fetch_i) ? 32'b0 : fetch_in_instr_i;

    riscv_decoder
#(
    .SUPPORT_XBEXTU(SUPPORT_XBEXTU),
    .SUPPORT_XPACK16(SUPPORT_XPACK16),
    .SUPPORT_XDOT2H(SUPPORT_XDOT2H),
    .SUPPORT_XADD16(SUPPORT_XADD16)
)
    u_dec
    (
         .valid_i(fetch_in_valid_i)
        ,.fetch_fault_i(fetch_in_fault_fetch_i | fetch_in_fault_page_i)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_out_instr_o)

        ,.invalid_o(decoder_invalid_w)
        ,.exec_o(decoder_exec_w)
        ,.lsu_o(decoder_lsu_w)
        ,.branch_o(decoder_branch_w)
        ,.mul_o(decoder_mul_w)
        ,.div_o(decoder_div_w)
        ,.csr_o(decoder_csr_w)
        ,.rd_valid_o(decoder_rd_valid_w)
    );

    // Outputs
    assign fetch_out_valid_o        = fetch_in_valid_i;
    assign fetch_out_pc_o           = fetch_in_pc_i;
    assign fetch_out_instr_o        = fetch_in_instr_w;
    assign fetch_out_pred_taken_o   = fetch_in_pred_taken_i;
    assign fetch_out_fault_page_o   = fetch_in_fault_page_i;
    assign fetch_out_fault_fetch_o  = fetch_in_fault_fetch_i;

    assign fetch_in_accept_o        = fetch_out_accept_i;
end
endgenerate

assign fetch_out_instr_invalid_o   = fetch_out_valid_o && decoder_invalid_w;
assign fetch_out_instr_exec_o      = fetch_out_valid_o && decoder_exec_w;
assign fetch_out_instr_lsu_o       = fetch_out_valid_o && decoder_lsu_w;
assign fetch_out_instr_branch_o    = fetch_out_valid_o && decoder_branch_w;
assign fetch_out_instr_mul_o       = fetch_out_valid_o && decoder_mul_w;
assign fetch_out_instr_div_o       = fetch_out_valid_o && decoder_div_w;
assign fetch_out_instr_csr_o       = fetch_out_valid_o && decoder_csr_w;
assign fetch_out_instr_rd_valid_o  = fetch_out_valid_o && decoder_rd_valid_w;


endmodule
