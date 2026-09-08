if {[llength $argv] < 3 || [llength $argv] > 5} {
    puts "Usage: implement_param_sweep_ooc.tcl <A0|A1|D0|D1> <EXTRA_DECODE_STAGE> <SUPPORT_REGFILE_XILINX> ?clock_ns? ?report_subdir?"
    exit 2
}

set config_name [lindex $argv 0]
set extra_decode_stage [lindex $argv 1]
set support_regfile_xilinx [lindex $argv 2]
set clock_ns 10.000
set report_subdir param_sweep
if {[llength $argv] >= 4} {
    set clock_ns [lindex $argv 3]
}
if {[llength $argv] >= 5} {
    set report_subdir [lindex $argv 4]
}

if {![regexp {^(A0|A1|D0|D1)$} $config_name] ||
    ![regexp {^[01]$} $extra_decode_stage] ||
    ![regexp {^[01]$} $support_regfile_xilinx] ||
    ![string is double -strict $clock_ns] || $clock_ns <= 0 ||
    [string length $report_subdir] == 0} {
    puts "Invalid parameter-sweep configuration."
    exit 2
}

set script_dir [file dirname [file normalize [info script]]]
set run_root [file normalize [file join $script_dir .. .. runs ultra-top-tcm-bht-btb]]
set core_dir [file join $run_root core riscv]
set top_dir [file join $run_root top_tcm_axi src_v]
set report_dir [file join $script_dir reports $report_subdir $config_name]

file mkdir $report_dir
set_param general.maxThreads 8

puts "CONFIG=$config_name"
puts "EXTRA_DECODE_STAGE=$extra_decode_stage"
puts "SUPPORT_REGFILE_XILINX=$support_regfile_xilinx"
set support_branch_prediction [expr {$config_name eq "A1" || $config_name eq "D1"}]
puts "SUPPORT_BRANCH_PREDICTION=$support_branch_prediction"
puts "BRANCH_PREDICTOR_CAPACITY=64"
puts "PART=xc7z020clg400-1"
puts "CLOCK_NS=$clock_ns"

set original_dir [pwd]
cd $core_dir
read_verilog [glob -nocomplain *.v]
cd $top_dir
read_verilog [glob -nocomplain *.v]
cd $original_dir
if {abs($clock_ns - 10.000) < 0.0001} {
    read_xdc [file join $script_dir ultra_top_tcm.xdc]
} else {
    # Keep the original OOC clock-entry and reset exception semantics while
    # allowing a conservative development-frequency run to use its own
    # period. This is an implementation constraint, not a board measurement.
    set dynamic_xdc [file join $report_dir closure_clock.xdc]
    set xdc_handle [open $dynamic_xdc w]
    puts $xdc_handle "create_clock -name clk_i -period $clock_ns \[get_ports clk_i\]"
    puts $xdc_handle "set_false_path -from \[get_ports {rst_i rst_cpu_i}\]"
    puts $xdc_handle "set_property HD.CLK_SRC BUFGCTRL_X0Y0 \[get_ports clk_i\]"
    close $xdc_handle
    read_xdc $dynamic_xdc
}

set generics [list \
    "EXTRA_DECODE_STAGE=$extra_decode_stage" \
    "SUPPORT_REGFILE_XILINX=$support_regfile_xilinx" \
    "SUPPORT_BRANCH_PREDICTION=$support_branch_prediction"]

synth_design -top riscv_tcm_top -part xc7z020clg400-1 -mode out_of_context -generic $generics
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force [file join $report_dir ultra_scalar_top_tcm_${config_name}_routed.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -path_type full \
    -file [file join $report_dir critical_paths.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
# Vivado 2022.2 has no report_unconstrained_paths command and its
# report_timing command has no -unconstrained switch.  check_timing -verbose
# above is the supported unconstrained-path audit for this tool version.
report_drc -file [file join $report_dir drc.rpt]
report_design_analysis -logic_level_distribution \
    -file [file join $report_dir logic_levels.rpt]
report_methodology -file [file join $report_dir methodology.rpt]

exit
