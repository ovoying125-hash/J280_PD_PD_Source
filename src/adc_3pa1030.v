// 并行模数转换接口：产生十二点五兆赫兹采样时钟，每毫秒发布一次十位采样换算值。
// 数据在转换器时钟上升沿三个系统周期后锁存，逐位除法完成量程映射。
`default_nettype none
module adc_3pa1030 #(
    parameter integer CLK_HZ=50000000,
    parameter integer LEGACY_FULL_SCALE=1650,
    parameter integer IGNORE_OTR=1
)(
    input wire clk, rst_n,
    input wire [9:0] adc_data_in,
    input wire adc_otr,
    output wire adc_clk, adc_oe_n,
    output reg [11:0] sample_code,
    output reg sample_strobe, link_valid
);
localparam integer PERIOD=CLK_HZ/1000;
reg [1:0] phase;
reg [9:0] captured_data ;
reg captured_otr ;
reg [5:0] warmup;
reg [31:0] cadence;
reg [2:0] good_count;
reg busy;
reg [4:0] bits_left;
reg [20:0] dividend, quotient;
reg [10:0] remainder;
wire [21:0] scaled_input=captured_data*LEGACY_FULL_SCALE+22'd511;
wire [10:0] trial={remainder[9:0],dividend[20]};
wire take_bit=trial>=11'd1023;
wire [20:0] next_quotient={quotient[19:0],take_bit};
wire acquisition_allowed=IGNORE_OTR!=0 || !captured_otr;
assign adc_clk=phase[1];
assign adc_oe_n=!rst_n;
// 同步锁存转换结果，并在毫秒节拍推进定点量程换算。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        phase<=0; captured_data<=0; captured_otr<=1; warmup<=0;
        cadence<=0;good_count<=0;link_valid<=0;sample_code<=0;
        sample_strobe<=0;busy<=0;bits_left<=0;dividend<=0;quotient<=0;remainder<=0;
    end else begin
        phase<=phase+1'b1;
        sample_strobe<=0;
        
        if(phase==0) begin
            captured_data<=adc_data_in;
            captured_otr<=adc_otr;
            if(warmup<32)warmup<=warmup+1'b1;
        end
        if(!acquisition_allowed)begin link_valid<=0;good_count<=0;end
        cadence<=cadence==PERIOD-1 ? 32'd0 : cadence+1'b1;
        if(cadence==PERIOD-1 && warmup>=32 && !busy)begin
            if(acquisition_allowed)begin
                dividend<=scaled_input[20:0];quotient<=0;remainder<=0;
                bits_left<=21;busy<=1;
            end
        end
        if(busy)begin
            dividend<=dividend<<1;
            quotient<=next_quotient;
            remainder<=take_bit ? trial-11'd1023 : trial;
            bits_left<=bits_left-1'b1;
            if(bits_left==1)begin
                busy<=0;
                if(acquisition_allowed)begin
                    sample_code<=next_quotient[11:0];sample_strobe<=1;
                    if(good_count<4)good_count<=good_count+1'b1;
                    if(good_count>=3)link_valid<=1;
                end
            end
        end
    end
end
endmodule
`default_nettype wire
