//////////////////////////////////////////////////////////////////////
// Module      : bus.v
// Description : RISC-V CPU 总线模块
//               - 指令通道 -> IMEM (ROM)
//               - 数据通道 -> DMEM (RAM) / MMIO (UART, GPIO)
//               - 内部实例化存储器 IP 和外设
//////////////////////////////////////////////////////////////////////

module bus (
    input  wire        clk,
    input  wire        rst_n,

    // ========== CPU 指令通道 ==========
    input  wire [31:0] inst_addr_i,
    input  wire        inst_re_i,
    output wire [31:0] inst_data_o,

    // ========== CPU 数据通道 ==========
    input  wire [31:0] data_addr_i,
    input  wire [31:0] data_wdata_i,
    input  wire        data_we_i,
    input  wire [3:0]  data_be_i,
    output wire [31:0] data_rdata_o,

    // ========== 外部 UART 引脚 ==========
    input  wire        uart_rx_i,       // 来自 FPGA 引脚（已同步处理）
    output wire        uart_tx
);

    //========================================================================
    // 1. 地址区域译码
    //========================================================================
    wire [3:0] d_region = data_addr_i[31:28];
    wire d_is_dmem   = (d_region == 4'h1);                    // 0x1000_0000 ~ 0x1FFF_FFFF
    wire d_is_mmio   = (d_region == 4'h2) || (d_region == 4'h3);   // MMIO 细分在后面，0x2000_0000 ~ 0x2FFF_FFFF 和 0x3000_0000 ~ 0x3FFF_FFFF 都是 MMIO
    // MMIO 细分
    wire d_is_uart  = d_is_mmio && (data_addr_i[31:12] == 20'h20000);   // 0x2000_0000
    wire d_is_gpio  = d_is_mmio && (data_addr_i[31:12] == 20'h20001);   // 0x2000_1000

    wire d_invalid = ~(d_is_dmem || d_is_uart || d_is_gpio);

    //========================================================================
    // 2. 内部互联信号
    //========================================================================
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        dmem_cs, dmem_we;
    wire [31:0] dmem_addr, dmem_wdata;
    wire [3:0]  dmem_be;
    wire [31:0] dmem_rdata;

    wire uart_cs, uart_we;
    wire [31:0] uart_rdata;

    wire gpio_cs, gpio_we;
    wire [31:0] gpio_rdata;

    //========================================================================
    // 3. 指令通道
    //========================================================================
    wire i_valid = (inst_addr_i[31:28] == 4'h0);
    assign imem_addr = inst_addr_i;
    assign inst_data_o = (inst_re_i && i_valid) ? imem_rdata : 32'h0;

    //========================================================================
    // 4. 数据通道设备选择
    //========================================================================
    assign dmem_cs   = !d_invalid && d_is_dmem;
    assign dmem_we   = dmem_cs && data_we_i;
    assign dmem_addr = {data_addr_i[31:2], 2'b00};
    assign dmem_wdata = data_wdata_i;
    assign dmem_be   = data_be_i;

    assign uart_cs   = !d_invalid && d_is_uart;
    // 适配器内部判断读写，此处 uart_we 仅在写时有效
    assign uart_we   = uart_cs && data_we_i;

    assign gpio_cs   = !d_invalid && d_is_gpio;
    assign gpio_we   = gpio_cs && data_we_i;

    //========================================================================
    // 5. 读数据多路选择器
    //========================================================================
    reg [31:0] rdata_mux;
    always @(*) begin
        rdata_mux = 32'h0;
        if (!d_invalid) begin
            if (dmem_cs)      rdata_mux = dmem_rdata;
            else if (uart_cs) rdata_mux = uart_rdata;
            else if (gpio_cs) rdata_mux = gpio_rdata;
        end
    end
    assign data_rdata_o = rdata_mux;

    //========================================================================
    // 6. 实例化存储器 IP (BRAM)
    //========================================================================
    // 指令 ROM (imem)
    imem u_imem (
        .clka  (clk),
        .addra (imem_addr[13:2]), // 4 字节对齐
        .douta (imem_rdata)
    );

    // 数据 RAM (dmem) - 需配置字节写使能
    dmem u_dmem (
        .clka  (clk),
        .wea   (dmem_be),        // 4 位字节写使能
        .addra (dmem_addr[13:2]), // 4 字节对齐
        .dina  (dmem_wdata),
        .clkb  (clk),
        .addrb (dmem_addr[13:2]), // 4 字节对齐
        .doutb (dmem_rdata)
    );

    //========================================================================
    // 7. 实例化 UART 适配器 + UART 核心
    //========================================================================
    wire [7:0]  s_axis_tdata;
    wire        s_axis_tvalid, s_axis_tready;
    wire [7:0]  m_axis_tdata;
    wire        m_axis_tvalid, m_axis_tready;
    wire        tx_busy, rx_busy, overrun_err, frame_err;
    wire [15:0] prescale;

    // UART 适配器（总线 -> AXI-Stream）
    uart_adapter u_uart_adapter (
        .clk         (clk),
        .rst_n       (rst_n),
        .reg_cs      (uart_cs),
        .reg_we      (uart_we),
        .reg_addr    (data_addr_i),
        .reg_wdata   (data_wdata_i),
        .reg_rdata   (uart_rdata),      // 回传给总线读数据 MUX
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .tx_busy     (tx_busy),
        .rx_busy     (rx_busy),
        .rx_overrun_error(overrun_err),
        .rx_frame_error  (frame_err),
        .prescale    (prescale)
    );

    // UART 核心 (AXI-Stream UART)
    uart #(
        .DATA_WIDTH(8)
    ) u_uart (
        .clk            (clk),
        .rst            (~rst_n),       // 原 UART 高电平复位，取反
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .rxd            (uart_rx_i), // 已同步的 RXD
        .txd            (uart_tx),
        .tx_busy        (tx_busy),
        .rx_busy        (rx_busy),
        .rx_overrun_error(overrun_err),
        .rx_frame_error (frame_err),
        .prescale       (prescale)
    );

    // 内部对 UART RX 引脚再做一次同步（已在 top 层同步，这里可添加，也可以直接接）
    // 这里我们假设顶层同步后的信号名叫 uart_rx，直接连接即可。
    // 为了安全，可在总线内再放一级同步，但顶层已做两级同步，所以直接使用。

    //========================================================================
    // 8. GPIO 外设（简单寄存器）
    //========================================================================
    reg [31:0] gpio_out_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gpio_out_reg <= 32'h0;
        else if (gpio_cs && gpio_we)
            gpio_out_reg <= data_wdata_i;
    end
    assign gpio_rdata = gpio_out_reg;

endmodule