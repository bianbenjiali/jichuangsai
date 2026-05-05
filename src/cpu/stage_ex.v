`include "defines.v"

module stage_ex (
	input  wire                clk        ,
	input  wire                rst        ,
	input  wire [   `AluOpBus] aluop      ,
	input  wire [  `AluSelBus] alusel     ,
	input  wire [     `RegBus] opv1       ,
	input  wire [     `RegBus] opv2       ,
	input  wire [ `RegAddrBus] reg_waddr_i,
	input  wire                we_i       ,
	input  wire [`InstAddrBus] link_addr  ,
	input  wire [     `RegBus] mem_offset ,
	output reg  [ `RegAddrBus] reg_waddr_o,
	output reg                 we_o       ,
	output reg  [     `RegBus] reg_wdata  ,
	output reg                 stallreq   ,
	output reg  [ `MemAddrBus] mem_addr   ,
	output wire [   `AluOpBus] ex_aluop   ,
	output wire [     `RegBus] rt_data	  ,
	output reg                 csr_we_o,
    output reg  [11:0]  	   csr_waddr_o,
    output reg  [31:0]         csr_wdata_o,
    
    output reg                 trap_en_o,
    output reg  [31:0]         trap_epc_o,
    output reg  [31:0]         trap_cause_o,
	output reg  [31:0]         trap_tval_o,
    output reg                 mret_en_o
);

	assign ex_aluop = aluop;
	assign rt_data  = opv2;

	reg[`RegBus] logic_out;
	reg[`RegBus] shift_out;
	reg[`RegBus] arith_out;
	reg[`RegBus] mem_out;
	reg[`RegBus] mul_out;
	reg[`RegBus] csr_out; // 准备写回 rd 寄存器的 CSR 旧值

	// 1. 有符号 * 有符号
	wire signed [63:0] mul_signed_signed = $signed(opv1) * $signed(opv2);
	// 2. 无符号 * 无符号
	wire [63:0] mul_unsigned_unsigned = opv1 * opv2;
	// 3. 有符号 * 无符号 (先把无符号数扩展成有符号数，再乘)
	wire signed[63:0] mul_signed_unsigned = $signed(opv1) * $signed({1'b0, opv2});

	wire div_start;
	wire div_is_signed;
	wire [31:0] div_quotient;
	wire [31:0] div_remainder;
	wire div_ready;

	// EXE_RES_LOGIC
	always @ (*) begin
		if(rst || alusel != `EXE_RES_LOGIC) begin
			logic_out = 0;
		end else begin
			case (aluop)
				`EXE_XOR_OP : begin
					logic_out = opv1 ^ opv2;
				end
				`EXE_OR_OP : begin
					logic_out = opv1 | opv2;
				end
				`EXE_AND_OP : begin
					logic_out = opv1 & opv2;
				end
				default : begin
					logic_out = 0;
				end
			endcase // aluop
		end // end else
	end // always @ (*)

	// EXE_RES_SHIFT
	always @ (*) begin
		if(rst || alusel != `EXE_RES_SHIFT) begin
			shift_out = 0;
		end else begin
			case (aluop)
				`EXE_SLL_OP : begin
					shift_out = opv1 << opv2[4:0];
				end
				`EXE_SRL_OP : begin
					shift_out = opv1 >> opv2[4:0];
				end
				`EXE_SRA_OP : begin
					shift_out = ({32{opv1[31]}} << {6'd32 - {1'b0, opv2[4:0]}}) |
								 (opv1 >> opv2[4:0]);
				end
				default : begin
					shift_out = 0;
				end
			endcase // aluop
		end // end else
	end // always @ (*)

	// EXE_RES_ARITH
	always @ (*) begin
		if(rst || alusel != `EXE_RES_ARITH) begin
			arith_out = 0;
		end else begin
			case (aluop)
				`EXE_ADD_OP : begin
					arith_out = opv1 + opv2;
				end
				`EXE_SUB_OP : begin
					arith_out = opv1 - opv2;
				end
				`EXE_SLT_OP : begin
					arith_out = $signed(opv1) < $signed(opv2);
				end
				`EXE_SLTU_OP : begin
					arith_out = opv1 < opv2;
				end
				default : begin
					arith_out = 0;
				end
			endcase // aluop
		end // end else
	end // always @ (*)

	// EXE_RES_MUL
	always @(*) begin
		if (rst || alusel != `EXE_RES_MUL) begin
			mul_out = 0;
		end else begin
			case (aluop)
				`EXE_MUL_OP: begin
					mul_out = mul_signed_signed[31:0];
				end
				`EXE_MULH_OP: begin
					mul_out = mul_signed_signed[63:32];
				end
				`EXE_MULHSU_OP: begin
					mul_out = mul_signed_unsigned[63:32];
				end
				`EXE_MULHU_OP: begin
					mul_out = mul_unsigned_unsigned[63:32];
				end
				default: begin
					mul_out = 0;
				end
			endcase
		end
	end

	//EXE_RES_DIV
	assign div_start = (alusel == `EXE_RES_MUL) && 
					   (aluop == `EXE_DIV_OP || aluop == `EXE_DIVU_OP || 
					    aluop == `EXE_REM_OP || aluop == `EXE_REMU_OP);
	assign div_is_signed = (aluop == `EXE_DIV_OP || aluop == `EXE_REM_OP);

	div div0 (
		.clk        (clk),
		.rst        (rst),
		.start      (div_start),
		.is_signed  (div_is_signed),
		.dividend   (opv1),
		.divisor    (opv2),
		.quotient   (div_quotient),
		.remainder  (div_remainder),
		.ready      (div_ready)
	);


	// EXE_RES_LOAD_STORE
	always @ (*) begin
		if(rst || alusel != `EXE_RES_LOAD_STORE) begin
			mem_out = 0;
		end else begin
			mem_out = opv1 + mem_offset;
		end // end else
	end // always @ (*)

    // EXE_RES_CSR
    always @(*) begin
        csr_we_o = 0; csr_waddr_o = 0; csr_wdata_o = 0;
        trap_en_o = 0; trap_epc_o = 0; trap_cause_o = 0; trap_tval_o = 0; mret_en_o = 0;
        csr_out = opv2; // opv2 里存的就是 ID 阶段顺过来的 CSR 旧数据

        if (alusel == `EXE_RES_CSR) begin
            csr_we_o    = (aluop != `EXE_CSR_READ_ONLY_OP);
            csr_waddr_o = mem_offset[11:0]; // mem_offset 里存的是 CSR 地址
            case (aluop)
                `EXE_CSRRW_OP: csr_wdata_o = opv1;
                `EXE_CSRRS_OP: csr_wdata_o = opv2 | opv1;
                `EXE_CSRRC_OP: csr_wdata_o = opv2 & ~opv1;
				default : csr_wdata_o = 0; // 其他情况不写 CSR
            endcase
        end else if (aluop == `EXE_ECALL_OP) begin
            trap_en_o    = 1'b1;
            trap_epc_o   = link_addr - 4; // 🚨 妙笔：link_addr 是 PC+4，减 4 刚好是当前 ecall 的 PC！
            trap_cause_o = 32'd11;        // M 模式下的 ECALL 异常号是 11
            trap_tval_o  = 0;             // ECALL 不产生错误值
        end else if (aluop == `EXE_MRET_OP) begin
            mret_en_o    = 1'b1;
        end
    end

	always @ (*) begin
		stallreq    = 0;
		reg_waddr_o = reg_waddr_i;
		we_o        = we_i;
		mem_addr    = 0;
		reg_wdata    = 0;
		if (div_start && !div_ready) begin
			stallreq = 1; // 除法开始了但还没准备好结果，要求暂停
		end else begin
			stallreq = 0; // 其他情况不 stall
		end
		case (alusel)
			`EXE_RES_LOGIC : begin
				//$display("EXE_RES_LOGIC");
				reg_wdata = logic_out;
			end
			`EXE_RES_SHIFT : begin
				//$display("EXE_RES_SHIFT");
				reg_wdata = shift_out;
			end
			`EXE_RES_ARITH : begin
				//$display("EXE_RES_ARITH");
				reg_wdata = arith_out;
			end
			`EXE_RES_JUMP_BRANCH : begin
				//$display("EXE_RES_JUMP_BRANCH: %d", link_addr);
				reg_wdata = link_addr;
			end
			`EXE_RES_LOAD_STORE : begin
				//$display("EXE_RES_LOAD_STORE");
				reg_wdata = 0;
				mem_addr  = mem_out;
			end
			`EXE_RES_MUL : begin
				case (aluop)
					`EXE_MUL_OP, `EXE_MULH_OP, `EXE_MULHSU_OP, `EXE_MULHU_OP: begin
						reg_wdata = mul_out;
					end
					`EXE_DIV_OP, `EXE_DIVU_OP: begin
						reg_wdata = div_quotient;
					end
					`EXE_REM_OP, `EXE_REMU_OP: begin
						reg_wdata = div_remainder;
					end
					default: begin
						reg_wdata = 0;
					end
				endcase
			end
			`EXE_RES_CSR : begin
				reg_wdata = csr_out; // CSR 指令写回 rd 的是 CSR 旧值
			end
			default : begin
				reg_wdata = 0;
			end
		endcase // alusel
	end // always @ (*)


endmodule // stage_ex