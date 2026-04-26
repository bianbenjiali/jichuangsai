`timescale 1ns / 1ps

module cpu_core_tb();

    // 1. 定义连向 CPU 的线
    reg         clk;
    reg         rst;
    
    wire [31:0] inst_addr_o;
    wire [31:0] inst_data_i;
    wire        inst_re_o;
    
    wire[31:0] data_addr_o;
    wire [31:0] data_wdata_o;
    wire [31:0] data_rdata_i;
    wire        data_we_o;
    wire [ 3:0] data_be_o;

    // 2. 实例化你的 CPU 核心
    cpu_core u_cpu_core (
        .clk          (clk),
        .rst          (rst),
        .inst_addr_o  (inst_addr_o),
        .inst_data_i  (inst_data_i),
        .inst_re_o    (inst_re_o),
        .data_addr_o  (data_addr_o),
        .data_wdata_o (data_wdata_o),
        .data_rdata_i (data_rdata_i),
        .data_we_o    (data_we_o),
        .data_be_o    (data_be_o)
    );

    // 3. 制造一个虚拟的指令存储器 (ROM)
    reg [31:0] rom_array [0:255]; // 一个能存 256 条指令的数组
    
    // 【魔法时刻】：把刚写的 txt 文件读入这个数组！
    initial begin
        $readmemh("D:\\GitHub\\jichuangsai\\test\\inst.txt", rom_array);
    end
    
    // 把 ROM 的数据喂给 CPU
    // 注意避坑：RISC-V的PC每次加4(字节寻址)，而数组是按字(Word)寻址的，所以要把地址除以4（右移2位）
    assign inst_data_i = rom_array[inst_addr_o[31:2]];

    // 4. 制造一个虚拟的数据存储器 (RAM)
    reg [31:0] ram_array [0:255];
    
    // 简单的单周期写 RAM
    always @(posedge clk) begin
        if (data_we_o) begin
            ram_array[data_addr_o[31:2]] <= data_wdata_o; // 这里为了极简，先忽略了 data_be_o 字节掩码
        end
    end
    // 简单的单周期读 RAM
    assign data_rdata_i = ram_array[data_addr_o[31:2]];

    // 5. 产生时钟和复位信号
    initial begin
        clk = 0;
        rst = 1;         // 一开始复位有效 (假设高电平复位)
        #50 rst = 0;     // 50ns 后松开复位，CPU 开始狂奔！
        
        #500 $stop;      // 跑 500ns 就自动停止仿真
    end

    // 产生 100MHz 的时钟 (每 5ns 翻转一次)
    always #5 clk = ~clk;

endmodule