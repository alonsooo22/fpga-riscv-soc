set script_dir [file dirname [file normalize [info script]]]
set run_root [file normalize [file join $script_dir .. .. runs ultra-top-tcm-bht-btb]]
set core_dir [file join $run_root core riscv]
set top_dir [file join $run_root top_tcm_axi src_v]
set report_dir [file join $script_dir reports impl_ooc_100mhz]

file mkdir $report_dir
set_param general.maxThreads 8

set original_dir [pwd]
cd $core_dir
read_verilog [glob -nocomplain *.v]
cd $top_dir
read_verilog [glob -nocomplain *.v]
cd $original_dir
read_xdc [file join $script_dir ultra_top_tcm.xdc]

synth_design -top riscv_tcm_top -part xc7z020clg400-1 -mode out_of_context
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force [file join $report_dir ultra_scalar_top_tcm_routed.dcp]
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -path_type full \
    -file [file join $report_dir critical_paths.rpt]
report_design_analysis -logic_level_distribution \
    -file [file join $report_dir logic_levels.rpt]
report_methodology -file [file join $report_dir methodology.rpt]

exit
