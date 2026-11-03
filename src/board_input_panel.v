// 按键与拨码输入：双级同步、二十毫秒稳定判定，按键松开后才重新使能边沿检测。
`default_nettype none
module board_input_panel #(parameter integer CLK_HZ=50000000)(
 input wire clk,rst_n,
 input wire [3:0] keys_n,
 input wire direction_n,reciprocal_n,
 output reg [3:0] step_pulse,
 output wire negative_direction,reciprocal_enable);
reg [5:0] sync1,sync2,candidate,stable;
reg [3:0] armed;
reg [4:0] counts[0:5];
reg [31:0] ms_count;
integer i;
assign negative_direction=stable[4];
assign reciprocal_enable=stable[5];
// 寄存状态更新与复位处理。
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  sync1<=0;sync2<=0;candidate<=0;stable<=0;armed<=0;step_pulse<=0;ms_count<=0;
  for(i=0;i<6;i=i+1)counts[i]<=0;
 end else begin
  sync1<=~{reciprocal_n,direction_n,keys_n};sync2<=sync1;step_pulse<=0;
  if(ms_count==CLK_HZ/1000-1)begin
   ms_count<=0;
   for(i=0;i<6;i=i+1)begin
    if(sync2[i]!=candidate[i])begin candidate[i]<=sync2[i];counts[i]<=0;end
    else if(counts[i]<20)begin
     counts[i]<=counts[i]+1'b1;
     if(counts[i]==19)begin
      stable[i]<=candidate[i];
      if(i<4)begin
       if(!candidate[i])armed[i]<=1;
       else if(!stable[i] && armed[i])begin step_pulse[i]<=1;armed[i]<=0;end
      end
     end
    end
   end
  end else ms_count<=ms_count+1'b1;
 end
end
endmodule
`default_nettype wire
