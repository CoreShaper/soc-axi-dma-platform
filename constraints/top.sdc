# 时钟
create_clock -name clk -period 10 [get_ports clk]

# 输入延迟：8个 data_in 位，以及 en, rst_n
set_input_delay -clock clk 2 [get_ports data_in_0_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_1_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_2_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_3_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_4_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_5_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_6_] -add_delay
set_input_delay -clock clk 2 [get_ports data_in_7_] -add_delay

set_input_delay -clock clk 2 [get_ports en] -add_delay
set_input_delay -clock clk 2 [get_ports rst_n] -add_delay

# 输出延迟：8个 acc 位，以及 carry
set_output_delay -clock clk 3 [get_ports acc_0_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_1_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_2_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_3_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_4_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_5_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_6_] -add_delay
set_output_delay -clock clk 3 [get_ports acc_7_] -add_delay

set_output_delay -clock clk 3 [get_ports carry] -add_delay
