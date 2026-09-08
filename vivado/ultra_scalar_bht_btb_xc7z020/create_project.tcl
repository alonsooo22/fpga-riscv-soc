set script_dir [file dirname [file normalize [info script]]]
set run_root [file normalize [file join $script_dir .. .. runs ultra-top-tcm-bht-btb]]
set core_dir [file join $run_root core riscv]
set top_dir [file join $run_root top_tcm_axi src_v]
set project_dir [file join $script_dir project]
set project_name ultra_scalar_top_tcm_xc7z020

create_project $project_name $project_dir -force -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set source_files [concat \
    [glob -nocomplain [file join $core_dir *.v]] \
    [glob -nocomplain [file join $top_dir *.v]]]
add_files -norecurse $source_files
add_files -fileset constrs_1 -norecurse [file join $script_dir ultra_top_tcm.xdc]

set_property top riscv_tcm_top [get_filesets sources_1]
set_property top_auto_set 0 [get_filesets sources_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
    -value {-mode out_of_context} -objects [get_runs synth_1]
update_compile_order -fileset sources_1

close_project
exit
