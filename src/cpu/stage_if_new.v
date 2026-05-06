`include "defines.v"

module stage_if (
	input  wire               clk       ,
	input  wire               rst       ,
	input  wire [`MemAddrBus] pc_i      ,      // 来自 PC 寄存器的地址
	input  wire [5:0]         stall     ,
	//input  wire [`MemAddrBus] next_pc_i ,
	input  wire [    `RegBus] mem_data_i,      // 从外部 ROM 读回来的指令机器码
	input  wire               br        ,      // 分支跳转标志
	output wire               mem_re    ,      // 读使能
	output wire [`MemAddrBus] mem_addr_o,      // 输出给外部 ROM 的地址
	output wire [`MemAddrBus] pc_o      ,      // 传递给下一级的 PC
	output wire [   `InstBus] inst_o    ,      // 传递给下一级的 指令
	output wire               stallreq         // 暂停请求
);

    // =========================================================
    reg if_acc_done;

    always @(posedge clk) begin
        if (rst || br) begin
            // 只要复位，或者 ID 阶段要求冲刷(br=1)，立刻清空完成标志，重新取指！
            if_acc_done <= 1'b0;
        end else begin
            if (!if_acc_done) begin
                // 等待 1 拍，BRAM 把数据吐出来后，标记为已完成
                if_acc_done <= 1'b1;
            end else if (!stall[1]) begin
                // 【精髓】：只有当如果自己没有被下游(ID/EX/MEM)卡住时，
                // 才说明这条指令成功送走了，可以清空标志去取下一条了！
                if_acc_done <= 1'b0;
            end
        end
    end

    // 永远允许读指令
    assign mem_re = rst ? 1'b0 : 1'b1;
    assign mem_addr_o = pc_i;
    assign pc_o = pc_i;
    
    // 🚨 只要还没 done，就向全局大喊：停下等我！
    assign stallreq = !if_acc_done;

    // 输出指令：如果刚复位、被冲刷，或者数据还没取回来(!if_acc_done)，强制输出 NOP 气泡保护流水线！
    assign inst_o = (rst || br || !if_acc_done) ? 32'h00000013 : mem_data_i;

	// 永远允许读指令
	/*assign mem_re = rst ? 1'b0 : 1'b1;
	
	// 直接把PC作为地址输出给外部的指令ROM
	assign mem_addr_o = pc_i;
	
	// 流水线向后传递的PC
	assign pc_o = pc_i;
	
	// 【核心逻辑】：如果复位，或者发生了跳转(br)，强行向流水线塞入一条 NOP 指令 (0x00000013 即 addi x0, x0, 0)
	// 否则，直接把外部 ROM 读回来的数据当作指令送入解码阶段
	assign inst_o = (rst || br) ? 32'h00000013 : mem_data_i;
	
	// 净化后，取指阶段自身不再产生阻塞（假设ROM是单周期的）
	assign stallreq = 1'b0;*/

endmodule