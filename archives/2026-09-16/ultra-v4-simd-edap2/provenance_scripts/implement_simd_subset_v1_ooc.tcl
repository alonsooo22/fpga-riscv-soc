# Isolated PPA flow for the four-instruction SIMD subset candidate.
# The accepted E-TCM v4 tree and its reports are not modified.
# argv: synth (default) or route

if {[llength $argv] > 1} {
    puts "Usage: implement_simd_subset_v1_ooc.tcl ?synth|route?"
    exit 2
}
set mode synth
if {[llength $argv] == 1} {
    set mode [string tolower [lindex $argv 0]]
}
if {$mode ni {synth route}} {
    puts "Invalid mode: $mode"
    exit 2
}

set script_dir [file dirname [file normalize [info script]]]
set candidate_dir [file normalize [file join $script_dir ..]]
set core_dir [file join $candidate_dir core riscv]
set top_dir [file join $candidate_dir top_tcm_axi src_v]
set followup_dir [file normalize [file join $candidate_dir .. ..]]
set xdc_file [file join $followup_dir rtl ultra_top_tcm_80MHz.xdc]
set report_dir [file join $candidate_dir build vivado_ppa_12p5]
file mkdir $report_dir
set_param general.maxThreads 8

puts "SIMD_SUBSET_IMPLEMENTATION=isolated_v1"
puts "MODE=$mode"
puts "PART=xc7z020clg400-1"
puts "CLOCK_NS=12.500"
puts "CANDIDATE_DIR=$candidate_dir"
puts "XDC=$xdc_file"

proc record_and_check_clock {path expected_period} {
    set clocks [get_clocks -quiet]
    if {[llength $clocks] == 0} {
        error "No clock object exists after constraints/checkpoint load"
    }
    set clock [lindex $clocks 0]
    set name [get_property NAME $clock]
    set period [get_property PERIOD $clock]
    set period_value [expr {double($period)}]
    if {[expr {abs($period_value - $expected_period) > 0.001}]} {
        error "Clock $name PERIOD=$period_value ns, expected $expected_period ns"
    }
    set fd [open $path w]
    puts $fd "clock_name=$name"
    puts $fd "period_ns=$period_value"
    puts $fd "period_mhz=[expr {1000.0 / $period_value}]"
    close $fd
    puts "CLOCK_QUERY name=$name period_ns=$period_value period_mhz=[expr {1000.0 / $period_value}]"
}

if {$mode eq "route"} {
    set synth_dcp [file join $report_dir simd_subset_v1_synth.dcp]
    open_checkpoint $synth_dcp
    record_and_check_clock [file join $report_dir simd_subset_v1_route_clock_query.txt] 12.5
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force [file join $report_dir simd_subset_v1_routed.dcp]
    report_utilization -file [file join $report_dir simd_subset_v1_route_utilization.rpt]
    report_utilization -hierarchical -file [file join $report_dir simd_subset_v1_route_utilization_hierarchical.rpt]
    report_timing_summary -delay_type min_max -max_paths 30 \
        -file [file join $report_dir simd_subset_v1_route_timing_summary.rpt]
    report_timing -delay_type max -max_paths 30 -path_type full \
        -file [file join $report_dir simd_subset_v1_route_critical_paths.rpt]
    report_timing -delay_type min -max_paths 30 -path_type full \
        -file [file join $report_dir simd_subset_v1_route_hold_paths.rpt]
    report_clock_utilization -file [file join $report_dir simd_subset_v1_route_clock_utilization.rpt]
    report_clock_interaction -file [file join $report_dir simd_subset_v1_route_clock_interaction.rpt]
    check_timing -verbose -file [file join $report_dir simd_subset_v1_route_check_timing.rpt]
    report_drc -file [file join $report_dir simd_subset_v1_route_drc.rpt]
    report_design_analysis -logic_level_distribution \
        -file [file join $report_dir simd_subset_v1_route_logic_levels.rpt]
    report_methodology -file [file join $report_dir simd_subset_v1_route_methodology.rpt]
    set manifest [open [file join $report_dir route_manifest.txt] w]
    puts $manifest "candidate=ultra_simd_subset_v1"
    puts $manifest "mode=route"
    puts $manifest "support_xbextu=1"
    puts $manifest "support_xpack16=1"
    puts $manifest "support_xdot2h=1"
    puts $manifest "support_xadd16=1"
    puts $manifest "extra_decode_stage=1"
    puts $manifest "support_regfile_xilinx=1"
    puts $manifest "support_branch_prediction=1"
    puts $manifest "support_early_tcm_load=1"
    puts $manifest "clock_ns=12.500"
    puts $manifest "part=xc7z020clg400-1"
    puts $manifest "source_root=$candidate_dir"
    puts $manifest "constraint_file=$xdc_file"
    puts $manifest "vivado_version=[version -short]"
    close $manifest
    close_design
    exit
}

set original_dir [pwd]
cd $core_dir
set core_sources [glob -nocomplain *.v]
read_verilog $core_sources
cd $top_dir
set top_sources [glob -nocomplain *.v]
read_verilog $top_sources
cd $original_dir
read_xdc $xdc_file

set generics [list \
    "SUPPORT_XBEXTU=1" \
    "SUPPORT_XPACK16=1" \
    "SUPPORT_XDOT2H=1" \
    "SUPPORT_XADD16=1" \
    "EXTRA_DECODE_STAGE=1" \
    "SUPPORT_REGFILE_XILINX=1" \
    "SUPPORT_BRANCH_PREDICTION=1" \
    "SUPPORT_EARLY_TCM_LOAD=1"]

synth_design -top riscv_tcm_top -part xc7z020clg400-1 \
    -mode out_of_context -generic $generics
record_and_check_clock [file join $report_dir simd_subset_v1_synth_clock_query.txt] 12.5
write_checkpoint -force [file join $report_dir simd_subset_v1_synth.dcp]
report_utilization -file [file join $report_dir simd_subset_v1_synth_utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir simd_subset_v1_synth_utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 30 \
    -file [file join $report_dir simd_subset_v1_synth_timing_summary.rpt]
report_timing -delay_type max -max_paths 30 -path_type full \
    -file [file join $report_dir simd_subset_v1_synth_critical_paths.rpt]
check_timing -verbose -file [file join $report_dir simd_subset_v1_synth_check_timing.rpt]

set manifest [open [file join $report_dir synth_manifest.txt] w]
puts $manifest "candidate=ultra_simd_subset_v1"
puts $manifest "mode=synth"
puts $manifest "support_xbextu=1"
puts $manifest "support_xpack16=1"
puts $manifest "support_xdot2h=1"
puts $manifest "support_xadd16=1"
puts $manifest "extra_decode_stage=1"
puts $manifest "support_regfile_xilinx=1"
puts $manifest "support_branch_prediction=1"
puts $manifest "support_early_tcm_load=1"
puts $manifest "clock_ns=12.500"
puts $manifest "part=xc7z020clg400-1"
puts $manifest "source_root=$candidate_dir"
puts $manifest "constraint_file=$xdc_file"
puts $manifest "vivado_version=[version -short]"
close $manifest

close_design
exit
