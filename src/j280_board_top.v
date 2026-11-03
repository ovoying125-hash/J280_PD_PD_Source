`default_nettype none
// 板级顶层保留原引脚命名：电机驱动采用甲通道，转臂编码器采用第二组。
module j280_board_top #(parameter integer CLK_HZ=50000000,BAUD=115200)(
 input wire clk_50m,run_btn_n,key2_n,key3_n,key4_n,key5_n,dip_dir_n,dip_recip_n,
 input wire uart_rx,
 output wire uart_tx,
 input wire [9:0] adc_data_in,
 input wire adc_otr,
 output wire adc_clk,adc_oe_n,
 input wire enc1_a,enc1_b,enc2_a,enc2_b,
 output wire AN1,AN2,PWMA,BN1,BN2,PWMB);
// 配置完成后产生一毫秒复位，并经两级寄存器同步释放。
reg [31:0] power_count=0;
reg ready=0;
reg [1:0] release_sync=0;
always @(posedge clk_50m)begin
 if(!ready)begin
  if(power_count==CLK_HZ/1000-1)ready<=1;else power_count<=power_count+1'b1;
 end
 release_sync<={release_sync[0],ready};
end
wire rst_n=release_sync[1];
wire [3:0] steps,run_steps;
wire negative,reciprocal,unused_direction,unused_reciprocal;
board_input_panel #(.CLK_HZ(CLK_HZ)) u_panel(.clk(clk_50m),.rst_n(rst_n),
 .keys_n({key5_n,key4_n,key3_n,key2_n}),.direction_n(dip_dir_n),.reciprocal_n(dip_recip_n),
 .step_pulse(steps),.negative_direction(negative),.reciprocal_enable(reciprocal));
// 启停键复用相同的同步消抖逻辑，松开后才允许再次触发。
board_input_panel #(.CLK_HZ(CLK_HZ)) u_run(.clk(clk_50m),.rst_n(rst_n),
 .keys_n({3'b111,run_btn_n}),.direction_n(1'b1),.reciprocal_n(1'b1),
 .step_pulse(run_steps),.negative_direction(unused_direction),.reciprocal_enable(unused_reciprocal));
wire [11:0] adc_code;
wire adc_sample,adc_link;
// 量程溢出指示不参与停机；数字链路、样本超时和机械保护分别在控制层处理。
adc_3pa1030 #(.CLK_HZ(CLK_HZ),.IGNORE_OTR(1)) u_adc(.clk(clk_50m),.rst_n(rst_n),
 .adc_data_in(adc_data_in),.adc_otr(adc_otr),.adc_clk(adc_clk),.adc_oe_n(adc_oe_n),
 .sample_code(adc_code),.sample_strobe(adc_sample),.link_valid(adc_link));
pendulum_core #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_core(.clk(clk_50m),.rst_n(rst_n),
 .run_press(run_steps[0]),.step_pulse(steps),.negative_direction(negative),.reciprocal_enable(reciprocal),
 .adc_code(adc_code),.adc_sample(adc_sample),.adc_link(adc_link),.encoder_a(enc2_a),.encoder_b(enc2_b),
 .motor_in1(AN1),.motor_in2(AN2),.motor_pwm(PWMA),.uart_txd(uart_tx));
// 另一组驱动输出保持低电平；串口接收脚和第一组编码器脚保留接口但不参与逻辑。
assign BN1=0;assign BN2=0;assign PWMB=0;
endmodule
`default_nettype wire
