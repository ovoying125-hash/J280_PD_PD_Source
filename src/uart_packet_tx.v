// 二进制组帧发送：帧头、类型、长度、载荷和异或校验依次交给字节发送器。
// 输入握手时锁存完整快照，载荷按低字节在先发送，忙时不接收新帧。
`default_nettype none
module uart_packet_tx #(
    parameter integer CLK_HZ = 50000000,       
    parameter integer BAUD = 115200,           
    parameter integer MAX_PAYLOAD_BYTES = 8    
) (
    input  wire                             clk,           
    input  wire                             rst_n,         
    input  wire                             frame_valid,   
    output wire                             frame_ready,   
    input  wire [7:0]                       frame_type,    
    input  wire [7:0]                       frame_length,  
    input  wire [8*MAX_PAYLOAD_BYTES-1:0]   frame_payload, 
    output wire                             uart_txd       
);
    reg busy;                                  
    reg [7:0] byte_index;                      
    reg [7:0] saved_type;                      
    reg [7:0] saved_length;                    
    reg [7:0] saved_checksum;                  
    reg [8*MAX_PAYLOAD_BYTES-1:0] saved_payload; 
    reg [7:0] checksum_input;                  
    reg [7:0] tx_byte;                         
    integer i;                                 
    wire tx_ready;                             
    
    assign frame_ready = !busy && (frame_length <= MAX_PAYLOAD_BYTES);
    // 寄存状态更新与复位处理。
    always @* begin
        checksum_input = frame_type ^ frame_length;
        for (i = 0; i < MAX_PAYLOAD_BYTES; i = i + 1)
            if (i < frame_length)
                checksum_input = checksum_input ^ frame_payload[8*i +: 8];
    end
    // 寄存状态更新与复位处理。
    always @* begin
        case (byte_index)
            8'd0: tx_byte = 8'hA5;
            8'd1: tx_byte = 8'h5A;
            8'd2: tx_byte = saved_type;
            8'd3: tx_byte = saved_length;
            default: begin
                if (byte_index < saved_length + 8'd4)
                    tx_byte = saved_payload[8*(byte_index - 8'd4) +: 8];
                else
                    tx_byte = saved_checksum;
            end
        endcase
    end
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart_tx (
        .clk(clk), .rst_n(rst_n),
        .in_data(tx_byte), .in_valid(busy), .in_ready(tx_ready),
        .txd(uart_txd)
    );
    // 寄存状态更新与复位处理。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            byte_index <= 0;
            saved_type <= 0;
            saved_length <= 0;
            saved_payload <= 0;
            saved_checksum <= 0;
        end else begin
            if (frame_valid && frame_ready) begin
                saved_type <= frame_type;
                saved_length <= frame_length;
                saved_payload <= frame_payload;
                saved_checksum <= checksum_input;
                byte_index <= 0;
                busy <= 1'b1;
            end else if (busy && tx_ready) begin
                if (byte_index == saved_length + 8'd4)
                    busy <= 1'b0; 
                else
                    byte_index <= byte_index + 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
