`timescale 1ns/1ps
`include "riscv_defs.v"
module units_tb;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,hold=0,valid=0;
 reg [31:0] ins=0,a=0,b=0;
 reg [3:0] op=0;
 wire [31:0] result,mul;
 wire inv,ex,mu,rd,inv_off,mu_off;
 riscv_alu #(.SUPPORT_XBEXTU(1),.SUPPORT_XPACK16(1),.SUPPORT_XADD16(1)) alu(op,a,b,result);
 riscv_decoder #(.SUPPORT_XBEXTU(1),.SUPPORT_XPACK16(1),.SUPPORT_XDOT2H(1),.SUPPORT_XADD16(1)) dec(
 .valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(ins),.invalid_o(inv),.exec_o(ex),.mul_o(mu),.rd_valid_o(rd),.lsu_o(),.branch_o(),.div_o(),.csr_o());
 riscv_decoder off_dec(.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(ins),.invalid_o(inv_off),.mul_o(mu_off),.exec_o(),.rd_valid_o(),.lsu_o(),.branch_o(),.div_o(),.csr_o());
 riscv_multiplier #(.SUPPORT_XDOT2H(1)) m(
 .clk_i(clk),.rst_i(rst),.hold_i(hold),.opcode_valid_i(valid),.opcode_opcode_i(ins),.opcode_pc_i(0),.opcode_invalid_i(0),
 .opcode_rd_idx_i(0),.opcode_ra_idx_i(0),.opcode_rb_idx_i(0),.opcode_ra_operand_i(a),.opcode_rb_operand_i(b),.writeback_value_o(mul));
 function automatic [31:0] dot(input [31:0] x,y);
  reg signed [31:0] p,q; reg signed [32:0] s;
  begin p=$signed(x[15:0])*$signed(y[15:0]);q=$signed(x[31:16])*$signed(y[31:16]);s={p[31],p}+{q[31],q};dot=s[31:0];end
 endfunction
 task automatic check_decode(input [31:0] word,input bit ismul);
  ins=word;#1;if(inv||!rd||mu!=ismul||ex==ismul||!inv_off||mu_off)$fatal(1,"decode %h",word);
 endtask
 task automatic check_mul(input [31:0] word,x,y,expected,input bit pause);
  @(negedge clk);ins=word;a=x;b=y;valid=1;
  @(negedge clk);valid=0;
  if(pause)begin hold=1;repeat(3)@(negedge clk);hold=0;end
  @(negedge clk);if(mul!==expected)$fatal(1,"multiply %h != %h",mul,expected);
 endtask
 reg [31:0] x,y,expected;
 initial begin
  repeat(2)@(negedge clk);rst=0;
  check_decode(`INST_XBEXTU,0);check_decode(`INST_XPACK16,0);check_decode(`INST_XDOT2H,1);check_decode(`INST_XADD16,0);
  ins=`INST_XBEXTU|32'h40000000;#1;if(!inv)$fatal(1,"reserved BEXT");
  ins=`INST_XDOT2H|32'h02000000;#1;if(!inv)$fatal(1,"reserved DOT");
  for(int s=0;s<32;s++)for(int w=1;w<=32;w++)begin
   a=32'h87654321;b=((w-1)<<5)|s;op=`ALU_XBEXTU;#1;
   expected=(a>>s)&(32'hffffffff>>(32-w));if(result!==expected)$fatal(1,"extract %d %d",s,w);
  end
  for(int i=0;i<200;i++)begin
   x=$random;y=$random;a=x;b=y;op=`ALU_XPACK16;#1;if(result!=={y[15:0],x[15:0]})$fatal(1,"pack");
   op=`ALU_XADD16;expected={16'(x[31:16]+y[31:16]),16'(x[15:0]+y[15:0])};#1;if(result!==expected)$fatal(1,"add16");
   check_mul(`INST_XDOT2H,x,y,dot(x,y),i%3==0);
   check_mul(`INST_MUL,x,y,x*y,0);
  end
  check_mul(`INST_XDOT2H,32'h80008000,32'h80008000,32'h80000000,1);
  $display("XSIMD_UNITS_PASS");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
