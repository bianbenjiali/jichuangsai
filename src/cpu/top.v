module top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,       // 来自板载 USB-UART 的 RX 引脚
    output wire        uart_tx        // 发送到 USB-UART 的 TX 引脚
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

endmodule