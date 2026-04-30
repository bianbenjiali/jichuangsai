`include "defines.v"

module reg_pc (
	input  wire                clk        ,
	input  wire                rst        ,
	input  wire [         5:0] stall      ,
	input  wire                br         ,
	input  wire [`InstAddrBus] br_addr    ,
	input  wire                pred_taken_i,
	input  wire [`InstAddrBus] pred_addr_i ,
	output reg  [`InstAddrBus] pc_o       
);

	//reg [`InstAddrBus] pc       ;

	always @ (posedge clk) begin
		if (rst) begin
			pc_o <= 32'h00000000; // 复位时从地址 0 开始执行
		end else if (!stall[0]) begin
			if (br) begin
				pc_o <= br_addr; // 分支跳转
			end else if (pred_taken_i) begin
				pc_o <= pred_addr_i; // 预测跳转
			end else begin
				pc_o <= pc_o + 4; // 顺序执行
			end
		end
	end
	
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