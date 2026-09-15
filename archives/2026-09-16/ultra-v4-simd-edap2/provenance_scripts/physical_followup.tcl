# One physical-only closure attempt from the existing routed candidate.
# No synthesis, RTL edits, clock changes, false paths or baseline overwrite.
set here [file dirname [file normalize [info script]]]
set old [file normalize [file join $here .. build vivado_ppa_12p5 simd_subset_v1_routed.dcp]]
set out [file join $here physical_followup]
file mkdir $out
set_param general.maxThreads 8
open_checkpoint $old
set period [get_property PERIOD [get_clocks clk_i]]
if {abs($period-12.5)>0.001} {error "Unexpected clock period $period"}
set f [open [file join $out contract.txt] w]
puts $f "input=$old\nclock_ns=$period\nrtl_changes=none\nnew_synthesis=none"
set endpoints [get_cells -hier -quiet -filter {NAME =~ *u_mul*result_e2_q_reg*}]
puts $f "mul_result_endpoints=[llength $endpoints]"
if {[llength $endpoints]} {
 report_timing -to $endpoints -max_paths 5 -path_type full -file [file join $out before_mul_paths.rpt]
}
set dot [get_cells -hier -quiet -filter {NAME =~ *g_dot2h* && REF_NAME == DSP48E1}]
puts $f "dot_dsp_cells=$dot"
if {[llength $dot]} {
 report_timing -through [get_pins -of_objects $dot -filter {DIRECTION == OUT}] -max_paths 5 -path_type full -file [file join $out before_dot_paths.rpt]
}
close $f
phys_opt_design -directive AggressiveExplore
route_design
write_checkpoint [file join $out optimized_routed.dcp]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $out timing_summary.rpt]
report_timing -max_paths 10 -path_type full -file [file join $out critical_paths.rpt]
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
report_drc -file [file join $out drc.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
close_design
