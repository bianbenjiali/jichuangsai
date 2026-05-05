`include "defines.v"

module reg_pc (
	input  wire                clk        ,
	input  wire                rst        ,
	input  wire [         5:0] stall      ,
	input  wire                br         ,
	input  wire [`InstAddrBus] br_addr    ,
	input  wire                pred_taken_i,
	input  wire [`InstAddrBus] pred_addr_i ,
	output reg  [`InstAddrBus] pc_o       ,
	output wire [`InstAddrBus] next_pc_o
);

	//reg [`InstAddrBus] pc       ;

	// 1. 组合逻辑：立刻计算出“下一拍”是什么地址
    // 这个逻辑不经过寄存器，所以能抵消 RAM 的一周期延时
	assign next_pc_o = (rst) ? 32'h00000000 :
                       (br && !stall[2]) ? br_addr :
                       (pred_taken_i && !stall[0]) ? pred_addr_i :
                       (!stall[0]) ? (pc_o + 4) :
                       pc_o; // 停顿执行时保持当前地址

    // 2. 时序逻辑：只维护当前流水线的 pc_o
    always @ (posedge clk) begin
        if (rst) begin
            pc_o <= 32'h00000000;
        end else begin
            pc_o <= next_pc_o;
        end
    end

	/*always @ (posedge clk) begin
		if (rst) begin
			pc_o <= 32'h00000000; // 复位时从地址 0 开始执行
		end else if (br && !stall[2]) begin		
			pc_o <= br_addr; // 分支跳转
		end else if (!stall[0]) begin
			if(pred_taken_i) begin
				pc_o <= pred_addr_i; // 预测跳转
			end else begin
				pc_o <= pc_o + 4; // 顺序执行
			end
		end
	end*/
	
	/*always @ (posedge clk) begin
		if (!rst && br) begin	
			pc <= br_addr;
		end else if (!rst && !stall[0]) begin
			if (pred_taken_i) begin
				pc <= pred_addr_i;
			end else begin
				pc <= pc + 4;
			end
		end
		if (rst) begin
			pc_o      <= 0;
			pc        <= 4;
		end else if (!stall[0]) begin
			//$display("PC now: %h", pc);
			pc_o <= pc;
		end
	end*/

	/*always @ (posedge clk) begin
		if (rst) begin
			pc_o <= 0;
		end else if (!stall[0]) begin
			if (br) pc_o <= br_addr;
			else pc_o <= pc_o + 4;
		end
	end*/

endmodule // reg_pc