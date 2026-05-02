`include "defines.v"

module reg_if_id (
	input  wire                clk    ,
	input  wire                rst    ,
	input  wire [`InstAddrBus] if_pc  ,
	input  wire [    `InstBus] if_inst,
	input  wire [         5:0] stall  ,
	input  wire                br     ,
	input  wire                if_pred_taken,
	input  wire [`InstAddrBus] if_pred_addr,
	output reg  [`InstAddrBus] id_pc  ,
	output reg  [    `InstBus] id_inst,
	output reg                 id_pred_taken,
	output reg  [`InstAddrBus] id_pred_addr
);

	always @ (posedge clk) begin
		if (rst || (br && !stall[2]) || (stall[1] && !stall[2])) begin
			id_pc   <= 0;
			id_inst <= 0;
			id_pred_taken <= 0;
			id_pred_addr <= 0;
		end else if (!stall[1]) begin
			id_pc   <= if_pc;
			id_inst <= if_inst;
			id_pred_taken <= if_pred_taken;
			id_pred_addr <= if_pred_addr;
		end
	end

endmodule // reg_if_id