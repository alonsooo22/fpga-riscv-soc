// Simulation-only scoreboard observer included from riscv_issue.v.
// It is intentionally a separate file so the accepted RTL source is not
// changed by this follow-up experiment.
function [0:0] trace_uses_rs1;
    input [31:0] opcode;
    begin
        case (opcode[6:0])
        7'h13, 7'h03, 7'h23, 7'h33, 7'h63, 7'h67:
            trace_uses_rs1 = 1'b1;
        7'h73:
            trace_uses_rs1 = (opcode[14:12] == 3'b001) ||
                             (opcode[14:12] == 3'b010) ||
                             (opcode[14:12] == 3'b011);
        default:
            trace_uses_rs1 = 1'b0;
        endcase
    end
endfunction

function [0:0] trace_uses_rs2;
    input [31:0] opcode;
    begin
        trace_uses_rs2 = (opcode[6:0] == 7'h23) ||
                         (opcode[6:0] == 7'h33) ||
                         (opcode[6:0] == 7'h63);
    end
endfunction

function [0:0] trace_writes_rd;
    input [31:0] opcode;
    begin
        case (opcode[6:0])
        7'h13, 7'h03, 7'h33, 7'h37, 7'h17, 7'h6f, 7'h67:
            trace_writes_rd = 1'b1;
        7'h73:
            trace_writes_rd = opcode[14:12] != 3'b000;
        default:
            trace_writes_rd = 1'b0;
        endcase
    end
endfunction

// Bits: immediate, load, store, branch, LUI, AUIPC, JAL, JALR, M,
// CSR-register, CSR-immediate.
function [10:0] trace_class;
    input [31:0] opcode;
    begin
        trace_class = 11'b0;
        case (opcode[6:0])
        7'h13: trace_class[0] = 1'b1;
        7'h03: trace_class[1] = 1'b1;
        7'h23: trace_class[2] = 1'b1;
        7'h63: trace_class[3] = 1'b1;
        7'h37: trace_class[4] = 1'b1;
        7'h17: trace_class[5] = 1'b1;
        7'h6f: trace_class[6] = 1'b1;
        7'h67: trace_class[7] = 1'b1;
        7'h33: trace_class[8] = 1'b1;
        7'h73:
            if ((opcode[14:12] == 3'b001) ||
                (opcode[14:12] == 3'b010) ||
                (opcode[14:12] == 3'b011))
                trace_class[9] = 1'b1;
            else if ((opcode[14:12] == 3'b101) ||
                     (opcode[14:12] == 3'b110) ||
                     (opcode[14:12] == 3'b111))
                trace_class[10] = 1'b1;
        default: ;
        endcase
    end
endfunction

// This small static check covers the field-use contract independently of
// the benchmark instruction mix. CSR immediate forms use zimm in rs1's
// encoded field and therefore must not be treated as an rs1 dependency.
initial begin
    if (!trace_uses_rs1(32'h0051_0093) || trace_uses_rs2(32'h0051_0093) ||
        !trace_writes_rd(32'h0051_0093))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK ADDI");
    if (!trace_uses_rs1(32'h0001_2083) || trace_uses_rs2(32'h0001_2083) ||
        !trace_writes_rd(32'h0001_2083))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK LOAD");
    if (!trace_uses_rs1(32'h0011_2023) || !trace_uses_rs2(32'h0011_2023) ||
        trace_writes_rd(32'h0011_2023))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK STORE");
    if (!trace_uses_rs1(32'h0020_8663) || !trace_uses_rs2(32'h0020_8663) ||
        trace_writes_rd(32'h0020_8663))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK BRANCH");
    if (trace_uses_rs1(32'h0000_10b7) || trace_uses_rs2(32'h0000_10b7) ||
        !trace_writes_rd(32'h0000_10b7) ||
        trace_uses_rs1(32'h0000_1097) || trace_uses_rs2(32'h0000_1097) ||
        !trace_writes_rd(32'h0000_1097))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK LUI_AUIPC");
    if (trace_uses_rs1(32'h0040_00ef) || trace_uses_rs2(32'h0040_00ef) ||
        !trace_writes_rd(32'h0040_00ef) ||
        !trace_uses_rs1(32'h0001_00e7) || trace_uses_rs2(32'h0001_00e7) ||
        !trace_writes_rd(32'h0001_00e7))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK JAL_JALR");
    if (!trace_uses_rs1(32'h0220_81b3) || !trace_uses_rs2(32'h0220_81b3) ||
        !trace_writes_rd(32'h0220_81b3))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK M");
    if (!trace_uses_rs1(32'h3001_10f3) || trace_uses_rs2(32'h3001_10f3) ||
        !trace_writes_rd(32'h3001_10f3) ||
        trace_uses_rs1(32'h3001_60f3) || trace_uses_rs2(32'h3001_60f3) ||
        !trace_writes_rd(32'h3001_60f3))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK CSR_REG_IMM");
    if (trace_uses_rs1(32'h0000_0073) || trace_uses_rs2(32'h0000_0073) ||
        trace_writes_rd(32'h0000_0073))
        $fatal(1, "SCOREBOARD_OBSERVER_SELF_CHECK SYSTEM");
end

wire trace_sem_uses_rs1_w  = trace_uses_rs1(fetch_instr_i);
wire trace_sem_uses_rs2_w  = trace_uses_rs2(fetch_instr_i);
wire trace_sem_writes_rd_w = trace_writes_rd(fetch_instr_i);
wire trace_csr_accept_w = opcode_issue_r && issue_csr_w &&
                          !issue_invalid_w && !take_interrupt_i;
wire trace_snapshot_scoreboard_w = trace_csr_accept_w &&
                                   (opcode_opcode_o[31:20] == `CSR_ULTRA_SCOREBOARD);
wire trace_timestamp_w = trace_csr_accept_w &&
                         (opcode_opcode_o[31:20] == `CSR_MCYCLE);
wire trace_system_or_invalid_w = issue_invalid_w ||
                                 ((fetch_instr_i[6:0] == 7'h73) &&
                                  (fetch_instr_i[14:12] == 3'b000));
wire trace_blanket_w = (pipe_load_e1_w || pipe_store_e1_w) &&
                       (issue_mul_w || issue_div_w || issue_csr_w);
wire trace_blanket_load_mul_w  = pipe_load_e1_w && issue_mul_w;
wire trace_blanket_load_div_w  = pipe_load_e1_w && issue_div_w;
wire trace_blanket_load_csr_w  = pipe_load_e1_w && issue_csr_w;
wire trace_blanket_store_mul_w = pipe_store_e1_w && issue_mul_w;
wire trace_blanket_store_div_w = pipe_store_e1_w && issue_div_w;
wire trace_blanket_store_csr_w = pipe_store_e1_w && issue_csr_w;
wire trace_load_e1_w = pipe_load_e1_w && (|pipe_rd_e1_w);
wire trace_mul_e1_w  = pipe_mul_e1_w  && (|pipe_rd_e1_w);
wire trace_load_e2_w = (SUPPORT_LOAD_BYPASS == 0) && pipe_load_e2_w &&
                       (|pipe_rd_e2_w);
wire trace_mul_e2_w  = (SUPPORT_MUL_BYPASS == 0) && pipe_mul_e2_w &&
                       (|pipe_rd_e2_w);
wire trace_load_raw_w =
       (trace_load_e1_w &&
        ((trace_sem_uses_rs1_w && issue_ra_idx_w == pipe_rd_e1_w) ||
         (trace_sem_uses_rs2_w && issue_rb_idx_w == pipe_rd_e1_w)))
    || (trace_load_e2_w &&
        ((trace_sem_uses_rs1_w && issue_ra_idx_w == pipe_rd_e2_w) ||
         (trace_sem_uses_rs2_w && issue_rb_idx_w == pipe_rd_e2_w)));
wire trace_mul_raw_w =
       (trace_mul_e1_w &&
        ((trace_sem_uses_rs1_w && issue_ra_idx_w == pipe_rd_e1_w) ||
         (trace_sem_uses_rs2_w && issue_rb_idx_w == pipe_rd_e1_w)))
    || (trace_mul_e2_w &&
        ((trace_sem_uses_rs1_w && issue_ra_idx_w == pipe_rd_e2_w) ||
         (trace_sem_uses_rs2_w && issue_rb_idx_w == pipe_rd_e2_w)));
wire trace_waw_w = issue_sb_alloc_w && (|issue_rd_idx_w) &&
       !issue_invalid_w && trace_sem_writes_rd_w &&
       ((trace_load_e1_w && issue_rd_idx_w == pipe_rd_e1_w) ||
        (trace_mul_e1_w  && issue_rd_idx_w == pipe_rd_e1_w)  ||
        (trace_load_e2_w && issue_rd_idx_w == pipe_rd_e2_w) ||
        (trace_mul_e2_w  && issue_rd_idx_w == pipe_rd_e2_w));
wire trace_unused_rs1_w = (!trace_sem_uses_rs1_w) &&
                          scoreboard_r[issue_ra_idx_w];
wire trace_unused_rs2_w = (!trace_sem_uses_rs2_w) &&
                          scoreboard_r[issue_rb_idx_w];
wire trace_invalid_rd_w = (!trace_sem_writes_rd_w || issue_invalid_w) &&
                          scoreboard_r[issue_rd_idx_w];
wire trace_unused_field_w = trace_unused_rs1_w || trace_unused_rs2_w ||
                            trace_invalid_rd_w;
wire trace_x0_field_w =
       scoreboard_r[5'b0] && !issue_invalid_w &&
       (((trace_sem_uses_rs1_w && issue_ra_idx_w == 5'b0)) ||
        ((trace_sem_uses_rs2_w && issue_rb_idx_w == 5'b0)) ||
        ((trace_sem_writes_rd_w && issue_rd_idx_w == 5'b0)));
wire trace_mixed_raw_w = trace_load_raw_w && trace_mul_raw_w;
wire trace_false_only_w = scoreboard_hazard_r && !trace_blanket_w &&
                          !trace_load_raw_w && !trace_mul_raw_w &&
                          !trace_waw_w &&
                          !trace_system_or_invalid_w &&
                          (trace_unused_field_w || trace_x0_field_w);
wire [2:0] trace_ledger_code_w =
       trace_blanket_w    ? 3'd0 :
       trace_mixed_raw_w  ? 3'd3 :
       trace_load_raw_w   ? 3'd1 :
       trace_mul_raw_w    ? 3'd2 :
       trace_waw_w        ? 3'd4 :
       trace_false_only_w ? 3'd5 : 3'd6;

reg [10:0] trace_class_seen_q;
reg [31:0] trace_sem_mismatch_q;
reg [63:0] trace_perf_total_q;
reg [63:0] trace_program_perf_total_q;
reg [63:0] trace_blanket_q;
reg [63:0] trace_blanket_load_q;
reg [63:0] trace_blanket_store_q;
reg [63:0] trace_blanket_load_mul_q;
reg [63:0] trace_blanket_load_div_q;
reg [63:0] trace_blanket_load_csr_q;
reg [63:0] trace_blanket_store_mul_q;
reg [63:0] trace_blanket_store_div_q;
reg [63:0] trace_blanket_store_csr_q;
reg [63:0] trace_blanket_load_mul_raw_q;
reg [63:0] trace_blanket_load_div_raw_q;
reg [63:0] trace_blanket_load_csr_raw_q;
reg [63:0] trace_blanket_store_mul_raw_q;
reg [63:0] trace_blanket_store_div_raw_q;
reg [63:0] trace_blanket_store_csr_raw_q;
reg [63:0] trace_blanket_load_mul_waw_q;
reg [63:0] trace_blanket_load_div_waw_q;
reg [63:0] trace_blanket_load_csr_waw_q;
reg [63:0] trace_blanket_store_mul_waw_q;
reg [63:0] trace_blanket_store_div_waw_q;
reg [63:0] trace_blanket_store_csr_waw_q;
reg [63:0] trace_unused_rs1_q;
reg [63:0] trace_unused_rs2_q;
reg [63:0] trace_invalid_rd_q;
reg [63:0] trace_x0_q;
reg [63:0] trace_load_raw_q;
reg [63:0] trace_mul_raw_q;
reg [63:0] trace_mixed_raw_q;
reg [63:0] trace_waw_q;
reg [63:0] trace_false_only_q;
reg [63:0] trace_x0_only_q;
reg [63:0] trace_other_q;
reg [63:0] trace_ledger_blanket_q;
reg [63:0] trace_ledger_load_raw_q;
reg [63:0] trace_ledger_mul_raw_q;
reg [63:0] trace_ledger_mixed_raw_q;
reg [63:0] trace_ledger_waw_q;
reg [63:0] trace_ledger_false_only_q;
reg [63:0] trace_ledger_other_q;

// The CoreMark port samples mhpmcounter3 before its start mcycle read and
// samples mcycle before its stop mhpmcounter3 read.  The first accepted
// mhpmcounter3 read is therefore the opening boundary; the second accepted
// mhpmcounter3 read is the closing boundary.  The mcycle reads are retained
// as ordering markers.  The gate is simulation-only and leaves the
// architectural/performance counter implementation untouched.
reg trace_window_start_seen_q;
reg trace_window_start_timestamp_seen_q;
reg trace_window_end_seen_q;
reg trace_window_active_q;
reg [63:0] trace_window_start_cycle_q;
reg [63:0] trace_window_end_cycle_q;
// HPM3 is sampled before the start mcycle read and after the stop mcycle
// read.  The architectural counter therefore includes a scoreboard event on
// either mcycle boundary when one is present; only the HPM3 opening edge and
// the post-stop cycles are outside the interval.
wire trace_window_count_w = trace_window_active_q;

integer trace_fd;
reg trace_run_active_q;
reg [63:0] trace_cycle_q;
reg [63:0] trace_run_start_q;
reg [63:0] trace_run_length_q;
reg [2:0] trace_run_code_q;
reg [31:0] trace_run_pc_q;
reg [31:0] trace_run_opcode_q;
reg [4:0] trace_run_ra_q;
reg [4:0] trace_run_rb_q;
reg [4:0] trace_run_rd_q;
reg trace_run_uses_rs1_q;
reg trace_run_uses_rs2_q;
reg trace_run_writes_rd_q;
reg [31:0] trace_run_scoreboard_q;
reg trace_run_blanket_q;
reg trace_run_blanket_load_q;
reg trace_run_blanket_store_q;
reg trace_run_load_raw_q;
reg trace_run_mul_raw_q;
reg trace_run_waw_q;
reg trace_run_false_only_q;
reg trace_run_pipe_load_e1_q;
reg trace_run_pipe_mul_e1_q;
reg [4:0] trace_run_pipe_rd_e1_q;
reg [31:0] trace_run_pipe_pc_e1_q;
reg [31:0] trace_run_pipe_opcode_e1_q;
reg trace_run_pipe_load_e2_q;
reg trace_run_pipe_mul_e2_q;
reg [4:0] trace_run_pipe_rd_e2_q;
reg [31:0] trace_run_pipe_result_e2_q;
reg trace_run_pipe_valid_wb_q;
reg [4:0] trace_run_pipe_rd_wb_q;
reg [31:0] trace_run_pipe_pc_wb_q;
reg [31:0] trace_run_pipe_opcode_wb_q;
reg [31:0] trace_run_pipe_result_wb_q;
reg [31:0] trace_run_exec_value_q;
reg trace_run_load_bypass_q;
reg trace_run_mul_bypass_q;
reg trace_run_backend_block_q;
reg trace_run_unused_rs1_q;
reg trace_run_unused_rs2_q;
reg trace_run_invalid_rd_q;
reg trace_run_x0_field_q;
reg trace_run_system_or_invalid_q;
reg trace_run_blanket_true_raw_q;
reg [6:0] trace_witness_mask_q;

initial begin
    trace_fd = $fopen("scoreboard_witness.csv", "w");
    if (trace_fd == 0)
        $fatal(1, "SCOREBOARD_TRACE cannot open scoreboard_witness.csv");
    $fwrite(trace_fd, "ledger_code,first_cycle,stall_cycles,issue_pc,issue_opcode,issue_ra,issue_rb,issue_rd,uses_rs1,uses_rs2,writes_rd,scoreboard_bits,blanket,blanket_load,blanket_store,load_raw,mul_raw,waw,false_only,pipe_load_e1,pipe_mul_e1,pipe_rd_e1,pipe_pc_e1,pipe_opcode_e1,pipe_load_e2,pipe_mul_e2,pipe_rd_e2,pipe_result_e2,pipe_valid_wb,pipe_rd_wb,pipe_pc_wb,pipe_opcode_wb,pipe_result_wb,exec_value,load_bypass,mul_bypass,backend_block,unused_rs1,unused_rs2,invalid_rd,x0_field,system_or_invalid,blanket_true_raw\n");
end

task trace_write_run;
begin
    if (trace_run_active_q && !trace_witness_mask_q[trace_run_code_q])
    begin
        $fwrite(trace_fd, "%0d,%0d,%0d,%08x,%08x,%0d,%0d,%0d,%0d,%0d,%0d,%08x,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%08x,%08x,%0d,%0d,%0d,%08x,%0d,%0d,%08x,%08x,%08x,%08x,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                trace_run_code_q, trace_run_start_q, trace_run_length_q,
                trace_run_pc_q, trace_run_opcode_q, trace_run_ra_q,
                trace_run_rb_q, trace_run_rd_q, trace_run_uses_rs1_q,
                trace_run_uses_rs2_q, trace_run_writes_rd_q,
                trace_run_scoreboard_q, trace_run_blanket_q,
                trace_run_blanket_load_q, trace_run_blanket_store_q,
                trace_run_load_raw_q, trace_run_mul_raw_q,
                trace_run_waw_q, trace_run_false_only_q,
                trace_run_pipe_load_e1_q, trace_run_pipe_mul_e1_q,
                trace_run_pipe_rd_e1_q, trace_run_pipe_pc_e1_q,
                trace_run_pipe_opcode_e1_q, trace_run_pipe_load_e2_q,
                trace_run_pipe_mul_e2_q, trace_run_pipe_rd_e2_q,
                trace_run_pipe_result_e2_q, trace_run_pipe_valid_wb_q,
                trace_run_pipe_rd_wb_q, trace_run_pipe_pc_wb_q,
                trace_run_pipe_opcode_wb_q, trace_run_pipe_result_wb_q,
                trace_run_exec_value_q, trace_run_load_bypass_q,
                trace_run_mul_bypass_q, trace_run_backend_block_q,
                trace_run_unused_rs1_q, trace_run_unused_rs2_q,
                 trace_run_invalid_rd_q, trace_run_x0_field_q,
                 trace_run_system_or_invalid_q, trace_run_blanket_true_raw_q);
    end
end
endtask

task trace_emit_run;
begin
    trace_write_run;
    if (trace_run_active_q && !trace_witness_mask_q[trace_run_code_q])
        trace_witness_mask_q[trace_run_code_q] <= 1'b1;
end
endtask

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    trace_class_seen_q        <= 11'b0;
    trace_sem_mismatch_q      <= 32'b0;
    trace_perf_total_q        <= 64'b0;
    trace_program_perf_total_q<= 64'b0;
    trace_blanket_q           <= 64'b0;
    trace_blanket_load_q      <= 64'b0;
    trace_blanket_store_q     <= 64'b0;
    trace_blanket_load_mul_q  <= 64'b0;
    trace_blanket_load_div_q  <= 64'b0;
    trace_blanket_load_csr_q  <= 64'b0;
    trace_blanket_store_mul_q <= 64'b0;
    trace_blanket_store_div_q <= 64'b0;
    trace_blanket_store_csr_q <= 64'b0;
    trace_blanket_load_mul_raw_q  <= 64'b0;
    trace_blanket_load_div_raw_q  <= 64'b0;
    trace_blanket_load_csr_raw_q  <= 64'b0;
    trace_blanket_store_mul_raw_q <= 64'b0;
    trace_blanket_store_div_raw_q <= 64'b0;
    trace_blanket_store_csr_raw_q <= 64'b0;
    trace_blanket_load_mul_waw_q  <= 64'b0;
    trace_blanket_load_div_waw_q  <= 64'b0;
    trace_blanket_load_csr_waw_q  <= 64'b0;
    trace_blanket_store_mul_waw_q <= 64'b0;
    trace_blanket_store_div_waw_q <= 64'b0;
    trace_blanket_store_csr_waw_q <= 64'b0;
    trace_unused_rs1_q       <= 64'b0;
    trace_unused_rs2_q       <= 64'b0;
    trace_invalid_rd_q       <= 64'b0;
    trace_x0_q               <= 64'b0;
    trace_load_raw_q          <= 64'b0;
    trace_mul_raw_q           <= 64'b0;
    trace_mixed_raw_q         <= 64'b0;
    trace_waw_q               <= 64'b0;
    trace_false_only_q        <= 64'b0;
    trace_x0_only_q           <= 64'b0;
    trace_other_q             <= 64'b0;
    trace_ledger_blanket_q    <= 64'b0;
    trace_ledger_load_raw_q   <= 64'b0;
    trace_ledger_mul_raw_q    <= 64'b0;
    trace_ledger_mixed_raw_q  <= 64'b0;
    trace_ledger_waw_q        <= 64'b0;
    trace_ledger_false_only_q <= 64'b0;
    trace_ledger_other_q      <= 64'b0;
    trace_window_start_seen_q <= 1'b0;
    trace_window_start_timestamp_seen_q <= 1'b0;
    trace_window_end_seen_q   <= 1'b0;
    trace_window_active_q     <= 1'b0;
    trace_window_start_cycle_q<= 64'b0;
    trace_window_end_cycle_q  <= 64'b0;
    trace_run_active_q        <= 1'b0;
    trace_cycle_q             <= 64'b0;
    trace_run_start_q         <= 64'b0;
    trace_run_length_q        <= 64'b0;
    trace_run_code_q          <= 3'b0;
    trace_witness_mask_q      <= 7'b0;
end
else
begin
    trace_cycle_q <= trace_cycle_q + 64'd1;

    // The CoreMark port takes the start HPM snapshot before its start-time
    // mcycle read, and takes the stop mcycle read before its stop HPM
    // snapshot.  Recognize those accepted CSR operations directly.  The
    // first mhpmcounter3 opens the observer; the first mcycle is the start
    // timestamp and the second mcycle closes it.  This is a simulation-only
    // gate and does not add a CSR access or alter the program timing.
    if (trace_snapshot_scoreboard_w && !trace_window_start_seen_q)
    begin
        trace_window_start_seen_q  <= 1'b1;
        trace_window_active_q      <= 1'b1;
        trace_window_start_cycle_q <= trace_cycle_q;
    end
    else if (trace_timestamp_w && trace_window_start_seen_q &&
             !trace_window_end_seen_q)
    begin
        if (!trace_window_start_timestamp_seen_q)
            trace_window_start_timestamp_seen_q <= 1'b1;
    end
    else if (trace_snapshot_scoreboard_w && trace_window_start_seen_q &&
             trace_window_start_timestamp_seen_q && !trace_window_end_seen_q)
    begin
        trace_window_end_seen_q  <= 1'b1;
        trace_window_active_q    <= 1'b0;
        trace_window_end_cycle_q <= trace_cycle_q;
    end

    if (opcode_valid_w)
    begin
        trace_class_seen_q <= trace_class_seen_q | trace_class(fetch_instr_i);
        if (!issue_invalid_w &&
            (issue_sb_alloc_w !== trace_sem_writes_rd_w))
            trace_sem_mismatch_q <= trace_sem_mismatch_q + 32'd1;
    end

    if (perf_scoreboard_stall_w)
        trace_program_perf_total_q <= trace_program_perf_total_q + 64'd1;

    if (trace_window_count_w && perf_scoreboard_stall_w)
    begin
        trace_perf_total_q <= trace_perf_total_q + 64'd1;
        if (trace_blanket_w)
        begin
            trace_blanket_q <= trace_blanket_q + 64'd1;
            if (pipe_load_e1_w)
                trace_blanket_load_q <= trace_blanket_load_q + 64'd1;
            if (pipe_store_e1_w)
                trace_blanket_store_q <= trace_blanket_store_q + 64'd1;
        end
        if (trace_blanket_load_mul_w)
        begin
            trace_blanket_load_mul_q <= trace_blanket_load_mul_q + 64'd1;
            if (trace_load_raw_w || trace_mul_raw_w)
                trace_blanket_load_mul_raw_q <= trace_blanket_load_mul_raw_q + 64'd1;
            if (trace_waw_w)
                trace_blanket_load_mul_waw_q <= trace_blanket_load_mul_waw_q + 64'd1;
        end
        if (trace_blanket_load_div_w)
        begin
            trace_blanket_load_div_q <= trace_blanket_load_div_q + 64'd1;
            if (trace_load_raw_w || trace_mul_raw_w)
                trace_blanket_load_div_raw_q <= trace_blanket_load_div_raw_q + 64'd1;
            if (trace_waw_w)
                trace_blanket_load_div_waw_q <= trace_blanket_load_div_waw_q + 64'd1;
        end
        if (trace_blanket_load_csr_w)
        begin
            trace_blanket_load_csr_q <= trace_blanket_load_csr_q + 64'd1;
            if (trace_load_raw_w || trace_mul_raw_w)
                trace_blanket_load_csr_raw_q <= trace_blanket_load_csr_raw_q + 64'd1;
            if (trace_waw_w)
                trace_blanket_load_csr_waw_q <= trace_blanket_load_csr_waw_q + 64'd1;
        end
        if (trace_blanket_store_mul_w)
        begin
            trace_blanket_store_mul_q <= trace_blanket_store_mul_q + 64'd1;
            if (trace_load_raw_w || trace_mul_raw_w)
                trace_blanket_store_mul_raw_q <= trace_blanket_store_mul_raw_q + 64'd1;
            if (trace_waw_w)
                trace_blanket_store_mul_waw_q <= trace_blanket_store_mul_waw_q + 64'd1;
        end
        if (trace_blanket_store_div_w)
        begin
            trace_blanket_store_div_q <= trace_blanket_store_div_q + 64'd1;
            if (trace_load_raw_w || trace_mul_raw_w)
                trace_blanket_store_div_raw_q <= trace_blanket_store_div_raw_q + 64'd1;
            if (trace_waw_w)
                trace_blanket_store_div_waw_q <= trace_blanket_store_div_waw_q + 64'd1;
        end
        if (trace_blanket_store_csr_w)
        begin
            trace_blanket_store_csr_q <= trace_blanket_store_csr_q + 64'd1;
            if (trace_load_raw_w || trace_mul_raw_w)
                trace_blanket_store_csr_raw_q <= trace_blanket_store_csr_raw_q + 64'd1;
            if (trace_waw_w)
                trace_blanket_store_csr_waw_q <= trace_blanket_store_csr_waw_q + 64'd1;
        end
        if (trace_unused_rs1_w)
            trace_unused_rs1_q <= trace_unused_rs1_q + 64'd1;
        if (trace_unused_rs2_w)
            trace_unused_rs2_q <= trace_unused_rs2_q + 64'd1;
        if (trace_invalid_rd_w)
            trace_invalid_rd_q <= trace_invalid_rd_q + 64'd1;
        if (trace_x0_field_w)
            trace_x0_q <= trace_x0_q + 64'd1;
        if (trace_load_raw_w)
            trace_load_raw_q <= trace_load_raw_q + 64'd1;
        if (trace_mul_raw_w)
            trace_mul_raw_q <= trace_mul_raw_q + 64'd1;
        if (trace_mixed_raw_w)
            trace_mixed_raw_q <= trace_mixed_raw_q + 64'd1;
        if (trace_waw_w)
            trace_waw_q <= trace_waw_q + 64'd1;
        if (trace_false_only_w)
        begin
            trace_false_only_q <= trace_false_only_q + 64'd1;
            if (trace_x0_field_w && !trace_unused_field_w)
                trace_x0_only_q <= trace_x0_only_q + 64'd1;
        end
        if (!trace_blanket_w && !trace_load_raw_w && !trace_mul_raw_w &&
            !trace_waw_w && !trace_false_only_w)
            trace_other_q <= trace_other_q + 64'd1;

        case (trace_ledger_code_w)
        3'd0: trace_ledger_blanket_q    <= trace_ledger_blanket_q + 64'd1;
        3'd1: trace_ledger_load_raw_q   <= trace_ledger_load_raw_q + 64'd1;
        3'd2: trace_ledger_mul_raw_q    <= trace_ledger_mul_raw_q + 64'd1;
        3'd3: trace_ledger_mixed_raw_q  <= trace_ledger_mixed_raw_q + 64'd1;
        3'd4: trace_ledger_waw_q        <= trace_ledger_waw_q + 64'd1;
        3'd5: trace_ledger_false_only_q <= trace_ledger_false_only_q + 64'd1;
        default: trace_ledger_other_q  <= trace_ledger_other_q + 64'd1;
        endcase

        if (!trace_run_active_q || trace_run_pc_q != fetch_pc_i ||
            trace_run_opcode_q != fetch_instr_i ||
            trace_run_code_q != trace_ledger_code_w)
        begin
            trace_emit_run;
            trace_run_active_q          <= 1'b1;
            trace_run_start_q           <= trace_cycle_q;
            trace_run_length_q          <= 64'd1;
            trace_run_code_q            <= trace_ledger_code_w;
            trace_run_pc_q              <= fetch_pc_i;
            trace_run_opcode_q          <= fetch_instr_i;
            trace_run_ra_q              <= issue_ra_idx_w;
            trace_run_rb_q              <= issue_rb_idx_w;
            trace_run_rd_q              <= issue_rd_idx_w;
            trace_run_uses_rs1_q        <= trace_sem_uses_rs1_w;
            trace_run_uses_rs2_q        <= trace_sem_uses_rs2_w;
            trace_run_writes_rd_q       <= trace_sem_writes_rd_w;
            trace_run_scoreboard_q      <= scoreboard_r;
            trace_run_blanket_q         <= trace_blanket_w;
            trace_run_blanket_load_q    <= pipe_load_e1_w;
            trace_run_blanket_store_q   <= pipe_store_e1_w;
            trace_run_load_raw_q        <= trace_load_raw_w;
            trace_run_mul_raw_q         <= trace_mul_raw_w;
            trace_run_waw_q             <= trace_waw_w;
            trace_run_false_only_q      <= trace_false_only_w;
            trace_run_pipe_load_e1_q    <= pipe_load_e1_w;
            trace_run_pipe_mul_e1_q     <= pipe_mul_e1_w;
            trace_run_pipe_rd_e1_q      <= pipe_rd_e1_w;
            trace_run_pipe_pc_e1_q      <= pipe_pc_e1_w;
            trace_run_pipe_opcode_e1_q  <= pipe_opcode_e1_w;
            trace_run_pipe_load_e2_q    <= pipe_load_e2_w;
            trace_run_pipe_mul_e2_q     <= pipe_mul_e2_w;
            trace_run_pipe_rd_e2_q      <= pipe_rd_e2_w;
            trace_run_pipe_result_e2_q  <= pipe_result_e2_w;
            trace_run_pipe_valid_wb_q   <= pipe_valid_wb_w;
            trace_run_pipe_rd_wb_q      <= pipe_rd_wb_w;
            trace_run_pipe_pc_wb_q      <= pipe_pc_wb_w;
            trace_run_pipe_opcode_wb_q  <= pipe_opc_wb_w;
            trace_run_pipe_result_wb_q  <= pipe_result_wb_w;
            trace_run_exec_value_q      <= writeback_exec_value_i;
            trace_run_load_bypass_q     <= SUPPORT_LOAD_BYPASS;
            trace_run_mul_bypass_q      <= SUPPORT_MUL_BYPASS;
            trace_run_backend_block_q   <= perf_backend_block_w;
            trace_run_unused_rs1_q      <= trace_unused_rs1_w;
            trace_run_unused_rs2_q      <= trace_unused_rs2_w;
            trace_run_invalid_rd_q      <= trace_invalid_rd_w;
            trace_run_x0_field_q        <= trace_x0_field_w;
            trace_run_system_or_invalid_q <= trace_system_or_invalid_w;
            trace_run_blanket_true_raw_q  <= trace_load_raw_w || trace_mul_raw_w;
        end
        else
            trace_run_length_q <= trace_run_length_q + 64'd1;
    end
    else if (trace_run_active_q)
    begin
        trace_emit_run;
        trace_run_active_q <= 1'b0;
    end
end

function [63:0] trace_perf_total; /*verilator public*/
begin trace_perf_total = trace_perf_total_q; end
endfunction
function [63:0] trace_program_perf_total; /*verilator public*/
begin trace_program_perf_total = trace_program_perf_total_q; end
endfunction
function [63:0] trace_blanket_count; /*verilator public*/
begin trace_blanket_count = trace_blanket_q; end
endfunction
function [63:0] trace_blanket_load_count; /*verilator public*/
begin trace_blanket_load_count = trace_blanket_load_q; end
endfunction
function [63:0] trace_blanket_store_count; /*verilator public*/
begin trace_blanket_store_count = trace_blanket_store_q; end
endfunction
function [63:0] trace_blanket_load_mul_count; /*verilator public*/
begin trace_blanket_load_mul_count = trace_blanket_load_mul_q; end
endfunction
function [63:0] trace_blanket_load_div_count; /*verilator public*/
begin trace_blanket_load_div_count = trace_blanket_load_div_q; end
endfunction
function [63:0] trace_blanket_load_csr_count; /*verilator public*/
begin trace_blanket_load_csr_count = trace_blanket_load_csr_q; end
endfunction
function [63:0] trace_blanket_store_mul_count; /*verilator public*/
begin trace_blanket_store_mul_count = trace_blanket_store_mul_q; end
endfunction
function [63:0] trace_blanket_store_div_count; /*verilator public*/
begin trace_blanket_store_div_count = trace_blanket_store_div_q; end
endfunction
function [63:0] trace_blanket_store_csr_count; /*verilator public*/
begin trace_blanket_store_csr_count = trace_blanket_store_csr_q; end
endfunction
function [63:0] trace_blanket_load_mul_raw_count; /*verilator public*/
begin trace_blanket_load_mul_raw_count = trace_blanket_load_mul_raw_q; end
endfunction
function [63:0] trace_blanket_load_div_raw_count; /*verilator public*/
begin trace_blanket_load_div_raw_count = trace_blanket_load_div_raw_q; end
endfunction
function [63:0] trace_blanket_load_csr_raw_count; /*verilator public*/
begin trace_blanket_load_csr_raw_count = trace_blanket_load_csr_raw_q; end
endfunction
function [63:0] trace_blanket_store_mul_raw_count; /*verilator public*/
begin trace_blanket_store_mul_raw_count = trace_blanket_store_mul_raw_q; end
endfunction
function [63:0] trace_blanket_store_div_raw_count; /*verilator public*/
begin trace_blanket_store_div_raw_count = trace_blanket_store_div_raw_q; end
endfunction
function [63:0] trace_blanket_store_csr_raw_count; /*verilator public*/
begin trace_blanket_store_csr_raw_count = trace_blanket_store_csr_raw_q; end
endfunction
function [63:0] trace_blanket_load_mul_waw_count; /*verilator public*/
begin trace_blanket_load_mul_waw_count = trace_blanket_load_mul_waw_q; end
endfunction
function [63:0] trace_blanket_load_div_waw_count; /*verilator public*/
begin trace_blanket_load_div_waw_count = trace_blanket_load_div_waw_q; end
endfunction
function [63:0] trace_blanket_load_csr_waw_count; /*verilator public*/
begin trace_blanket_load_csr_waw_count = trace_blanket_load_csr_waw_q; end
endfunction
function [63:0] trace_blanket_store_mul_waw_count; /*verilator public*/
begin trace_blanket_store_mul_waw_count = trace_blanket_store_mul_waw_q; end
endfunction
function [63:0] trace_blanket_store_div_waw_count; /*verilator public*/
begin trace_blanket_store_div_waw_count = trace_blanket_store_div_waw_q; end
endfunction
function [63:0] trace_blanket_store_csr_waw_count; /*verilator public*/
begin trace_blanket_store_csr_waw_count = trace_blanket_store_csr_waw_q; end
endfunction
function [63:0] trace_unused_rs1_count; /*verilator public*/
begin trace_unused_rs1_count = trace_unused_rs1_q; end
endfunction
function [63:0] trace_unused_rs2_count; /*verilator public*/
begin trace_unused_rs2_count = trace_unused_rs2_q; end
endfunction
function [63:0] trace_invalid_rd_count; /*verilator public*/
begin trace_invalid_rd_count = trace_invalid_rd_q; end
endfunction
function [63:0] trace_x0_count; /*verilator public*/
begin trace_x0_count = trace_x0_q; end
endfunction
function [63:0] trace_load_raw_count; /*verilator public*/
begin trace_load_raw_count = trace_load_raw_q; end
endfunction
function [63:0] trace_mul_raw_count; /*verilator public*/
begin trace_mul_raw_count = trace_mul_raw_q; end
endfunction
function [63:0] trace_mixed_raw_count; /*verilator public*/
begin trace_mixed_raw_count = trace_mixed_raw_q; end
endfunction
function [63:0] trace_waw_count; /*verilator public*/
begin trace_waw_count = trace_waw_q; end
endfunction
function [63:0] trace_false_only_count; /*verilator public*/
begin trace_false_only_count = trace_false_only_q; end
endfunction
function [63:0] trace_x0_only_count; /*verilator public*/
begin trace_x0_only_count = trace_x0_only_q; end
endfunction
function [63:0] trace_other_count; /*verilator public*/
begin trace_other_count = trace_other_q; end
endfunction
function [63:0] trace_ledger_blanket_count; /*verilator public*/
begin trace_ledger_blanket_count = trace_ledger_blanket_q; end
endfunction
function [63:0] trace_ledger_load_count; /*verilator public*/
begin trace_ledger_load_count = trace_ledger_load_raw_q; end
endfunction
function [63:0] trace_ledger_mul_count; /*verilator public*/
begin trace_ledger_mul_count = trace_ledger_mul_raw_q; end
endfunction
function [63:0] trace_ledger_mixed_count; /*verilator public*/
begin trace_ledger_mixed_count = trace_ledger_mixed_raw_q; end
endfunction
function [63:0] trace_ledger_waw_count; /*verilator public*/
begin trace_ledger_waw_count = trace_ledger_waw_q; end
endfunction
function [63:0] trace_ledger_false_count; /*verilator public*/
begin trace_ledger_false_count = trace_ledger_false_only_q; end
endfunction
function [63:0] trace_ledger_other_count; /*verilator public*/
begin trace_ledger_other_count = trace_ledger_other_q; end
endfunction
function [10:0] trace_class_seen; /*verilator public*/
begin trace_class_seen = trace_class_seen_q; end
endfunction
function [31:0] trace_sem_mismatch; /*verilator public*/
begin trace_sem_mismatch = trace_sem_mismatch_q; end
endfunction
function [6:0] trace_witness_mask; /*verilator public*/
begin trace_witness_mask = trace_witness_mask_q; end
endfunction
function [0:0] trace_window_start_seen; /*verilator public*/
begin trace_window_start_seen = trace_window_start_seen_q; end
endfunction
function [0:0] trace_window_end_seen; /*verilator public*/
begin trace_window_end_seen = trace_window_end_seen_q; end
endfunction
function [0:0] trace_window_active; /*verilator public*/
begin trace_window_active = trace_window_active_q; end
endfunction
function [63:0] trace_window_start_cycle; /*verilator public*/
begin trace_window_start_cycle = trace_window_start_cycle_q; end
endfunction
function [63:0] trace_window_end_cycle; /*verilator public*/
begin trace_window_end_cycle = trace_window_end_cycle_q; end
endfunction

final begin
    trace_write_run;
    if (trace_fd != 0)
        $fclose(trace_fd);
`ifdef ULTRA_SCOREBOARD_TRACE_REQUIRE_WINDOW
    if (!trace_window_start_seen_q || !trace_window_end_seen_q)
        $fatal(1, "SCOREBOARD_TRACE_WINDOW_NOT_CLOSED start=%0d end=%0d",
               trace_window_start_seen_q, trace_window_end_seen_q);
`endif
end

// One-shot dynamic consumer classification for the RAW feasibility study.
// This file is included only by the isolated simulation copy and does not
// participate in synthesis or in the accepted functional RTL.
`ifdef ULTRA_RAW_CONSUMER_BREAKDOWN
`include "raw_consumer_breakdown.vh"
`endif
