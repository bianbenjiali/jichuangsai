//////////////////////////////////////////////////////////////////////
// Module      : cpu_bus_controller.v
// Description : RISC-V 五级流水线总线控制器
//               - 支持哈佛结构：独立指令访存通道与数据访存通道
//               - 地址分配：
//                 * 指令存储器：0x0000_0000 ~ 0x0FFF_FFFF
//                 * 数据存储器：0x1000_0000 ~ 0x1FFF_FFFF
//                 * MMIO 区域：0x2000_0000 ~ 0x3FFF_FFFF
//               - 组合读数据返回，写信号由请求有效且写使能控制
//////////////////////////////////////////////////////////////////////

module cpu_bus_controller (
    input  wire        clk,
    input  wire        rst_n,

    // ========== 指令访存接口（IF 阶段） ==========
    input  wire        i_req,          // 取指请求（通常每周期有效，除非流水线暂停）
    input  wire [31:0] i_addr,         // 指令地址（PC）
    output wire [31:0] i_rdata,        // 读出的指令（32 位）
    output reg         i_ack,          // 指令访存完成应答（可用于暂停流水线）
    output reg         i_err,          // 指令访存错误（如越界）

    // ========== 数据访存接口（MEM 阶段） ==========
    input  wire        d_req,          // 数据访存请求（load/store 指令有效）
    input  wire        d_we,           // 写使能（1 = store，0 = load）
    input  wire [31:0] d_addr,         // 数据地址（字节地址）
    input  wire [31:0] d_wdata,        // 写数据（来自 rs2）
    output wire [31:0] d_rdata,        // 读数据（返回给 MEM/WB 流水线寄存器）
    output reg         d_ack,          // 数据访存完成应答
    output reg         d_err,          // 数据访存错误（越界或非对齐）

    // ========== 指令存储器接口（IMEM，只读） ==========
    output reg         imem_cs,        // 片选
    output reg  [31:0] imem_addr,      // 地址（通常字对齐）
    input  wire [31:0] imem_rdata,     // 读出的指令

    // ========== 数据存储器接口（DMEM，可读写） ==========
    output reg         dmem_cs,        // 片选
    output reg         dmem_we,        // 写使能
    output reg  [31:0] dmem_addr,      // 地址（字对齐）
    output reg  [31:0] dmem_wdata,     // 写数据
    input  wire [31:0] dmem_rdata,     // 读数据

    // ========== 外设接口示例（UART, GPIO, TIMER） ==========
    output reg         uart_cs,
    output reg         uart_we,
    output reg  [31:0] uart_wdata,
    input  wire [31:0] uart_rdata,

    output reg         gpio_cs,
    output reg         gpio_we,
    output reg  [31:0] gpio_wdata,
    input  wire [31:0] gpio_rdata,

    output reg         timer_cs,
    output reg         timer_we,
    output reg  [31:0] timer_wdata,
    input  wire [31:0] timer_rdata
);

//========================================================================
// 1. 地址区域译码（依据物理地址分配方案）
//========================================================================

// ----- 指令地址译码 -----
wire [3:0] i_region = i_addr[31:28];
// 指令存储器区域：0x0000_0000 ~ 0x0FFF_FFFF
wire i_is_imem = (i_region == 4'h0);
// 指令地址非法（超出 IMEM 范围）
wire i_invalid = ~i_is_imem;

// ----- 数据地址译码 -----
wire [3:0] d_region = d_addr[31:28];
// 数据存储器区域：0x1000_0000 ~ 0x1FFF_FFFF
wire d_is_dmem = (d_region == 4'h1);
// MMIO 区域总范围：0x2000_0000 ~ 0x3FFF_FFFF
wire d_is_mmio = (d_region[3:2] == 2'b10);  // [31:30] == 2'b10

// MMIO 外设细分译码（采用 4KB 对齐）
//   UART  : 0x2000_0000 ~ 0x2000_0FFF
//   GPIO  : 0x2000_1000 ~ 0x2000_1FFF
//   TIMER : 0x2000_2000 ~ 0x2000_2FFF
wire d_is_uart  = d_is_mmio && (d_addr[31:12] == 20'h20000);
wire d_is_gpio  = d_is_mmio && (d_addr[31:12] == 20'h20001);
wire d_is_timer = d_is_mmio && (d_addr[31:12] == 20'h20002);

// 数据地址非法（未映射区域）
wire d_invalid = ~(d_is_dmem || d_is_uart || d_is_gpio || d_is_timer);

// 可选：数据地址非对齐检测（仅支持字访问）
wire d_unaligned = (d_addr[1:0] != 2'b00);

//========================================================================
// 2. 指令访存控制逻辑
//========================================================================
always @(*) begin
    // 默认值
    imem_cs = 1'b0;
    i_ack   = 1'b0;
    i_err   = 1'b0;

    if (i_req) begin
        if (i_invalid) begin
            i_err = 1'b1;           // 指令地址越界，触发异常
            i_ack = 1'b0;
        end else begin
            imem_cs = 1'b1;
            i_ack   = 1'b1;         // 单周期响应
            i_err   = 1'b0;
        end
    end
end

// 指令地址连接（直接传递，存储器内部会忽略低两位）
always @(*) begin
    imem_addr = i_addr;
end

// 指令读数据：若请求有效且无错误，直接来自 IMEM，否则返回 0
assign i_rdata = (i_req && !i_err) ? imem_rdata : 32'h0;

//========================================================================
// 3. 数据访存控制逻辑
//========================================================================
always @(*) begin
    // 默认值
    dmem_cs   = 1'b0;
    dmem_we   = 1'b0;
    uart_cs   = 1'b0;
    uart_we   = 1'b0;
    gpio_cs   = 1'b0;
    gpio_we   = 1'b0;
    timer_cs  = 1'b0;
    timer_we  = 1'b0;
    d_ack     = 1'b0;
    d_err     = 1'b0;

    if (d_req) begin
        // 地址非法或非对齐错误
        if (d_invalid || d_unaligned) begin
            d_err = 1'b1;
            d_ack = 1'b0;
        end else begin
            d_ack = 1'b1;
            if (d_is_dmem) begin
                dmem_cs = 1'b1;
                dmem_we = d_we;
            end
            else if (d_is_uart) begin
                uart_cs = 1'b1;
                uart_we = d_we;
            end
            else if (d_is_gpio) begin
                gpio_cs = 1'b1;
                gpio_we = d_we;
            end
            else if (d_is_timer) begin
                timer_cs = 1'b1;
                timer_we = d_we;
            end
        end
    end
end

// 数据地址连接（传递字对齐地址）
always @(*) begin
    dmem_addr = {d_addr[31:2], 2'b00};  // 确保字对齐，低两位强制为 0
end

// 数据写数据总线连接（所有设备共享）
always @(*) begin
    dmem_wdata  = d_wdata;
    uart_wdata  = d_wdata;
    gpio_wdata  = d_wdata;
    timer_wdata = d_wdata;
end

//========================================================================
// 4. 数据读数据多路选择器
//========================================================================
reg [31:0] d_rdata_reg;
always @(*) begin
    d_rdata_reg = 32'h0;
    if (d_req && !d_err) begin
        if (dmem_cs)
            d_rdata_reg = dmem_rdata;
        else if (uart_cs)
            d_rdata_reg = uart_rdata;
        else if (gpio_cs)
            d_rdata_reg = gpio_rdata;
        else if (timer_cs)
            d_rdata_reg = timer_rdata;
    end
end
assign d_rdata = d_rdata_reg;

endmodule