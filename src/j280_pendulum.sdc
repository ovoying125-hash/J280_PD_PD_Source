# 系统时钟五十兆赫兹；转换器输入按三个系统周期采样约束。
# 输入延迟采用典型数据延迟及板级估计，不代表全温压实测保证。
create_clock -name sys_clk -period 20.000 -waveform {0 10} [get_ports {clk_50m}]
set_input_delay -clock [get_clocks {sys_clk}] -max 30.000 [get_ports {adc_data_in[*] adc_otr}]
set_input_delay -clock [get_clocks {sys_clk}] -min 0.000 [get_ports {adc_data_in[*] adc_otr}]
set_multicycle_path 3 -setup -from [get_ports {adc_data_in[*] adc_otr}]
set_multicycle_path 2 -hold -from [get_ports {adc_data_in[*] adc_otr}]
