`default_nettype none
// 将电位器读数先换算为相对直立点的最短环形位移，再进行一阶低通。
// 四分之一更新系数作用于十六位小数状态，避免低速小信号被整数截断锁住。
module angle_filter #(parameter integer ZERO_CODE=1241, SPAN=1650)(
 input wire clk,rst_n,sample,
 input wire [11:0] adc_code,
 output wire signed [12:0] angle,
 output reg valid);
reg seeded;
reg signed [31:0] state_q16;
wire signed [13:0] raw=$signed({2'b0,adc_code})-ZERO_CODE;
wire signed [13:0] wrapped=raw>SPAN/2 ? raw-SPAN : raw< -SPAN/2 ? raw+SPAN : raw;
wire signed [31:0] target_q16=$signed(wrapped)*32'sd65536;
assign angle=state_q16>>>16;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n)begin seeded<=0;state_q16<=0;valid<=0;end
 else begin
  valid<=0;
  if(sample)begin
   state_q16<=!seeded ? target_q16 : state_q16+((target_q16-state_q16)>>>2);
   seeded<=1;valid<=1;
  end
 end
end
endmodule
`default_nettype wire
