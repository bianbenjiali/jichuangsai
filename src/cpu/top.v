module top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,       // 来自板载 USB-UART 的 RX 引脚
    output wire        uart_tx,        // 发送到 USB-UART 的 TX 引脚
    output wire [3:0]  led
    // 其他如 GPIO 输出可在此添加
);

    //========================================================================
    // UART RX 同步处理（二级同步器，消除亚稳态）
    //========================================================================
    reg uart_rx_meta, uart_rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_meta <= 1'b1;
            uart_rx_sync <= 1'b1;
        end else begin
            uart_rx_meta <= uart_rx;         // 第一级
            uart_rx_sync <= uart_rx_meta;    // 第二级
        end
    end

    //========================================================================
    // CPU 与总线之间的信号
    //========================================================================
    wire [31:0] inst_addr, inst_data;
    wire        inst_re;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire        data_we;
    wire [3:0]  data_be;

    // ====================================================
    // 🌟 工业级安全设计：CPU 时钟门控使能生成
    // ====================================================
    reg cpu_clk_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_clk_en <= 1'b0;
        end else begin
            cpu_clk_en <= ~cpu_clk_en; // 每 1 个 sys_clk 周期翻转一次
        end
    end

    // ====================================================
    // 🌟 调用 Xilinx 时钟树专用门控原语
    // ====================================================
    wire cpu_clk;

    BUFGCE u_cpu_clock_gate (
        .O   (cpu_clk),    // 输出：受控的、干净的 CPU 时钟 (50MHz)
        .I   (clk),        // 输入：系统主时钟 (100MHz)
        .CE  (cpu_clk_en)  // 使能：010101 翻转信号
    );

    //========================================================================
    // 实例化 CPU 核心（队友A 提供）
    //========================================================================
    cpu_core u_cpu_core (
        .clk         (cpu_clk),
        .rst         (~rst_n),
        .inst_addr_o (inst_addr),
        .inst_data_i (inst_data),
        .inst_re_o   (inst_re),
        .data_addr_o (data_addr),
        .data_wdata_o(data_wdata),
        .data_rdata_i(data_rdata),
        .data_we_o   (data_we),
        .data_be_o   (data_be)
    );

    //========================================================================
    // 实例化总线模块（队友B 提供）
    //========================================================================
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
        .uart_rx_i    (uart_rx_sync),   // 连接同步后的信号
        .uart_tx      (uart_tx)
    );
    // 假设板子上有 4 个 LED 灯，在 XDC 里绑定好引脚

    // 把 CPU 的 PC 指针的高位接到 LED 上！
    // 为什么接高位？因为 CPU 跑得太快了（50MHz），接低位灯会闪得连成一片，人眼看不出。
    // 接第 24~27 位，如果 CPU 在狂奔，你会看到 LED 像呼吸灯一样闪烁！
    assign led[0] = inst_addr[24]; 
    assign led[1] = inst_addr[25]; 
    
    // 把 UART 的 TX busy 状态接到 LED 上
    assign led[2] = uart_tx; 
    
    // 把复位信号接到 LED 上 (检查复位极性)
    assign led[3] = rst_n;

endmodule