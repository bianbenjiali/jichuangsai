`timescale 1ns/1ps
module tb_top;

reg clk;
reg rst_n;
reg uart_rx;
wire uart_tx;

// 实例化顶层（你需要把 cpu_core 和 bus 连起来）
top u_top (
    .clk      (clk),
    .rst_n    (rst_n),
    .uart_rx  (uart_rx),
    .uart_tx  (uart_tx)
);

initial begin
    clk = 0;
    forever #5 clk = ~clk;   // 100MHz
end

initial begin
    rst_n = 0;
    uart_rx = 1'b1;
    #100 rst_n = 1;          // 复位释放
end

// 仿真时长看波形约 1~2ms 即可
initial begin
    #2_000_000;              // 2ms
    $finish;
end

endmodule