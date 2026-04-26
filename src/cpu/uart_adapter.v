// uart_adapter.v
module uart_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 总线接口 ----
    input  wire        reg_cs,       // 片选
    input  wire        reg_we,       // 写使能
    input  wire [31:0] reg_addr,     // 完整地址 (用来区分寄存器)
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // ---- AXI-Stream 接口 (连接 uart 顶层) ----
    output wire [7:0]  s_axis_tdata,
    output reg         s_axis_tvalid,
    input  wire        s_axis_tready,

    input  wire [7:0]  m_axis_tdata,
    input  wire        m_axis_tvalid,
    output reg         m_axis_tready,

    // ---- UART 状态与控制 ----
    input  wire        tx_busy,
    input  wire        rx_busy,
    input  wire        rx_overrun_error,
    input  wire        rx_frame_error,
    output reg  [15:0] prescale
);

    // 寄存器地址译码（使用地址的 bit3:2）
    wire addr_tx_data  = reg_cs && (reg_addr[3:2] == 2'b00);  // 0x00
    wire addr_rx_data  = reg_cs && (reg_addr[3:2] == 2'b01);  // 0x04
    wire addr_status   = reg_cs && (reg_addr[3:2] == 2'b10);  // 0x08
    wire addr_prescale = reg_cs && (reg_addr[3:2] == 2'b11);  // 0x0C

    //========================================================================
    // 发送逻辑
    //========================================================================
    reg [7:0] tx_data_reg;
    reg       tx_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data_reg <= 8'h0;
            tx_pending  <= 1'b0;
        end else begin
            // AXI 握手完成，清除 pending
            if (tx_pending && s_axis_tready) begin
                tx_pending <= 1'b0;
            end
            // CPU 写入 TX_DATA
            if (addr_tx_data && reg_we) begin
                tx_data_reg <= reg_wdata[7:0];
                tx_pending  <= 1'b1;
            end
        end
    end

    assign s_axis_tdata = tx_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axis_tvalid <= 1'b0;
        end else begin
            if (tx_pending && !s_axis_tvalid)
                s_axis_tvalid <= 1'b1;
            else if (s_axis_tvalid && s_axis_tready)
                s_axis_tvalid <= 1'b0;
        end
    end

    //========================================================================
    // 接收逻辑
    //========================================================================
    reg [7:0] rx_data_reg;
    reg       rx_valid;
    reg       rx_overrun_reg;
    reg       rx_frame_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_reg    <= 8'h0;
            rx_valid       <= 1'b0;
            rx_overrun_reg <= 1'b0;
            rx_frame_reg   <= 1'b0;
        end else begin
            // CPU 读走 RX_DATA 后清除有效标志
            if (addr_rx_data && !reg_we)
                rx_valid <= 1'b0;

            // AXI-Stream 接收握手
            if (m_axis_tvalid && m_axis_tready) begin
                if (rx_valid) begin
                    rx_overrun_reg <= 1'b1;   // 数据覆盖，溢出
                end else begin
                    rx_data_reg <= m_axis_tdata;
                    rx_valid    <= 1'b1;
                end
            end

            // 锁存帧错误
            if (rx_frame_error)
                rx_frame_reg <= 1'b1;
        end
    end

    // 一直准备好接收（如果怕溢出，可加握手，但 overrun 机制已处理）
    always @(*) begin
        m_axis_tready = 1'b1;
    end

    //========================================================================
    // 预分频寄存器
    //========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prescale <= 16'd0;
        else if (addr_prescale && reg_we)
            prescale <= reg_wdata[15:0];
    end

    //========================================================================
    // 读数据多路选择（返回给 CPU）
    //========================================================================
    always @(*) begin
        reg_rdata = 32'h0;
        if (reg_cs) begin
            if (addr_rx_data && !reg_we)
                reg_rdata = {24'h0, rx_data_reg};
            else if (addr_status && !reg_we)
                reg_rdata = {28'h0,
                             rx_frame_reg,   // bit3
                             rx_overrun_reg, // bit2
                             rx_valid,       // bit1   (RX data valid)
                             tx_busy         // bit0   (TX busy)
                            };
            else if (addr_prescale && !reg_we)
                reg_rdata = {16'h0, prescale};
        end
    end

endmodule