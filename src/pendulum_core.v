`default_nettype none
// 控制协调层：起摆状态机、双环调度、目标管理和保护判定独立于串口。
module pendulum_core #(parameter integer CLK_HZ=50000000,BAUD=115200)(
 input wire clk,rst_n,run_press,
 input wire [3:0] step_pulse,
 input wire negative_direction,reciprocal_enable,
 input wire [11:0] adc_code,
 input wire adc_sample,adc_link,
 input wire encoder_a,encoder_b,
 output wire motor_in1,motor_in2,motor_pwm,
 output wire uart_txd);
`include "fixed_parameters.vh"
localparam [1:0] OFF=0,SWING=1,BALANCE=2,FAULT=3;
reg [1:0] state;
reg [7:0] fault_reason;
reg [31:0] ms_count,run_ms,adc_age;
wire ms_tick=ms_count==CLK_HZ/1000-1;
always @(posedge clk or negedge rst_n)
 if(!rst_n)ms_count<=0;else ms_count<=ms_tick ? 0 : ms_count+1'b1;

// 编码器二为转臂反馈；起摆行程基于启动位置，平衡位置基于捕获位置。
wire signed [31:0] encoder_position;
wire encoder_bad;
quadrature_decoder u_encoder(.clk(clk),.rst_n(rst_n),.enc_a(encoder_a),.enc_b(encoder_b),
 .position(encoder_position),.invalid_transition(encoder_bad));
wire signed [31:0] physical_position=ENCODER_DIRECTION*encoder_position;
reg signed [31:0] swing_origin,balance_origin;
wire signed [31:0] position=physical_position-balance_origin;
wire signed [31:0] swing_position=physical_position-swing_origin;
wire travel_bad=state==SWING ? (swing_position>SWING_TRAVEL || swing_position< -SWING_TRAVEL) :
 (position>BALANCE_TRAVEL || position< -BALANCE_TRAVEL);

wire signed [12:0] filtered_angle;
wire filtered_valid;
angle_filter #(.ZERO_CODE(ZERO_CODE),.SPAN(WRAP_SPAN)) u_filter(
 .clk(clk),.rst_n(rst_n),.sample(adc_sample),.adc_code(adc_code),.angle(filtered_angle),.valid(filtered_valid));
wire signed [12:0] angle=ANGLE_DIRECTION*filtered_angle;
wire signed [13:0] raw_angle=$signed({2'b0,adc_code})-ZERO_CODE;
wire fallen=raw_angle>FALL_LIMIT || raw_angle< -FALL_LIMIT;
wire adc_bad=!adc_link || adc_age>=100;
wire running=state==SWING || state==BALANCE;
wire drive_enable=running && !adc_bad && !travel_bad && !(state==BALANCE && fallen);

// 三次交替冲击后允许滑行；接近直立或手扶稳定时由起摆模块给出捕获事件。
wire signed [15:0] swing_command;
wire captured,pulse_event,second_started;
wire [15:0] pulse_count;
swing_three_pulse #(.CLK_HZ(CLK_HZ),.MAX_PULSES(3)) u_swing(
 .clk(clk),.rst_n(rst_n),.enable(state==SWING),.sample_strobe(adc_sample),.adc_valid(adc_link),
 .adc_code(adc_code),.wrap_span(WRAP_SPAN[11:0]),.wrap_half_span(12'd825),
 .wrap_low_code(12'd0),.wrap_high_code(12'd1650),.bottom_code(BOTTOM_CODE[11:0]),
 .target_code(SWING_TARGET[11:0]),.upper_code(UPPER_CODE[11:0]),.bottom_window(BOTTOM_WINDOW[11:0]),.rearm_distance(REARM_DISTANCE[11:0]),
 .first_pwm(FIRST_PWM[15:0]),.pulse_ms(FIRST_MS[15:0]),.second_pwm(SECOND_PWM[15:0]),.second_ms(SECOND_MS[15:0]),
 .third_enable(1'b1),.third_pwm(THIRD_PWM[15:0]),.third_ms(THIRD_MS[15:0]),
 .upright_code(ZERO_CODE[11:0]),.capture_window(CAPTURE_WINDOW[11:0]),.command(swing_command),.done(captured),
 .pulse_event(pulse_event),.second_started(second_started),.pulse_count(pulse_count));

// 故障锁存后必须按键回到停止态，再次按键才重新起摆，禁止自动重启。
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin state<=OFF;fault_reason<=0;swing_origin<=0;balance_origin<=0;run_ms<=0;adc_age<=0;end
 else begin
  if(adc_sample)adc_age<=0;else if(ms_tick && adc_age<100)adc_age<=adc_age+1'b1;
  if(ms_tick && running)run_ms<=run_ms+1'b1;
  if(run_press)begin
   if(state!=OFF)begin state<=OFF;fault_reason<=0;end
   else if(!adc_bad)begin state<=SWING;swing_origin<=physical_position;balance_origin<=physical_position;run_ms<=0;end
  end else if(running)begin
   if(adc_bad)begin state<=FAULT;fault_reason<=1;end
   else if(travel_bad)begin state<=FAULT;fault_reason<=2;end
   else if(state==BALANCE && fallen)begin state<=FAULT;fault_reason<=3;end
   else if(state==SWING && run_ms>=30000)begin state<=FAULT;fault_reason<=4;end
   else if(state==SWING && captured)begin state<=BALANCE;balance_origin<=physical_position;end
  end
 end
end

// 固定目标配置只在上电时装载一次；串口不具备参数或目标修改通路。
reg configured;
always @(posedge clk or negedge rst_n)if(!rst_n)configured<=0;else configured<=1;
reg signed [31:0] user_target;
reg [11:0] tilt_limit;
wire target_valid;
wire signed [31:0] requested_target,reciprocal_center;
wire [15:0] requested_tilt;
wire reciprocal_active,range_blocked;
board_target_control u_target(.clk(clk),.rst_n(rst_n),.enable(state==BALANCE),.ms_tick(ms_tick),
 .step_pulse(step_pulse),.negative_direction(negative_direction),.reciprocal_enable(reciprocal_enable),
 .config_load(!configured),.config_data({SMALL_TILT[15:0],RECIP_INTERVAL[31:0],RECIP_AMPLITUDE[15:0],COUNTS_PER_REV[15:0]}),
 .current_target(user_target),.external_target_value(32'sd0),.external_target_accept(1'b0),
 .travel_limit(BALANCE_TRAVEL[15:0]),.small_step_limit(SMALL_TILT[15:0]),.large_step_limit(LARGE_TILT[15:0]),
 .request_valid(target_valid),.request_ready(1'b1),.request_target(requested_target),.request_tilt(requested_tilt),
 .reciprocal_active(reciprocal_active),.range_blocked(range_blocked),.reciprocal_center(reciprocal_center));
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin user_target<=0;tilt_limit<=SMALL_TILT;end
 else if(state!=BALANCE)begin user_target<=0;tilt_limit<=SMALL_TILT;end
 else if(target_valid)begin user_target<=requested_target;tilt_limit<=requested_tilt[11:0];end
end

// 外环每十毫秒计算一次位移差分，速度单位为计数每十毫秒、八位小数。
reg [3:0] outer_div;
reg signed [31:0] previous_position,velocity_q8;
reg outer_tick;
reg balance_d;
wire signed [63:0] velocity_sample=($signed(position)-$signed(previous_position))*64'sd256;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin outer_div<=0;previous_position<=0;velocity_q8<=0;outer_tick<=0;balance_d<=0;end
 else begin
  outer_tick<=0;balance_d<=state==BALANCE;
  if(!running || (state==BALANCE && !balance_d))begin outer_div<=0;previous_position<=position;velocity_q8<=0;end
  else if(ms_tick)begin
   if(outer_div==OUTER_MS-1)begin
    outer_div<=0;previous_position<=position;
    velocity_q8<=velocity_q8+((velocity_sample-velocity_q8)>>>1);outer_tick<=1;
   end else outer_div<=outer_div+1'b1;
  end
 end
end
wire signed [31:0] position_error=user_target-position;
wire signed [12:0] target_tilt;
wire outer_valid;
position_pd_native u_outer(.clk(clk),.rst_n(rst_n),.enable(state==BALANCE),.tick(outer_tick),
 .position_error(position_error[17:0]),.velocity_q8(velocity_q8),.kp_q16(OUTER_KP),.kd_q16(OUTER_KD),
 .tilt_limit(tilt_limit),.command(target_tilt),.valid(outer_valid));
wire signed [15:0] angle_command;
angle_pd #(.OUTPUT_LIMIT(PWM_LIMIT)) u_inner(.clk(clk),.rst_n(rst_n),.enable(state==BALANCE && drive_enable),.tick(filtered_valid),
 .measurement(angle),.target(target_tilt),.kp_q8(INNER_KP),.kd_q8(INNER_KD),.command(angle_command));

// 输出选择在驱动器之前统一完成，停止和保护条件直接封锁功率输出。
wire signed [15:0] applied=drive_enable ? (state==SWING ? swing_command : angle_command) : 16'sd0;
wire unused_stby;
tb6612_pwm #(.CLK_HZ(CLK_HZ)) u_motor(.clk(clk),.rst_n(rst_n),.enable(drive_enable),
 .command(applied),.in1(motor_in1),.in2(motor_in2),.pwm(motor_pwm),.stby(unused_stby));

// 遥测按二十毫秒周期主动上报，不订阅、不续约，不依赖上位机是否在线。
reg [4:0] monitor_div;
reg monitor_valid;
reg [231:0] monitor_payload;
wire monitor_ready;
wire [7:0] run_flags={4'd0,adc_link,drive_enable,state};
wire [7:0] board_flags={3'd0,state==BALANCE,range_blocked,reciprocal_active,reciprocal_enable,negative_direction};
wire signed [31:0] display_code=ZERO_CODE+filtered_angle;
wire [15:0] normalized_code=display_code<0 ? display_code+WRAP_SPAN : display_code>WRAP_SPAN ? display_code-WRAP_SPAN : display_code;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin monitor_div<=0;monitor_valid<=0;monitor_payload<=0;end
 else begin
  if(monitor_valid && monitor_ready)monitor_valid<=0;
  if(ms_tick)begin
   monitor_div<=monitor_div==MONITOR_MS-1 ? 0 : monitor_div+1'b1;
   if(monitor_div==MONITOR_MS-1 && !monitor_valid)begin
    monitor_payload<={board_flags,reciprocal_center,COUNTS_PER_REV[15:0],fault_reason,run_flags,
      normalized_code,applied,velocity_q8,position,user_target,user_target};
    monitor_valid<=1;
   end
  end
 end
end
uart_packet_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.MAX_PAYLOAD_BYTES(29)) u_telemetry(
 .clk(clk),.rst_n(rst_n),.frame_valid(monitor_valid),.frame_ready(monitor_ready),
 .frame_type(8'h39),.frame_length(8'd29),.frame_payload(monitor_payload),.uart_txd(uart_txd));
endmodule
`default_nettype wire
