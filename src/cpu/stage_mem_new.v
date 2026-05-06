`include "defines.v"

module stage_mem (
	input  wire               clk        ,
	input  wire [5:0]         stall      ,
	input  wire               rst        ,
	input  wire [`RegAddrBus] reg_waddr_i,
	input  wire               we_i       ,
	input  wire [    `RegBus] reg_wdata_i,
	input  wire [`MemAddrBus] mem_addr_i ,     // 来自 EX 阶段算出的访存地址
	input  wire [  `AluOpBus] aluop      ,     // 操作码（判断是 lw 还是 sw 等）
	input  wire [    `RegBus] rt_data    ,     // 要存入内存的数据 (store指令用)
	input  wire [    `RegBus] mem_data_i ,     // 从外部 RAM 读回来的数据 (load指令用)
	
	output reg  [`RegAddrBus] reg_waddr_o,
	output reg                we_o       ,
	output reg  [    `RegBus] reg_wdata_o,     // 最终写回寄存器的值
	
	output reg  [`MemAddrBus] mem_addr_o ,     // 输出给外部 RAM 的地址
	output reg                mem_re     ,     // 外部 RAM 读使能
	output reg                mem_we     ,     // 外部 RAM 写使能
	output reg  [        3:0] mem_sel    ,     // 外部 RAM 字节掩码 (Byte Enable)
	output reg  [    `RegBus] mem_data_o ,     // 往外部 RAM 写的数据
	output reg                stallreq         // 暂停请求
);

	// 1. 定义哪些是 Load 指令
    wire is_mem_op = (aluop == `EXE_LB_OP  || aluop == `EXE_LH_OP || 
                    aluop == `EXE_LW_OP  || aluop == `EXE_LBU_OP || 
                    aluop == `EXE_LHU_OP || aluop == `EXE_SB_OP || 
					aluop == `EXE_SH_OP  || aluop == `EXE_SW_OP);

    // 2. 状态记录：记录我们是否已经为了这条指令等待过一个周期了
    reg mem_acc_done;
    always @(posedge clk) begin
        if (rst) begin
            mem_acc_done <= 1'b0;
        end else if (is_mem_op && !mem_acc_done) begin
            mem_acc_done <= 1'b1; // 发出暂停请求后，下一拍就代表等待完成了
        end else if(!stall[4]) begin
            mem_acc_done <= 1'b0;
		end else begin
			mem_acc_done <= 1'b0;
		end
    end

	always @ (*) begin
		if(rst) begin
			reg_waddr_o = 0;   we_o = 0;   reg_wdata_o = 0;
			mem_addr_o = 0;    mem_re = 0; mem_we = 0;
			mem_sel = 4'b0000; mem_data_o = 0; stallreq = 0;
		end /*else if(is_mem_op && !mem_acc_done) begin
			// 如果是内存操作指令，并且还没有等过一个周期，就发出暂停请求，等待数据准备好
			reg_waddr_o = 0;   we_o = 0;   reg_wdata_o = 0;
			mem_addr_o = mem_addr_i; mem_re = 1'b1; mem_we = 1'b1;
			mem_sel = 4'b0000; mem_data_o = 0; stallreq = 1'b1;
		end*/ else begin
			// 默认值往下传
			reg_waddr_o = reg_waddr_i;
			we_o        = we_i;
			reg_wdata_o = reg_wdata_i; 
			
			// 默认不访存
			mem_addr_o = 0;    mem_re = 0; mem_we = 0;
			mem_sel = 4'b0000; mem_data_o = 0; stallreq = 0;

			case (aluop)
				// ================= 读内存 (Load) =================
				`EXE_LB_OP, `EXE_LH_OP, `EXE_LW_OP, `EXE_LBU_OP, `EXE_LHU_OP : begin
					mem_addr_o = {mem_addr_i[31:2], 2'b00}; // 强制 4 字节对齐
					mem_re     = 1'b1;
					stallreq = !mem_acc_done;
					// 根据末两位地址，从 32 位数据中截取需要的字节，并做符号扩展
					case (aluop)
						`EXE_LB_OP : begin
							case (mem_addr_i[1:0])
								2'b00   : reg_wdata_o = {{24{mem_data_i[7]}}, mem_data_i[7:0]};
								2'b01   : reg_wdata_o = {{24{mem_data_i[15]}}, mem_data_i[15:8]};
								2'b10   : reg_wdata_o = {{24{mem_data_i[23]}}, mem_data_i[23:16]};
								2'b11   : reg_wdata_o = {{24{mem_data_i[31]}}, mem_data_i[31:24]};
                                default : reg_wdata_o = 0;
							endcase
						end
						`EXE_LH_OP : begin
							case (mem_addr_i[1:0])
								2'b00   : reg_wdata_o = {{16{mem_data_i[15]}}, mem_data_i[15:0]};
								2'b10   : reg_wdata_o = {{16{mem_data_i[31]}}, mem_data_i[31:16]};
								default : reg_wdata_o = 0;
							endcase
						end
						`EXE_LW_OP : begin
							case (mem_addr_i[1:0])
								2'b00   : reg_wdata_o = mem_data_i;
								default : reg_wdata_o = 0;
							endcase
						end
						`EXE_LBU_OP : begin
							case (mem_addr_i[1:0])
								2'b00   : reg_wdata_o = {{24{1'b0}}, mem_data_i[7:0]};
								2'b01   : reg_wdata_o = {{24{1'b0}}, mem_data_i[15:8]};
								2'b10   : reg_wdata_o = {{24{1'b0}}, mem_data_i[23:16]};
								2'b11   : reg_wdata_o = {{24{1'b0}}, mem_data_i[31:24]};
                                default : reg_wdata_o = 0;
							endcase
						end
						`EXE_LHU_OP : begin
							case (mem_addr_i[1:0])
								2'b00   : reg_wdata_o = {{16{1'b0}}, mem_data_i[15:0]};
								2'b10   : reg_wdata_o = {{16{1'b0}}, mem_data_i[31:16]};
								default : reg_wdata_o = 0;
							endcase
						end
					endcase
				end
				
				// ================= 写内存 (Store) =================
				`EXE_SB_OP : begin
					mem_addr_o = {mem_addr_i[31:2], 2'b00}; // 强制 4 字节对齐
					mem_we     = 1'b1;
					mem_data_o = {4{rt_data[7:0]}}; // 把最低字节复制4份，靠sel掩码决定写哪个
					reg_wdata_o = 0;
					stallreq = !mem_acc_done;
					case (mem_addr_i[1:0])
						2'b00   : begin mem_sel = 4'b0001; mem_we = 1'b1; end
						2'b01   : begin mem_sel = 4'b0010; mem_we = 1'b1; end
						2'b10   : begin mem_sel = 4'b0100; mem_we = 1'b1; end
						2'b11   : begin mem_sel = 4'b1000; mem_we = 1'b1; end
						default : begin mem_sel = 4'b0000; mem_we = 1'b0; end
					endcase
				end
				`EXE_SH_OP : begin
					mem_addr_o = {mem_addr_i[31:2], 2'b00}; // 强制 4 字节对齐
					mem_we     = 1'b1;
					mem_data_o = {2{rt_data[15:0]}};
					reg_wdata_o = 0;
					stallreq = !mem_acc_done;
					case (mem_addr_i[1:0])
						2'b00   : begin mem_sel = 4'b0011; mem_we = 1'b1; end
						2'b10   : begin mem_sel = 4'b1100; mem_we = 1'b1; end
						default : begin mem_sel = 4'b0000; mem_we = 1'b0; end
					endcase
				end
				`EXE_SW_OP : begin
					mem_addr_o = {mem_addr_i[31:2], 2'b00}; // 强制 4 字节对齐
					mem_we     = 1'b1;
					mem_data_o = rt_data;
					reg_wdata_o = 0;
					stallreq = !mem_acc_done;
					case (mem_addr_i[1:0])
						2'b00   : begin mem_sel = 4'b1111; mem_we = 1'b1; end 
						default : begin mem_sel = 4'b0000; mem_we = 1'b0; end
					endcase
				end
				default : begin
					reg_wdata_o = reg_wdata_i;
				end
			endcase
		end
	end
endmodule