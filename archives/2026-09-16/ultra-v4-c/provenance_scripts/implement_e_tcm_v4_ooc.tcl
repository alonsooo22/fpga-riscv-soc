# Isolated E-TCM v4 80 MHz XC7Z020 OOC implementation.
# This script reads only sim/early_tcm_e_tcm_v4 and writes only the v4
# candidate report directory. Accepted D1 and E-TCM v1/v2/v3 products are untouched.
# argv: synth (default) or route. Route reuses the v4 synth checkpoint.

if {[llength $argv] > 1} {
    puts "Usage: implement_e_tcm_v4_ooc.tcl ?synth|route?"
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
set followup_dir [file normalize [file join $script_dir .. ..]]
set experiment_dir [file join $followup_dir sim early_tcm_e_tcm_v4]
set report_dir [file join $followup_dir reports early_tcm_e_tcm_v4 vivado_post_v4]
set core_dir [file join $experiment_dir core riscv]
set top_dir [file join $experiment_dir top_tcm_axi src_v]
set xdc_file [file join $followup_dir rtl ultra_top_tcm_80MHz.xdc]
file mkdir $report_dir
set_param general.maxThreads 8

puts "E_TCM_IMPLEMENTATION=isolated_v4"
puts "MODE=$mode"
puts "PART=xc7z020clg400-1"
puts "CLOCK_NS=12.500"
puts "SUPPORT_EARLY_TCM_LOAD=1"
puts "CORE_DIR=$core_dir"
puts "TOP_DIR=$top_dir"
puts "XDC=$xdc_file"

if {![file isdirectory $core_dir] || ![file isdirectory $top_dir] ||
    ![file isfile $xdc_file]} {
    puts "E-TCM v4 source or constraint directory is missing"
    exit 3
}

proc record_and_check_clock {path expected_period} {
    set clocks [get_clocks -quiet]
    if {[llength $clocks] == 0} {
        error "No clock object exists after constraints/checkpoint load"
    }
    set clock [lindex $clocks 0]
    set name [get_property NAME $clock]
    set period [get_property PERIOD $clock]
    if {$period eq ""} {
        error "Clock $name has no PERIOD property"
    }
    set period_value [expr {double($period)}]
    if {[expr {abs($period_value - $expected_period) > 0.001}]} {
        error "Clock $name PERIOD=$period_value ns, expected $expected_period ns"
    }
    set fd [open $path w]
    puts $fd "clock_name=$name"
    puts $fd "period_ns=$period_value"
    puts $fd "period_mhz=[expr {1000.0 / $period_value}]"
    puts $fd "clock_object=[get_property NAME $clock]"
    close $fd
    puts "CLOCK_QUERY name=$name period_ns=$period_value period_mhz=[expr {1000.0 / $period_value}]"
}

if {$mode eq "route"} {
    set synth_dcp [file join $report_dir e_tcm_v4_synth.dcp]
    if {![file isfile $synth_dcp]} {
        error "E-TCM v4 synth checkpoint is missing: $synth_dcp"
    }
    open_checkpoint $synth_dcp
    record_and_check_clock [file join $report_dir e_tcm_v4_routed_clock_query.txt] 12.5
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force [file join $report_dir e_tcm_v4_routed.dcp]
    report_utilization -file [file join $report_dir e_tcm_v4_routed_utilization.rpt]
    report_utilization -hierarchical -file [file join $report_dir e_tcm_v4_routed_utilization_hierarchical.rpt]
    report_timing_summary -delay_type min_max -max_paths 30 \
        -file [file join $report_dir e_tcm_v4_routed_timing_summary.rpt]
    report_timing -delay_type max -max_paths 30 -path_type full \
        -file [file join $report_dir e_tcm_v4_routed_critical_paths.rpt]
    report_timing -delay_type min -max_paths 30 -path_type full \
        -file [file join $report_dir e_tcm_v4_routed_hold_paths.rpt]
    report_clock_utilization -file [file join $report_dir e_tcm_v4_routed_clock_utilization.rpt]
    report_clock_interaction -file [file join $report_dir e_tcm_v4_routed_clock_interaction.rpt]
    check_timing -verbose -file [file join $report_dir e_tcm_v4_routed_check_timing.rpt]
    report_drc -file [file join $report_dir e_tcm_v4_routed_drc.rpt]
    report_design_analysis -logic_level_distribution \
        -file [file join $report_dir e_tcm_v4_routed_logic_levels.rpt]
    report_methodology -file [file join $report_dir e_tcm_v4_routed_methodology.rpt]
    set manifest [open [file join $report_dir routed_manifest.txt] w]
    puts $manifest "candidate=E-TCM-v4"
    puts $manifest "mode=route"
    puts $manifest "extra_decode_stage=1"
    puts $manifest "support_regfile_xilinx=1"
    puts $manifest "support_branch_prediction=1"
    puts $manifest "support_early_tcm_load=1"
    puts $manifest "clock_ns=12.500"
    puts $manifest "part=xc7z020clg400-1"
    puts $manifest "source_root=$experiment_dir"
    puts $manifest "constraint_file=$xdc_file"
    puts $manifest "vivado_version=[version -short]"
    close $manifest
    close_design
    exit
}

set original_dir [pwd]
cd $core_dir
set core_sources [glob -nocomplain *.v]
if {[llength $core_sources] == 0} {
    puts "No E-TCM v4 core sources found"
    exit 3
}
read_verilog $core_sources
cd $top_dir
set top_sources [glob -nocomplain *.v]
if {[llength $top_sources] == 0} {
    puts "No E-TCM v4 top sources found"
    exit 3
}
read_verilog $top_sources
cd $original_dir

read_xdc $xdc_file

set generics [list \
    "EXTRA_DECODE_STAGE=1" \
    "SUPPORT_REGFILE_XILINX=1" \
    "SUPPORT_BRANCH_PREDICTION=1" \
    "SUPPORT_EARLY_TCM_LOAD=1"]

synth_design -top riscv_tcm_top -part xc7z020clg400-1 \
    -mode out_of_context -generic $generics
record_and_check_clock [file join $report_dir e_tcm_v4_synth_clock_query.txt] 12.5
write_checkpoint -force [file join $report_dir e_tcm_v4_synth.dcp]
report_utilization -file [file join $report_dir e_tcm_v4_synth_utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir e_tcm_v4_synth_utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 30 \
    -file [file join $report_dir e_tcm_v4_synth_timing_summary.rpt]
report_timing -delay_type max -max_paths 30 -path_type full \
    -file [file join $report_dir e_tcm_v4_synth_critical_paths.rpt]
check_timing -verbose -file [file join $report_dir e_tcm_v4_synth_check_timing.rpt]

set manifest [open [file join $report_dir synth_manifest.txt] w]
puts $manifest "candidate=E-TCM-v4"
puts $manifest "mode=synth"
puts $manifest "extra_decode_stage=1"
puts $manifest "support_regfile_xilinx=1"
puts $manifest "support_branch_prediction=1"
puts $manifest "support_early_tcm_load=1"
puts $manifest "clock_ns=12.500"
puts $manifest "part=xc7z020clg400-1"
puts $manifest "source_root=$experiment_dir"
puts $manifest "constraint_file=$xdc_file"
puts $manifest "vivado_version=[version -short]"
close $manifest

close_design
exit
