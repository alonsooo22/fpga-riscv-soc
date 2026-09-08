set script_dir [file dirname [file normalize [info script]]]
set run_root [file normalize [file join $script_dir .. .. runs ultra-top-tcm-bht-btb]]
set core_dir [file join $run_root core riscv]
set top_dir [file join $run_root top_tcm_axi src_v]
set report_dir [file join $script_dir reports synth_ooc]

file mkdir $report_dir

set original_dir [pwd]
cd $core_dir
read_verilog [glob -nocomplain *.v]
cd $top_dir
read_verilog [glob -nocomplain *.v]
cd $original_dir
read_xdc [file join $script_dir ultra_top_tcm.xdc]

synth_design -top riscv_tcm_top -part xc7z020clg400-1 -mode out_of_context
write_checkpoint -force [file join $report_dir ultra_top_tcm_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization.rpt]

exit
