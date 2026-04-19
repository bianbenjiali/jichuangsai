`include "defines.v"

module stage_if (
	input  wire               rst       ,
	input  wire [`MemAddrBus] pc_i      ,      // 来自 PC 寄存器的地址
	input  wire [    `RegBus] mem_data_i,      // 从外部 ROM 读回来的指令机器码
	input  wire               br        ,      // 分支跳转标志
	input  wire               right_one ,      // 原作者用来辅助跳转的信号
	output wire               mem_re    ,      // 读使能
	output wire [`MemAddrBus] mem_addr_o,      // 输出给外部 ROM 的地址
	output wire [`MemAddrBus] pc_o      ,      // 传递给下一级的 PC
	output wire [   `InstBus] inst_o    ,      // 传递给下一级的 指令
	output wire               stallreq         // 暂停请求
);

	// 永远允许读指令
	assign mem_re = rst ? 1'b0 : 1'b1;
	
	// 直接把PC作为地址输出给外部的指令ROM
	assign mem_addr_o = pc_i;
	
	// 流水线向后传递的PC
	assign pc_o = pc_i;
	
	// 【核心逻辑】：如果复位，或者发生了跳转(br)，强行向流水线塞入一条 NOP 指令 (0x00000013 即 addi x0, x0, 0)
	// 否则，直接把外部 ROM 读回来的数据当作指令送入解码阶段
	assign inst_o = (rst || br) ? 32'h00000013 : mem_data_i;
	
	// 净化后，取指阶段自身不再产生阻塞（假设ROM是单周期的）
	assign stallreq = 1'b0;

endmodule