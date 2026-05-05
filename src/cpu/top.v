module top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,       // 来自板载 USB-UART 的 RX 引脚
    output wire        uart_tx,          // 发送到 USB-UART 的 TX 引脚
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

    (* mark_debug = "true" *) wire [31:0] debug_inst_addr = inst_addr;
    (* mark_debug = "true" *) wire [31:0] debug_inst_data = inst_data;

    // ====================================================
    // 🌟 工业级安全设计：CPU 时钟门控使能生成
    // ====================================================
    /*reg cpu_clk_en;
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
    );*/

    //========================================================================
    // 实例化 CPU 核心（队友A 提供）
    //========================================================================
    cpu_core u_cpu_core (
        .clk         (clk),
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
  // 1. 测时钟：证明板子的晶振是活着的！
    reg [25:0] alive_cnt;
    always @(posedge clk) begin
        alive_cnt <= alive_cnt + 1;
    end
    // 如果系统时钟(100MHz)正常，LED[0] 大概每 0.6 秒闪烁一次！
    // 如果 LED[0] 不闪，说明时钟约束写错了或者板子时钟坏了！
    assign led[0] = alive_cnt[25]; 

    // 2. 测 CPU 是否在动：接 PC 的低位！
    // 只要 CPU 没死机，PC 就会一直变。PC[6] 每过 64 个字节翻转一次。
    // 在 50MHz 下，它翻转极快！人眼的视觉暂留会觉得 LED[1] 是【半亮】的状态（亮暗交替太快）。
    // 如果 LED[1] 全亮或全灭，说明 CPU 彻底死锁停住了！
    assign led[1] = inst_addr[6];

    // 3. 测串口状态
    // 如果 CPU 成功跑到了打印字符串的阶段，并且在等串口发送
    // 你会看到 LED[2] 在微微闪烁（快速地忙碌、空闲交替）
    assign led[2] = uart_tx; // 直接把 UART TX 线接到 LED[2]，这样它发送数据时 LED 就会亮！

    // 4. 测复位信号
    // 用手按下复位键，LED[3] 应该熄灭。松开后常亮。
    assign led[3] = rst_n;

endmodule