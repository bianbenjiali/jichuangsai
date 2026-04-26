`timescale 1ns/1ps

module tb_bus;

    // 时钟和复位
    reg clk;
    reg rst_n;

    // CPU 接口信号
    reg  [31:0] inst_addr;
    reg         inst_re;
    wire [31:0] inst_data;

    reg  [31:0] data_addr;
    reg  [31:0] data_wdata;
    reg         data_we;
    reg  [3:0]  data_be;
    wire [31:0] data_rdata;

    // UART 外部引脚
    reg  uart_rx;
    wire uart_tx;

    // 实例化总线模块
    bus u_bus (
        .clk          (clk),
        .rst_n        (rst_n),
        .inst_addr_i  (inst_addr),
        .inst_re_i    (inst_re),
        .inst_data_o  (inst_data),
        .data_addr_i  (data_addr),
        .data_wdata_i (data_wdata),
        .data_we_i    (data_we),
        .data_be_i    (data_be),
        .data_rdata_o (data_rdata),
        .uart_rx_i    (uart_rx),
        .uart_tx      (uart_tx)
    );

    // 时钟生成（100MHz，周期 10ns）
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 复位生成
    initial begin
        rst_n = 0;
        #100 rst_n = 1;    // 100ns 后释放复位
    end

    // 测试流程
    initial begin
        // 初始化信号
        inst_addr  = 32'h0;
        inst_re    = 1'b0;
        data_addr  = 32'h0;
        data_wdata = 32'h0;
        data_we    = 1'b0;
        data_be    = 4'b1111;
        uart_rx    = 1'b1;       // UART 空闲为高

        // 等待复位释放
        @(posedge rst_n);
        repeat (5) @(posedge clk);  // 等待几个周期

        // ================================
        // 测试 1：指令存储器读取
        // ================================
        inst_addr = 32'h0000_0000;
        inst_re   = 1'b1;
        @(posedge clk);
        #1;  // 等待数据稳定
        $display("IMEM read @0x%08h: 0x%08h", inst_addr, inst_data);

        inst_addr = 32'h0000_0004;
        @(posedge clk);
        #1;
        $display("IMEM read @0x%08h: 0x%08h", inst_addr, inst_data);

        inst_re   = 1'b0;   // 停止指令读取
        @(posedge clk);

        // ================================
        // 测试 2：数据存储器写入/读取
        // ================================
        // 写一个字到 DMEM 地址 0x1000_0100
        data_addr  = 32'h1000_0100;
        data_wdata = 32'hDEAD_BEEF;
        data_we    = 1'b1;
        data_be    = 4'b1111;
        @(posedge clk);
        data_we    = 1'b0;   // 取消写使能

        // 读回同一地址
        data_addr  = 32'h1000_0100;
        @(posedge clk);
        #1;
        $display("DMEM read @0x%08h: 0x%08h (expected 0xDEAD_BEEF)", data_addr, data_rdata);

        // 测试字节写（只写最低字节）
        data_addr  = 32'h1000_0200;
        data_wdata = 32'hAA55_AA55;
        data_be    = 4'b0001;   // 只写 byte0
        data_we    = 1'b1;
        @(posedge clk);
        data_we    = 1'b0;

        // 读回
        data_addr  = 32'h1000_0200;
        @(posedge clk);
        #1;
        $display("DMEM byte write read @0x%08h: 0x%08h (expected 0x0000_00A5)", data_addr, data_rdata);

        // ================================
        // 测试 3：UART 发送
        // ================================
        // 写 PRESCALE 寄存器（0x2000000C）
        data_addr  = 32'h2000_000C;
        data_wdata = 32'd109;   // prescale ~ 115200 baud @ 100MHz
        data_we    = 1'b1;
        @(posedge clk);
        data_we    = 1'b0;

        // 写 TX_DATA 寄存器（0x20000000）发送字符 'A'
        data_addr  = 32'h2000_0000;
        data_wdata = 8'h41;
        data_we    = 1'b1;
        @(posedge clk);
        data_we    = 1'b0;

        // 等待发送完成（STATUS bit0 变为 0）
        data_addr  = 32'h2000_0008;
        data_we    = 1'b0;
        wait ( (data_rdata & 1) == 0 );   // 等待 TX_BUSY=0

        // 观察 uart_tx 波形，应能看到一个字节的串行数据

        // ================================
        // 测试 4：UART 接收（模拟外界发送 0x55）
        // ================================
        // 产生一个字节的 UART 帧：起始位(0) + 8数据位 + 停止位(1)
        // 发送 0x55 = 8'b0101_0101, LSB first
        @(posedge clk);
        uart_rx = 1'b0;   // 起始位
        repeat(868) @(posedge clk);      // 波特率周期
        // 数据位 bit0
        uart_rx = 1'b1;
        repeat(868) @(posedge clk);
        uart_rx = 1'b0;  // bit1
        repeat(868) @(posedge clk);
        uart_rx = 1'b1;  // bit2
        repeat(868) @(posedge clk);
        uart_rx = 1'b0;  // bit3
        repeat(868) @(posedge clk);
        uart_rx = 1'b1;  // bit4
        repeat(868) @(posedge clk);
        uart_rx = 1'b0;  // bit5
        repeat(868) @(posedge clk);
        uart_rx = 1'b1;  // bit6
        repeat(868) @(posedge clk);
        uart_rx = 1'b0;  // bit7
        repeat(868) @(posedge clk);
        uart_rx = 1'b1;  // 停止位
        repeat(868) @(posedge clk);

        // 等待 RX_VALID（STATUS bit1）
        data_addr = 32'h2000_0008;
        wait ( (data_rdata & 2) != 0 );
        // 读 RX_DATA
        data_addr = 32'h2000_0004;
        @(posedge clk);
        #1;
        $display("UART RX data: 0x%08h (expected 0x55)", data_rdata);

        // ================================
        // 测试 5：GPIO 读写
        // ================================
        data_addr  = 32'h2000_1000;
        data_wdata = 32'hFF00_00FF;
        data_we    = 1'b1;
        @(posedge clk);
        data_we    = 1'b0;

        data_addr  = 32'h2000_1000;
        @(posedge clk);
        #1;
        $display("GPIO read back: 0x%08h", data_rdata);

        $display("All tests completed.");
        $finish;
    end

endmodule