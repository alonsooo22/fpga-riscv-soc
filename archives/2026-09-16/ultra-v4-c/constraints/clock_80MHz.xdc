# Candidate-only OOC constraint for the next optimization experiments.
# Keep the original ultra_top_tcm.xdc (10.000 ns historical/F1 constraint)
# unchanged.  This file is the actual 80 MHz / 12.500 ns constraint used by
# F2 synthesis and any later routed candidate.
create_clock -name clk_i -period 12.500 [get_ports clk_i]
set_false_path -from [get_ports {rst_i rst_cpu_i}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk_i]
