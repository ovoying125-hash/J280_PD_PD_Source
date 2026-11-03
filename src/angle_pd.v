`default_nettype none
// 内环比例微分控制：微分作用于测量值，目标倾角改变不会直接产生微分冲击。
// 测量差分按四分之一系数滤波；增益与差分的单位均对应一毫秒采样。
module angle_pd #(parameter integer OUTPUT_LIMIT=900)(
 input wire clk,rst_n,enable,tick,
 input wire signed [12:0] measurement,target,
 input wire signed [23:0] kp_q8,kd_q8,
 output reg signed [15:0] command);
reg signed [12:0] previous;
reg signed [31:0] derivative_q8;
wire signed [13:0] delta=$signed({previous[12],previous})-$signed({measurement[12],measurement});
wire signed [31:0] d_next=derivative_q8+(($signed(delta)*32'sd256-derivative_q8)>>>2);
wire signed [13:0] error=$signed({target[12],target})-$signed({measurement[12],measurement});
wire signed [63:0] p_term=$signed(kp_q8)*$signed(error);
wire signed [63:0] d_term=$signed(kd_q8)*$signed(d_next);
wire signed [63:0] total=((p_term<<<8)+d_term)>>>16;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin previous<=0;derivative_q8<=0;command<=0;end
 else if(!enable)begin previous<=measurement;derivative_q8<=0;command<=0;end
 else if(tick)begin
  previous<=measurement;derivative_q8<=d_next;
  command<=total>OUTPUT_LIMIT ? OUTPUT_LIMIT : total< -OUTPUT_LIMIT ? -OUTPUT_LIMIT : total[15:0];
 end
end
endmodule
`default_nettype wire
