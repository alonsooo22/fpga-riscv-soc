create_clock -name clk_i -period 10.000 [get_ports clk_i]
set_false_path -from [get_ports {rst_i rst_cpu_i}]

# OOC clock-entry location for realistic clock delay/skew modelling on XC7Z020.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk_i]
