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

    // =================================================================
    // 🌟 终极外挂：UART TX 虚拟窃听器 (直接在 Vivado 控制台打印)
    // =================================================================
    // 注意：波特率 115200 下，1个 bit 的时间是 1000000000 / 115200 ≈ 8680 ns
    // 如果你们波特率是 2304000，那时间就是 434 ns。请根据你们的实际波特率修改这里！
    localparam BIT_PERIOD = 8680; // 假设波特率 115200

    reg [7:0] rx_char;
    integer i;

    always @(negedge uart_tx) begin // 捕捉到起始位 (下降沿)
        #(BIT_PERIOD / 2);          // 走到起始位正中间
        
        if (uart_tx == 0) begin     // 确认真的是起始位
            #(BIT_PERIOD);          // 跨过起始位
            
            // 连续采样 8 个数据位
            for (i = 0; i < 8; i = i + 1) begin
                rx_char[i] = uart_tx;
                #(BIT_PERIOD);
            end
            
            // 打印字符到 Tcl Console！(不换行)
            $write("%c", rx_char);
        end
    end

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