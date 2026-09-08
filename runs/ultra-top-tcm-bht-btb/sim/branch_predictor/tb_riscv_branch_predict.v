`timescale 1ns/1ps

// Closure unit test for the fixed 64-entry implementation.  Keep update
// addresses stable while update_valid_i is asserted and sample update_hit_o
// before the write clock edge; sampling after the edge cannot distinguish a
// replacement miss from a same-tag hit.
module tb_riscv_branch_predict;
    reg         clk_i;
    reg         rst_i;
    reg         invalidate_i;
    reg  [31:0] lookup_pc_i;
    wire        lookup_hit_o;
    wire        lookup_taken_o;
    wire [31:0] lookup_target_o;
    reg         update_valid_i;
    reg  [31:0] update_pc_i;
    reg  [31:0] update_target_i;
    reg         update_is_jal_i;
    reg         update_taken_i;
    wire        update_hit_o;
    wire        disabled_lookup_hit_w;
    wire        disabled_lookup_taken_w;
    wire [31:0] disabled_lookup_target_w;
    wire        disabled_update_hit_w;

    integer failures;

    riscv_branch_predict #(
        .SUPPORT_BRANCH_PREDICTION(1)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .invalidate_i(invalidate_i),
        .lookup_pc_i(lookup_pc_i),
        .lookup_hit_o(lookup_hit_o),
        .lookup_taken_o(lookup_taken_o),
        .lookup_target_o(lookup_target_o),
        .update_valid_i(update_valid_i),
        .update_pc_i(update_pc_i),
        .update_target_i(update_target_i),
        .update_is_jal_i(update_is_jal_i),
        .update_taken_i(update_taken_i),
        .update_hit_o(update_hit_o)
    );

    riscv_branch_predict #(
        .SUPPORT_BRANCH_PREDICTION(0)
    ) dut_disabled (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .invalidate_i(invalidate_i),
        .lookup_pc_i(lookup_pc_i),
        .lookup_hit_o(disabled_lookup_hit_w),
        .lookup_taken_o(disabled_lookup_taken_w),
        .lookup_target_o(disabled_lookup_target_w),
        .update_valid_i(update_valid_i),
        .update_pc_i(update_pc_i),
        .update_target_i(update_target_i),
        .update_is_jal_i(update_is_jal_i),
        .update_taken_i(update_taken_i),
        .update_hit_o(disabled_update_hit_w)
    );

    always #5 clk_i = ~clk_i;

    // A timeout is a test failure, not a successful simulator termination.
    initial begin
        #100000;
        $fatal(1, "TIMEOUT: riscv_branch_predict unit test");
    end

    task check;
        input condition;
        input [511:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task clear_update;
        begin
            update_valid_i = 1'b0;
            update_pc_i = 32'b0;
            update_target_i = 32'b0;
            update_is_jal_i = 1'b0;
            update_taken_i = 1'b0;
        end
    endtask

    // update_hit_o is deliberately checked while update_valid_i is high and
    // before posedge clk_i.  The caller supplies the expected pre-write hit.
    task update_expect;
        input [31:0] pc;
        input [31:0] target;
        input         is_jal;
        input         taken;
        input         expected_hit;
        input [511:0] message;
        begin
            @(negedge clk_i);
            update_valid_i = 1'b1;
            update_pc_i = pc;
            update_target_i = target;
            update_is_jal_i = is_jal;
            update_taken_i = taken;
            #1;
            check(update_hit_o === expected_hit, message);
            @(posedge clk_i);
            #1;
            clear_update();
        end
    endtask

    task update_conditional;
        input [31:0] pc;
        input         taken;
        input         expected_hit;
        input [511:0] message;
        begin
            update_expect(pc, pc + 32'd64, 1'b0, taken, expected_hit, message);
        end
    endtask

    task update_jal;
        input [31:0] pc;
        input [31:0] target;
        input         expected_hit;
        input [511:0] message;
        begin
            update_expect(pc, target, 1'b1, 1'b1, expected_hit, message);
        end
    endtask

    task lookup;
        input [31:0] pc;
        input         expected_hit;
        input         expected_taken;
        input [31:0] expected_target;
        input [511:0] message;
        begin
            lookup_pc_i = pc;
            #1;
            check(lookup_hit_o === expected_hit, message);
            check(lookup_taken_o === expected_taken, "lookup direction mismatch");
            check(lookup_target_o === expected_target, "lookup target mismatch");
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        invalidate_i = 1'b0;
        lookup_pc_i = 32'b0;
        failures = 0;
        clear_update();

        // Reset clears valid bits while the resetless RAM data is immaterial.
        repeat (2) @(posedge clk_i);
        #1;
        lookup(32'h0000_0010, 1'b0, 1'b0, 32'b0, "reset did not invalidate index 4");
        lookup(32'h0000_0000, 1'b0, 1'b0, 32'b0, "reset did not invalidate index 0");
        rst_i = 1'b0;

        // Index 4 allocation, then the complete 00/01/10/11 BHT trajectory.
        // First taken allocation is weakly taken (10).
        update_conditional(32'h0000_0010, 1'b1, 1'b0, "new allocation must report miss");
        lookup(32'h0000_0010, 1'b1, 1'b1, 32'h0000_0050, "index 4 allocation lookup");
        update_conditional(32'h0000_0010, 1'b1, 1'b1, "same tag taken update must hit");
        lookup(32'h0000_0010, 1'b1, 1'b1, 32'h0000_0050, "BHT did not reach 11");
        update_conditional(32'h0000_0010, 1'b1, 1'b1, "11 saturation update must hit");
        lookup(32'h0000_0010, 1'b1, 1'b1, 32'h0000_0050, "BHT 11 saturation changed direction");
        update_conditional(32'h0000_0010, 1'b0, 1'b1, "first not-taken decrement must hit");
        lookup(32'h0000_0010, 1'b1, 1'b1, 32'h0000_0050, "BHT 11 to 10 transition");
        update_conditional(32'h0000_0010, 1'b0, 1'b1, "second not-taken decrement must hit");
        lookup(32'h0000_0010, 1'b1, 1'b0, 32'h0000_0050, "BHT 10 to 01 transition");
        update_conditional(32'h0000_0010, 1'b0, 1'b1, "third not-taken decrement must hit");
        lookup(32'h0000_0010, 1'b1, 1'b0, 32'h0000_0050, "BHT 01 to 00 transition");
        update_conditional(32'h0000_0010, 1'b0, 1'b1, "00 saturation update must hit");
        lookup(32'h0000_0010, 1'b1, 1'b0, 32'h0000_0050, "BHT 00 saturation changed direction");

        // 0x10 and 0x50 are different indices in the real 64-entry table.
        update_conditional(32'h0000_0050, 1'b1, 1'b0, "0x50 must allocate at index 20");
        lookup(32'h0000_0050, 1'b1, 1'b1, 32'h0000_0090, "index 20 lookup");
        lookup(32'h0000_0010, 1'b1, 1'b0, 32'h0000_0050, "0x10 was aliased by 0x50");

        // 0x10 and 0x110 are the same index with different tags. Replacement
        // must be a miss and must re-seed history from the new outcome.
        update_conditional(32'h0000_0110, 1'b0, 1'b0, "same-index different-tag replacement must miss");
        lookup(32'h0000_0110, 1'b1, 1'b0, 32'h0000_0150, "replacement tag lookup");
        lookup(32'h0000_0010, 1'b0, 1'b0, 32'b0, "old tag survived replacement");
        update_conditional(32'h0000_0110, 1'b1, 1'b1, "replacement tag update must hit");
        lookup(32'h0000_0110, 1'b1, 1'b0, 32'h0000_0150, "replacement BHT 00 to 01 transition");
        update_conditional(32'h0000_0110, 1'b1, 1'b1, "replacement BHT second update must hit");
        lookup(32'h0000_0110, 1'b1, 1'b1, 32'h0000_0150, "replacement BHT 01 to 10 transition");

        // A high tag must participate in the compare, not just low address bits.
        update_conditional(32'h8000_0010, 1'b1, 1'b0, "high-tag alias must miss");
        lookup(32'h8000_0010, 1'b1, 1'b1, 32'h8000_0050, "high-tag lookup");
        lookup(32'h0000_0010, 1'b0, 1'b0, 32'b0, "low tag unexpectedly matched high tag");

        // Index zero and index 63 are independently addressable, including
        // high-tag aliases for each boundary entry.
        update_conditional(32'h0000_0000, 1'b1, 1'b0, "index 0 allocation");
        update_conditional(32'h0000_00fc, 1'b1, 1'b0, "index 63 allocation");
        lookup(32'h0000_0000, 1'b1, 1'b1, 32'h0000_0040, "index 0 lookup");
        lookup(32'h0000_00fc, 1'b1, 1'b1, 32'h0000_013c, "index 63 lookup");
        update_conditional(32'h0000_0100, 1'b0, 1'b0, "index 0 high-tag replacement");
        update_conditional(32'h0000_01fc, 1'b0, 1'b0, "index 63 high-tag replacement");
        lookup(32'h0000_0000, 1'b0, 1'b0, 32'b0, "index 0 old tag survived replacement");
        lookup(32'h0000_00fc, 1'b0, 1'b0, 32'b0, "index 63 old tag survived replacement");
        lookup(32'h0000_0100, 1'b1, 1'b0, 32'h0000_0140, "index 0 high-tag lookup");
        lookup(32'h0000_01fc, 1'b1, 1'b0, 32'h0000_023c, "index 63 high-tag lookup");

        // JAL ignores conditional BHT direction and remains taken on a hit.
        update_jal(32'h0000_0090, 32'h0000_00d0, 1'b0, "JAL allocation must miss");
        lookup(32'h0000_0090, 1'b1, 1'b1, 32'h0000_00d0, "JAL lookup");
        update_jal(32'h0000_0090, 32'h0000_00d0, 1'b1, "same-tag JAL update must hit");

        // FENCE.I/invalidate clears valid state for all entries.
        invalidate_i = 1'b1;
        @(posedge clk_i);
        #1;
        invalidate_i = 1'b0;
        lookup(32'h0000_0050, 1'b0, 1'b0, 32'b0, "invalidate did not clear index 20");
        lookup(32'h0000_0090, 1'b0, 1'b0, 32'b0, "invalidate did not clear JAL entry");

        // First not-taken allocation is strongly not-taken (00), proving
        // replacement/allocate initialization is based on the new outcome.
        update_conditional(32'h0000_0090, 1'b0, 1'b0, "post-invalidate allocation miss");
        lookup(32'h0000_0090, 1'b1, 1'b0, 32'h0000_00d0, "not-taken allocation was not 00");

        // Independent lookup/update addresses and no update-to-lookup bypass.
        lookup_pc_i = 32'h0000_0090;
        @(negedge clk_i);
        update_valid_i = 1'b1;
        update_pc_i = 32'h0000_0110;
        update_target_i = 32'h0000_0220;
        update_is_jal_i = 1'b0;
        update_taken_i = 1'b1;
        #1;
        check(lookup_hit_o === 1'b1, "independent lookup address was disturbed");
        check(update_hit_o === 1'b0, "same-index replacement was not a pre-edge miss");
        @(posedge clk_i);
        #1;
        clear_update();
        lookup(32'h0000_0110, 1'b1, 1'b1, 32'h0000_0220, "independent update did not commit");

        // Same-cycle lookup of a first-time update must not be combinationally
        // bypassed; the entry becomes visible only after the write edge.
        @(negedge clk_i);
        lookup_pc_i = 32'h0000_0210;
        update_valid_i = 1'b1;
        update_pc_i = 32'h0000_0210;
        update_target_i = 32'h0000_0250;
        update_is_jal_i = 1'b0;
        update_taken_i = 1'b1;
        #1;
        check(lookup_hit_o === 1'b0, "same-cycle lookup unexpectedly bypassed update");
        check(update_hit_o === 1'b0, "same-cycle first update must report miss");
        @(posedge clk_i);
        #1;
        clear_update();
        lookup(32'h0000_0210, 1'b1, 1'b1, 32'h0000_0250, "same-cycle update did not commit");

        // Predictor-off outputs remain safe zeroes even while the enabled
        // instance is being updated.
        check(disabled_lookup_hit_w === 1'b0, "disabled hit is not safe zero");
        check(disabled_lookup_taken_w === 1'b0, "disabled direction is not safe zero");
        check(disabled_lookup_target_w === 32'b0, "disabled target is not safe zero");
        check(disabled_update_hit_w === 1'b0, "disabled update hit is not safe zero");

        if (failures != 0)
            $fatal(1, "FAIL: riscv_branch_predict unit test failures=%0d", failures);
        else begin
            $display("PASS: riscv_branch_predict unit test");
            $finish(0);
        end
    end
endmodule
