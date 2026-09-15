//-----------------------------------------------------------------
// Ultra scalar direct-mapped branch predictor
//-----------------------------------------------------------------
// The table structure is a Verilog-2001 adaptation of the kas030
// branch_predictor.  It deliberately has asynchronous lookup and
// synchronous update so the Xilinx implementation can infer distributed RAM.
//-----------------------------------------------------------------

`timescale 1ns/1ps

module riscv_branch_predict
#(
     parameter SUPPORT_BRANCH_PREDICTION = 1
)
(
     input           clk_i
    ,input           rst_i
    ,input           invalidate_i

    ,input  [31:0]   lookup_pc_i
    ,output          lookup_hit_o
    ,output          lookup_taken_o
    ,output [31:0]   lookup_target_o

    ,input           update_valid_i
    ,input  [31:0]   update_pc_i
    ,input  [31:0]   update_target_i
    ,input           update_is_jal_i
    ,input           update_taken_i
    ,output          update_hit_o
);

// Capacity is deliberately an implementation invariant, not a public
// configuration knob.  The RAM64X1D instances below require six address
// bits, so the architectural mapping is always PC[7:2].  The accepted
// implementation uses the complete PC[31:8] tag.  ULTRA_BTB_SHORT_TAG is an
// isolated experiment only; it must never be enabled by the normal build.
localparam integer BTB_ENTRIES = 64;
localparam integer INDEX_W     = 6;
`ifdef ULTRA_BTB_SHORT_TAG
localparam integer TAG_W       = 8;
`else
localparam integer TAG_W       = 24;
`endif

generate
if (SUPPORT_BRANCH_PREDICTION)
begin: gen_predictor_enabled
    // The table data is intentionally resetless. Valid bits protect all
    // lookups until a corresponding entry has been synchronously allocated.
    // RAM64X1D is the Xilinx distributed-RAM primitive with one synchronous
    // write port and two asynchronous read addresses. It matches the
    // independent lookup/update reads required by this direct-mapped table.
    reg                                             btb_valid_q  [0:BTB_ENTRIES-1];

    wire [INDEX_W-1:0] lookup_index_w = lookup_pc_i[7:2];
    wire [INDEX_W-1:0] update_index_w = update_pc_i[7:2];
`ifdef ULTRA_BTB_SHORT_TAG
    wire [TAG_W-1:0] lookup_tag_w = lookup_pc_i[15:8];
    wire [TAG_W-1:0] update_tag_w = update_pc_i[15:8];
`else
    wire [TAG_W-1:0] lookup_tag_w = lookup_pc_i[31:8];
    wire [TAG_W-1:0] update_tag_w = update_pc_i[31:8];
`endif

    wire [5:0] lookup_addr_w = lookup_index_w;
    wire [5:0] update_addr_w = update_index_w;
    wire [1:0] bht_lookup_w;
    wire [1:0] bht_update_w;
    wire [TAG_W-1:0] btb_tag_lookup_w;
    wire [TAG_W-1:0] btb_tag_update_w;
    wire [31:0] btb_target_lookup_w;
    wire [31:0] btb_target_update_w;
    wire btb_is_jal_lookup_w;
    wire btb_is_jal_update_w;
    reg [1:0] bht_update_data_r;

    genvar g;
    for (g = 0; g < 32; g = g + 1)
    begin: gen_target_ram
        RAM64X1D target_bit
        (
             .DPO(btb_target_lookup_w[g])
            ,.SPO(btb_target_update_w[g])
            ,.A0(update_addr_w[0]), .A1(update_addr_w[1])
            ,.A2(update_addr_w[2]), .A3(update_addr_w[3])
            ,.A4(update_addr_w[4]), .A5(update_addr_w[5])
            ,.D(update_target_i[g])
            ,.DPRA0(lookup_addr_w[0]), .DPRA1(lookup_addr_w[1])
            ,.DPRA2(lookup_addr_w[2]), .DPRA3(lookup_addr_w[3])
            ,.DPRA4(lookup_addr_w[4]), .DPRA5(lookup_addr_w[5])
            ,.WCLK(clk_i), .WE(update_valid_i)
        );
    end
    for (g = 0; g < TAG_W; g = g + 1)
    begin: gen_tag_ram
        RAM64X1D tag_bit
        (
             .DPO(btb_tag_lookup_w[g])
            ,.SPO(btb_tag_update_w[g])
            ,.A0(update_addr_w[0]), .A1(update_addr_w[1])
            ,.A2(update_addr_w[2]), .A3(update_addr_w[3])
            ,.A4(update_addr_w[4]), .A5(update_addr_w[5])
            ,.D(update_tag_w[g])
            ,.DPRA0(lookup_addr_w[0]), .DPRA1(lookup_addr_w[1])
            ,.DPRA2(lookup_addr_w[2]), .DPRA3(lookup_addr_w[3])
            ,.DPRA4(lookup_addr_w[4]), .DPRA5(lookup_addr_w[5])
            ,.WCLK(clk_i), .WE(update_valid_i)
        );
    end
    for (g = 0; g < 2; g = g + 1)
    begin: gen_bht_ram
        RAM64X1D bht_bit
        (
             .DPO(bht_lookup_w[g])
            ,.SPO(bht_update_w[g])
            ,.A0(update_addr_w[0]), .A1(update_addr_w[1])
            ,.A2(update_addr_w[2]), .A3(update_addr_w[3])
            ,.A4(update_addr_w[4]), .A5(update_addr_w[5])
            ,.D(bht_update_data_r[g])
            ,.DPRA0(lookup_addr_w[0]), .DPRA1(lookup_addr_w[1])
            ,.DPRA2(lookup_addr_w[2]), .DPRA3(lookup_addr_w[3])
            ,.DPRA4(lookup_addr_w[4]), .DPRA5(lookup_addr_w[5])
            ,.WCLK(clk_i), .WE(update_valid_i)
        );
    end
    begin: gen_is_jal_ram
        RAM64X1D is_jal_bit
        (
             .DPO(btb_is_jal_lookup_w)
            ,.SPO(btb_is_jal_update_w)
            ,.A0(update_addr_w[0]), .A1(update_addr_w[1])
            ,.A2(update_addr_w[2]), .A3(update_addr_w[3])
            ,.A4(update_addr_w[4]), .A5(update_addr_w[5])
            ,.D(update_is_jal_i)
            ,.DPRA0(lookup_addr_w[0]), .DPRA1(lookup_addr_w[1])
            ,.DPRA2(lookup_addr_w[2]), .DPRA3(lookup_addr_w[3])
            ,.DPRA4(lookup_addr_w[4]), .DPRA5(lookup_addr_w[5])
            ,.WCLK(clk_i), .WE(update_valid_i)
        );
    end
    

    wire lookup_hit_w = btb_valid_q[lookup_index_w] &&
                        (btb_tag_lookup_w == lookup_tag_w);
    wire update_hit_w = btb_valid_q[update_index_w] &&
                        (btb_tag_update_w == update_tag_w);

    // BHT read-modify-write value. On a same-index replacement the history
    // is re-seeded; on a hit it saturates at 00/11 exactly as kas030 does.
    always @ *
    begin
        bht_update_data_r = bht_update_w;
        if (!update_hit_w)
        begin
            if (update_is_jal_i)
                bht_update_data_r = 2'b01;
            else if (update_taken_i)
                bht_update_data_r = 2'b10;
            else
                bht_update_data_r = 2'b00;
        end
        else if (!update_is_jal_i)
        begin
            if (update_taken_i && (bht_update_w != 2'b11))
                bht_update_data_r = bht_update_w + 2'b01;
            else if (!update_taken_i && (bht_update_w != 2'b00))
                bht_update_data_r = bht_update_w - 2'b01;
        end
    end

    assign lookup_hit_o    = lookup_hit_w;
    assign lookup_taken_o  = lookup_hit_w &&
                             (btb_is_jal_lookup_w || bht_lookup_w[1]);
    assign lookup_target_o = lookup_hit_w ? btb_target_lookup_w : 32'b0;
    assign update_hit_o    = update_valid_i && update_hit_w;

    integer i;
    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
    begin
        for (i = 0; i < BTB_ENTRIES; i = i + 1)
            btb_valid_q[i] <= 1'b0;
    end
    else if (invalidate_i)
    begin
        for (i = 0; i < BTB_ENTRIES; i = i + 1)
            btb_valid_q[i] <= 1'b0;
    end
    else if (update_valid_i)
    begin
        btb_valid_q[update_index_w]  <= 1'b1;
    end

`ifdef ULTRA_BTB_SHORT_TAG
`ifdef ULTRA_BTB_SHORT_TAG_WINDOW_CHECK
    // Update validity is an actual predictor-training handshake, so it is
    // safe to check the update PC here.  Lookup validity is owned by the
    // fetch/MMU handshake and is checked at riscv_core rather than by
    // treating every non-zero value on lookup_pc_i as a real fetch.
    always @ (posedge clk_i)
    if (!rst_i && update_valid_i && update_pc_i[31:16] != 16'h0000)
        $fatal(1, "SHORT_TAG_WINDOW_VIOLATION update_pc=0x%08x", update_pc_i);
`endif
`endif

end
else
begin: gen_predictor_disabled
    assign lookup_hit_o    = 1'b0;
    assign lookup_taken_o  = 1'b0;
    assign lookup_target_o = 32'b0;
    assign update_hit_o    = 1'b0;
end
endgenerate

endmodule

// Simulation model for the Xilinx distributed-RAM primitive used above.
// Vivado supplies the real RAM64X1D primitive during synthesis.
`ifdef verilator
module RAM64X1D
(
     output DPO
    ,output SPO
    ,input  A0, input A1, input A2, input A3, input A4, input A5
    ,input  D
    ,input  DPRA0, input DPRA1, input DPRA2, input DPRA3, input DPRA4, input DPRA5
    ,input  WCLK
    ,input  WE
);

    parameter INIT = 64'h0000000000000000;
    reg [63:0] mem;
    wire [5:0] read_addr = {A5, A4, A3, A2, A1, A0};
    wire [5:0] dual_read_addr = {DPRA5, DPRA4, DPRA3, DPRA2, DPRA1, DPRA0};

    assign SPO = mem[read_addr];
    assign DPO = mem[dual_read_addr];

    initial mem = INIT;

    always @ (posedge WCLK)
        if (WE)
            mem[read_addr] <= D;
endmodule
`endif
