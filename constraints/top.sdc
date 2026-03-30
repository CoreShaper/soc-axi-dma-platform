# 创建时钟，周期 10ns（100MHz）
create_clock -name clk -period 10 [get_ports clk]

# 输入延迟：外部信号在时钟沿后 2ns 到达
set_input_delay -clock clk 2 [get_ports data_in] -add_delay
set_input_delay -clock clk 2 [get_ports en] -add_delay
set_input_delay -clock clk 2 [get_ports rst_n] -add_delay

# 输出延迟：外部需要在时钟沿前 3ns 收到数据
set_output_delay -clock clk 3 [get_ports acc] -add_delay
set_output_delay -clock clk 3 [get_ports carry] -add_delay
