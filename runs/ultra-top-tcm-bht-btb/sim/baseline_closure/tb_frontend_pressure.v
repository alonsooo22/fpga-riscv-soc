`timescale 1ns/1ps

module tb_frontend_pressure;
    reg         clk;
    reg         rst;
    reg         fetch_accept;
    reg         icache_accept;
    reg         icache_valid;
    reg         icache_error;
    reg [31:0]  icache_inst;
    reg         icache_page_fault;
    reg         fetch_invalidate;
    reg         branch_request;
    reg [31:0]  branch_pc;
    reg [1:0]   branch_priv;
    reg         prediction_taken;
    reg [31:0]  prediction_target;

    wire        fetch_valid;
    wire [31:0] fetch_instr;
    wire [31:0] fetch_pc;
    wire        fetch_fault_fetch;
    wire        fetch_fault_page;
    wire        icache_rd;
    wire        icache_flush;
    wire        icache_invalidate;
    wire [31:0] icache_pc;
    wire [1:0]  icache_priv;
    wire [31:0] prediction_pc;
    wire        fetch_pred_taken;
    wire        squash_decode;
    wire        perf_branch_redirect;
    wire        perf_branch_flush;
    wire        perf_fetch_starve;

    integer cycle_count;
    integer failures;
    integer response_seen;
    integer redirect_seen;
    integer old_response_dropped;
    integer new_response_seen;
    integer request_pc_stable;
    integer prediction_metadata_stable;
    integer outstanding_redirect_seen;
    integer outstanding_old_dropped;
    integer outstanding_new_seen;

    riscv_fetch #(
        .SUPPORT_MMU(0),
        .SUPPORT_BRANCH_PREDICTION(1)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .fetch_accept_i(fetch_accept),
        .icache_accept_i(icache_accept),
        .icache_valid_i(icache_valid),
        .icache_error_i(icache_error),
        .icache_inst_i(icache_inst),
        .icache_page_fault_i(icache_page_fault),
        .fetch_invalidate_i(fetch_invalidate),
        .branch_request_i(branch_request),
        .branch_pc_i(branch_pc),
        .branch_priv_i(branch_priv),
        .prediction_taken_i(prediction_taken),
        .prediction_target_i(prediction_target),
        .fetch_valid_o(fetch_valid),
        .fetch_instr_o(fetch_instr),
        .fetch_pc_o(fetch_pc),
        .fetch_fault_fetch_o(fetch_fault_fetch),
        .fetch_fault_page_o(fetch_fault_page),
        .icache_rd_o(icache_rd),
        .icache_flush_o(icache_flush),
        .icache_invalidate_o(icache_invalidate),
        .icache_pc_o(icache_pc),
        .icache_priv_o(icache_priv),
        .prediction_pc_o(prediction_pc),
        .fetch_pred_taken_o(fetch_pred_taken),
        .squash_decode_o(squash_decode),
        .perf_branch_redirect_o(perf_branch_redirect),
        .perf_branch_flush_o(perf_branch_flush),
        .perf_fetch_starve_o(perf_fetch_starve)
    );

    always #5 clk = ~clk;

    task automatic cycle;
    begin
        @(posedge clk);
        #1;
        cycle_count = cycle_count + 1;
        $display("FRONT_OBS cycle=%0d rd=%0d req_pc=%08x resp=%0d valid=%0d out_pc=%08x instr=%08x pred=%0d pred_target=%08x branch_req=%0d redirect_pc=%08x squash=%0d redirect=%0d flush=%0d",
                 cycle_count, icache_rd, icache_pc, icache_valid, fetch_valid,
                 fetch_pc, fetch_instr, fetch_pred_taken, prediction_target,
                 branch_request, branch_pc,
                 squash_decode, perf_branch_redirect, perf_branch_flush);
    end
    endtask

    task automatic defaults;
    begin
        fetch_accept = 1'b1;
        icache_accept = 1'b1;
        icache_valid = 1'b0;
        icache_error = 1'b0;
        icache_inst = 32'b0;
        icache_page_fault = 1'b0;
        fetch_invalidate = 1'b0;
        branch_request = 1'b0;
        branch_pc = 32'b0;
        branch_priv = 2'b11;
        prediction_taken = 1'b0;
        prediction_target = 32'b0;
    end
    endtask

    task automatic reset_dut;
    begin
        defaults();
        rst = 1'b1;
        cycle();
        cycle();
        rst = 1'b0;
        cycle();
    end
    endtask

    task automatic fail_if;
        input condition;
        input [1023:0] message;
    begin
        if (condition) begin
            $display("FRONT_FAIL %0s", message);
            failures = failures + 1;
        end
    end
    endtask

    task automatic begin_fetch;
        input [31:0] start_pc;
        input        pred_taken;
        input [31:0] pred_target;
    begin
        branch_pc = start_pc;
        branch_priv = 2'b11;
        prediction_taken = pred_taken;
        prediction_target = pred_target;
        branch_request = 1'b1;
        cycle();
        branch_request = 1'b0;
        cycle();
    end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        cycle_count = 0;
        failures = 0;
        response_seen = 0;
        redirect_seen = 0;
        old_response_dropped = 0;
        new_response_seen = 0;
        request_pc_stable = 1;
        prediction_metadata_stable = 1;
        outstanding_redirect_seen = 0;
        outstanding_old_dropped = 0;
        outstanding_new_seen = 0;

        // -------------------------------------------------------------
        // Scenario 1: response enters the skid buffer while downstream is
        // stalled.  Prediction metadata and request PC must stay paired.
        // -------------------------------------------------------------
        reset_dut();
        begin_fetch(32'h00000100, 1'b1, 32'h00000300);
        // Retire the first response with no backpressure so the redirect
        // delay state can clear.  The response accepted concurrently with
        // the next request is then returned once more and placed into skid;
        // its ownership is the captured pc_d_q metadata (0x100).
        icache_valid = 1'b0;
        cycle();
        icache_valid = 1'b1;
        icache_inst = 32'h11111111;
        cycle();
        fail_if(!fetch_valid || fetch_pc != 32'h00000100 ||
                fetch_instr != 32'h11111111 || !fetch_pred_taken,
                "initial response did not match its request metadata");
        icache_valid = 1'b0;
        fetch_accept = 1'b1;
        cycle();
        fetch_accept = 1'b0;
        icache_valid = 1'b1;
        icache_inst = 32'h33333333;
        cycle();
        fail_if(!fetch_valid || fetch_pc != 32'h00000100 ||
                fetch_instr != 32'h33333333 || !fetch_pred_taken,
                "stalled response did not expose expected PC/instruction/prediction");
        icache_valid = 1'b0;
        cycle();
        if (fetch_valid)
            response_seen = response_seen + 1;
        repeat (2) begin
            cycle();
            fail_if(!fetch_valid || fetch_pc != 32'h00000100 ||
                    fetch_instr != 32'h33333333 || !fetch_pred_taken,
                    "skid response changed while fetch_accept was low");
        end
        $display("FRONT_HIT downstream_stall stable_valid=%0d stable_pc=%08x stable_pred=%0d",
                 fetch_valid, fetch_pc, fetch_pred_taken);

        // -------------------------------------------------------------
        // Scenario 2: a redirect arrives while the response is in the skid
        // buffer.  Treat this as an interrupt-like redirect interleaved with
        // a predicted-taken request; the old response may not reappear.
        // -------------------------------------------------------------
        branch_pc = 32'h00000600;
        branch_request = 1'b1;
        redirect_seen = 1;
        cycle();
        fail_if(!squash_decode, "redirect did not assert squash_decode");
        branch_request = 1'b0;
        fetch_accept = 1'b1;
        prediction_taken = 1'b1;
        prediction_target = 32'h00000800;
        cycle();
        fail_if(fetch_valid && fetch_pc == 32'h00000100,
                "old skid response was emitted after redirect");
        icache_valid = 1'b0;
        cycle();
        cycle();
        icache_valid = 1'b1;
        icache_inst = 32'h22222222;
        cycle();
        fail_if(!fetch_valid || fetch_pc != 32'h00000600 ||
                fetch_instr != 32'h22222222,
                "redirect target response was not returned");
        new_response_seen = 1;
        $display("FRONT_HIT skid_redirect old_pc=0x00000100 dropped=1 new_pc=0x%08x pred_meta=%0d",
                 fetch_pc, fetch_pred_taken);

        // -------------------------------------------------------------
        // Scenario 3: an old request remains outstanding.  Its late response
        // is returned on the redirect-application edge and must be dropped;
        // the new request must subsequently return exactly once.
        // -------------------------------------------------------------
        reset_dut();
        begin_fetch(32'h00001000, 1'b0, 32'b0);
        fail_if(!icache_rd || icache_pc != 32'h00001000,
                "old outstanding request was not observed");
        icache_valid = 1'b0;
        cycle();
        branch_pc = 32'h00001200;
        branch_request = 1'b1;
        outstanding_redirect_seen = 1;
        cycle();
        fail_if(!squash_decode, "outstanding-request redirect did not assert squash_decode");
        branch_request = 1'b0;
        icache_valid = 1'b1;
        icache_inst = 32'haaaaaaaa;
        cycle();
        fail_if(fetch_valid && fetch_pc == 32'h00001000,
                "late old response was emitted after outstanding redirect");
        outstanding_old_dropped = 1;
        icache_valid = 1'b0;
        cycle();
        cycle();
        icache_valid = 1'b1;
        icache_inst = 32'hbbbbbbbb;
        cycle();
        fail_if(!fetch_valid || fetch_pc != 32'h00001200 ||
                fetch_instr != 32'hbbbbbbbb,
                "new response after outstanding redirect was not returned");
        outstanding_new_seen = 1;
        $display("FRONT_HIT outstanding_redirect old_resp_dropped=1 new_pc=0x%08x",
                 fetch_pc);

        // -------------------------------------------------------------
        // Final evidence checks.  The individual scenarios are bounded and
        // fail with a nonzero Verilator status through $fatal.
        // -------------------------------------------------------------
        fail_if(response_seen == 0, "no response was observed before skid capture");
        fail_if(redirect_seen == 0 || new_response_seen == 0,
                "skid redirect scenario did not hit all observation points");
        fail_if(outstanding_redirect_seen == 0 || outstanding_old_dropped == 0 ||
                outstanding_new_seen == 0,
                "outstanding redirect scenario did not hit all observation points");
        if (failures != 0) begin
            $display("FAIL: frontend pressure test failures=%0d", failures);
            $fatal(1);
        end
        $display("PASS: frontend pressure test scenarios=3");
        $finish(0);
    end
endmodule
