// 三次交替冲击起摆：最低点启动、离开后回底反冲、再次回底进行第三次冲击。
// 对换圈跳变设置拒绝窗口；接近直立连续确认或手扶稳定均可提前接管。
`default_nettype none
module swing_three_pulse #(parameter integer CLK_HZ=50000000,MAX_PULSES=3)(
 input wire clk,rst_n,enable,sample_strobe,adc_valid,
 input wire [11:0] adc_code,wrap_span,wrap_half_span,
 input wire [11:0] wrap_low_code,wrap_high_code,
 input wire [11:0] bottom_code,target_code,upper_code,bottom_window,rearm_distance,
 input wire signed [15:0] first_pwm,
 input wire [15:0] pulse_ms,second_pwm,second_ms,
 input wire third_enable,
 input wire [15:0] third_pwm,third_ms,
 input wire [11:0] upright_code,capture_window,
 output wire signed [15:0] command,
 output reg done,pulse_event,
 output wire second_started,
 output reg [15:0] pulse_count);
localparam integer MAX_STEP=80;
reg seen,departed,departure_positive;
reg [11:0] previous_code;
reg signed [12:0] previous_distance;
reg signed [15:0] pulse_command;
reg [31:0] remaining;
reg [1:0] approach_samples,window_samples;
reg [5:0] stable_samples;
reg [3:0] reject_samples;
wire signed [12:0] raw_delta=$signed({1'b0,adc_code})-$signed({1'b0,previous_code});
wire signed [12:0] delta=raw_delta>$signed({1'b0,wrap_half_span}) ? raw_delta-$signed({1'b0,wrap_span}) :
 raw_delta<-$signed({1'b0,wrap_half_span}) ? raw_delta+$signed({1'b0,wrap_span}) : raw_delta;
wire signed [12:0] raw_distance=$signed({1'b0,adc_code})-$signed({1'b0,bottom_code});
wire signed [12:0] distance=raw_distance>$signed({1'b0,wrap_half_span}) ? raw_distance-$signed({1'b0,wrap_span}) :
 raw_distance<-$signed({1'b0,wrap_half_span}) ? raw_distance+$signed({1'b0,wrap_span}) : raw_distance;
wire [12:0] magnitude=distance[12] ? -distance : distance;
wire step_ok=delta<=MAX_STEP && delta>=-MAX_STEP;
wire returning=departure_positive ?
 (delta<0 && previous_distance>0 && distance<=$signed({1'b0,bottom_window}) && distance>=-MAX_STEP) :
 (delta>0 && previous_distance<0 && distance>=-$signed({1'b0,bottom_window}) && distance<=MAX_STEP);
wire signed [12:0] capture_delta=$signed({1'b0,adc_code})-$signed({1'b0,upright_code});
wire in_capture=capture_delta<=$signed({1'b0,capture_window}) && capture_delta>=-$signed({1'b0,capture_window});
wire signed [12:0] approach_band=$signed({1'b0,capture_window})+MAX_STEP;
wire in_approach=capture_delta<=approach_band && capture_delta>=-approach_band;
wire approaching=capture_delta<0 ? delta>=-4 : delta<=4;
wire stable_step=delta<=4 && delta>=-4;
wire near_seam={1'b0,adc_code}<={1'b0,wrap_low_code}+13'd16 ||
 {1'b0,adc_code}+13'd16>={1'b0,wrap_high_code};
wire capture_ready=window_samples>=2 || stable_samples>=40;
wire another_allowed=pulse_count==1 || (MAX_PULSES>=3 && third_enable && pulse_count==2);
assign second_started=pulse_count>=2;
assign command=enable && adc_valid && !done && remaining!=0 ? pulse_command : 16'sd0;
// 直立捕获资格与换圈拒绝窗口。
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin approach_samples<=0;window_samples<=0;stable_samples<=0;reject_samples<=0;end
 else if(!enable || pulse_count==0 || pulse_event)begin
  approach_samples<=0;window_samples<=0;stable_samples<=0;reject_samples<=0;
 end else if(!adc_valid)begin
  approach_samples<=0;window_samples<=0;stable_samples<=0;reject_samples<=12;
 end else if(sample_strobe && !done)begin
  if(!seen || !step_ok || near_seam)begin
   approach_samples<=0;window_samples<=0;stable_samples<=0;reject_samples<=12;
  end else if(reject_samples!=0)begin
   reject_samples<=reject_samples-1'b1;
   approach_samples<=0;window_samples<=0;stable_samples<=0;
  end else begin
   if(!in_approach || (!in_capture && !approaching))approach_samples<=0;
   else if(!in_capture && approach_samples<2)approach_samples<=approach_samples+1'b1;
   if(in_capture && approach_samples>=2)begin
    if(window_samples<2)window_samples<=window_samples+1'b1;
   end else window_samples<=0;
   if(in_capture && stable_step)begin
    if(stable_samples<40)stable_samples<=stable_samples+1'b1;
   end else stable_samples<=0;
  end
 end
end
// 冲击次数、离底重触发资格和脉冲持续时间。
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  seen<=0;departed<=0;departure_positive<=0;
  previous_code<=0;previous_distance<=0;pulse_command<=0;remaining<=0;
  done<=0;pulse_event<=0;pulse_count<=0;
 end else if(!enable)begin
  seen<=0;departed<=0;departure_positive<=0;
  previous_code<=0;previous_distance<=0;pulse_command<=0;remaining<=0;
  done<=0;pulse_event<=0;pulse_count<=0;
 end else begin
  pulse_event<=0;
  if(remaining!=0)remaining<=remaining-1'b1;
  if(!adc_valid)begin
   remaining<=0;seen<=0;
  end else if(capture_ready && !done)begin
   done<=1;remaining<=0;
  end else if(sample_strobe && !done)begin
   seen<=1;previous_code<=adc_code;previous_distance<=distance;
   if(!seen || !step_ok)begin end
   else if(pulse_count==0)begin
    if(magnitude<=bottom_window)begin
     pulse_command<=first_pwm;remaining<=pulse_ms*(CLK_HZ/1000);
     pulse_count<=1;pulse_event<=1;
    end
   end else begin
    if(another_allowed && !departed && magnitude>=rearm_distance)begin
     departed<=1;departure_positive<=!distance[12];
    end
    if(another_allowed && departed && returning)begin
     if(pulse_count==1)begin
      pulse_command<=first_pwm[15] ? $signed(second_pwm) : -$signed(second_pwm);
      remaining<=second_ms*(CLK_HZ/1000);
     end else begin
      pulse_command<=first_pwm[15] ? -$signed(third_pwm) : $signed(third_pwm);
      remaining<=third_ms*(CLK_HZ/1000);
     end
     pulse_count<=pulse_count+1'b1;pulse_event<=1;departed<=0;
    end
   end
  end
 end
end
endmodule
`default_nettype wire
