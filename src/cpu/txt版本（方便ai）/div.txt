`timescale 1ns / 1ps

module div (
    input  wire        clk,
    input  wire        rst,
    
    input  wire        start,     // 开始信号，外部拉高一个周期触发除法运算
    input  wire        is_signed, // 是否有符号除法
    input  wire [31:0] dividend,  // 被除数
    input  wire [31:0] divisor,   // 除数
    
    output reg  [31:0] quotient,  // 商
    output reg  [31:0] remainder, // 余数
    output reg         ready      // 结果准备好信号，除法完成后拉高一个周期
);

    reg [1:0]  state;
    reg [5:0]  count;
    
    reg [31:0] reg_q;
    reg [32:0] reg_r; 
    reg [32:0] reg_b; 
    reg        sign_q, sign_r;

    localparam IDLE = 2'b00;
    localparam CALC = 2'b01;
    localparam DONE = 2'b10;

    // 非恢复余数法核心组合逻辑
    wire [32:0] shifted_r = {reg_r[31:0], reg_q[31]}; // 每轮左移一位，把商的最高位移到余数的最低位
    wire [32:0] sub_res   = shifted_r - reg_b; 
    wire [32:0] add_res   = shifted_r + reg_b;
    wire [32:0] next_r    = (reg_r[32] == 1'b0) ? sub_res : add_res; // 如果当前余数非负，减去除数；如果当前余数为负，加回除数
    wire        next_q0   = ~next_r[32]; 

    // 用组合逻辑提前算好最终修正余数
    // 如果最后余数是负的（最高位为1），就加上除数修正回来
    wire [32:0] final_r   = (reg_r[32] == 1'b1) ? (reg_r + reg_b) : reg_r;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            ready <= 0;
            quotient <= 0;
            remainder <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 0;
                    if (start && divisor != 0) begin
                        sign_q <= is_signed ? (dividend[31] ^ divisor[31]) : 1'b0;
                        sign_r <= is_signed ? dividend[31] : 1'b0;
                        
                        reg_q <= (is_signed && dividend[31]) ? (~dividend + 1) : dividend;
                        reg_b <= {1'b0, (is_signed && divisor[31]) ? (~divisor + 1) : divisor};
                        reg_r <= 0;
                        
                        count <= 0;
                        state <= CALC;
                    end else if (start && divisor == 0) begin
                        quotient  <= 32'hFFFFFFFF;
                        remainder <= dividend;
                        ready     <= 1;
                        state     <= DONE;
                    end
                end
                
                CALC: begin
                    if (count < 32) begin
                        reg_r <= next_r;
                        reg_q <= {reg_q[30:0], next_q0}; // A/Q 复用
                        count <= count + 1;
                    end else begin
                        state <= DONE; // 算够32次，直接去 DONE
                    end
                end
                
                DONE: begin
                    if (ready == 0) begin
                        // 输出结果时，直接使用修正好的 final_r
                        quotient  <= sign_q ? (~reg_q + 1) : reg_q;
                        remainder <= sign_r ? (~final_r[31:0] + 1) : final_r[31:0];
                        ready     <= 1;
                    end else begin
                        ready <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule