`timescale 1ns / 1ps

module csr_reg (
    input  wire         clk,
    input  wire         rst,
    
    // 读写端口
    input  wire         we,
    input  wire [11:0]  waddr,
    input  wire [31:0]  wdata,
    input  wire [11:0]  raddr,
    output reg  [31:0]  rdata,

    // 异常/陷入硬件自动更新端口
    input  wire         trap_en,
    input  wire [31:0]  trap_epc,
    input  wire [31:0]  trap_cause,
    input  wire [31:0]  trap_tval,   // 新增：比如非法地址，存在这里
    output wire [31:0]  trap_vec,
    input  wire         mret_en,   
    
    // 性能计数器硬件更新 (连到流水线的使能信号)
    input  wire         inst_ret_en  // 如果 WB 阶段成功执行完一条指令，输入 1
);

    // --- 核心寄存器定义 ---
    reg [31:0] mstatus; 
    reg [31:0] mie;     
    reg [31:0] mtvec;   
    reg [31:0] mscratch;
    reg [31:0] mepc;    
    reg [31:0] mcause;  
    reg [31:0] mtval;   
    reg [31:0] mip;     

    // 性能计数器 (64位，在 32 位系统里分为低 32 位和高 32 位)
    reg [63:0] mcycle;   // 时钟周期计数器 (CoreMark 算分全靠它！)
    reg [63:0] minstret; // 成功执行的指令计数器

    assign trap_vec = mtvec;

    // --- 1. 读 CSR (纯组合逻辑) ---
    always @(*) begin
        if (rst) begin
            rdata = 0;
        end else begin
            case (raddr)
                12'h300: rdata = mstatus;
                12'h304: rdata = mie;
                12'h305: rdata = mtvec;
                12'h340: rdata = mscratch;
                12'h341: rdata = mepc;
                12'h342: rdata = mcause;
                12'h343: rdata = mtval;
                12'h344: rdata = mip;
                
                // 读性能计数器
                12'hB00: rdata = mcycle[31:0];   // mcycle 低32位
                12'hB80: rdata = mcycle[63:32];  // mcycleh 高32位
                12'hB02: rdata = minstret[31:0]; // minstret 低32位
                12'hB82: rdata = minstret[63:32];// minstreth 高32位
                
                default: rdata = 0;
            endcase
        end
    end

    // --- 2. 写 CSR 与 硬件状态更新 (时序逻辑) ---
    always @(posedge clk) begin
        if (rst) begin
            // 机器模式初始化
            mstatus  <= 32'h00001800; // 默认进入机器模式
            mie      <= 0;
            mtvec    <= 0;
            mscratch <= 0;
            mepc     <= 0;
            mcause   <= 0;
            mtval    <= 0;
            mip      <= 0;
            mcycle   <= 0;
            minstret <= 0;
        end else begin
            // 💡 硬件永远在跑的计数器
            mcycle <= mcycle + 1;
            if (inst_ret_en) begin
                minstret <= minstret + 1;
            end

            // 💡 异常发生时的硬件覆盖
            if (trap_en) begin
                mepc   <= trap_epc;
                mcause <= trap_cause;
                mtval  <= trap_tval;

                //保存MIE状态到MPIE，并禁止中断
                mstatus[7] <= mstatus[3]; // MPIE = MIE 
                mstatus[3] <= 1'b0;       // MIE = 0 (进入异常处理，禁止中断)
                mstatus[12:11] <= 2'b11;  // MPP = 11 (机器模式)
            end else if(mret_en) begin
                // 💡 mret 指令恢复现场
                mstatus[3] <= mstatus[7]; // MIE = MPIE (恢复之前的中断使能状态)
                mstatus[7] <= 1'b1;       // MPIE = 1 (mret后再次进入异常时，默认允许中断)
                mstatus[12:11] <= 2'b11;  
            end
            // 💡 软件指令主动写 CSR
            else if (we) begin
                case (waddr)
                    12'h300: mstatus  <= wdata;
                    12'h304: mie      <= wdata;
                    12'h305: mtvec    <= wdata;
                    12'h340: mscratch <= wdata;
                    12'h341: mepc     <= wdata;
                    12'h342: mcause   <= wdata;
                    12'h343: mtval    <= wdata;
                    12'h344: mip      <= wdata;
                    // 注意：标准通常不允许普通软件直接改计数器，所以这里不提供 mcycle 的写入口
                endcase
            end
        end
    end
endmodule