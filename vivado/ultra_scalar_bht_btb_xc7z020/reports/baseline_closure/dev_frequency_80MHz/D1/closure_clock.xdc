create_clock -name clk_i -period 12.500 [get_ports clk_i]
set_false_path -from [get_ports {rst_i rst_cpu_i}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk_i]
