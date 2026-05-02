`include "defines.v"

module stage_id (
	input  wire                rst          ,
	input  wire [`InstAddrBus] pc           ,
	input  wire [    `InstBus] inst         ,
	input  wire [     `RegBus] reg_data1    ,
	input  wire [     `RegBus] reg_data2    ,
	// forwarding
	input  wire [   `AluOpBus] ex_aluop     ,
	input  wire                ex_we        ,
	input  wire [     `RegBus] ex_reg_wdata ,
	input  wire [ `RegAddrBus] ex_reg_waddr ,
	input  wire                mem_we       ,
	input  wire [     `RegBus] mem_reg_wdata,
	input  wire [ `RegAddrBus] mem_reg_waddr,
	output reg                 re1          ,
	output reg                 re2          ,
	output reg  [ `RegAddrBus] reg_addr1    ,
	output reg  [ `RegAddrBus] reg_addr2    ,
	output reg  [   `AluOpBus] aluop        ,
	output reg  [  `AluSelBus] alusel       ,
	output reg  [     `RegBus] opv1         ,
	output reg  [     `RegBus] opv2         ,
	output reg  [ `RegAddrBus] reg_waddr    ,
	output reg                 we           ,
	output wire                stallreq     ,
	output reg                 br           ,
	output reg  [`InstAddrBus] br_addr      ,
	output reg  [`InstAddrBus] link_addr    ,
	output reg  [     `RegBus] mem_offset   ,
	// 来自分支预测单元的信息
	input  wire                id_pred_taken,
    input  wire [`InstAddrBus] id_pred_addr,
    
    // 新增：输出给 BPU 的真实结果（用于更新）
    output wire                bpu_upd_en_o,
    output wire                bpu_upd_taken_o,
    output wire [`InstAddrBus] bpu_upd_addr_o
);

	wire[6:0] opcode = inst[6:0];
	wire[2:0] funct3 = inst[14:12];
	wire[6:0] funct7 = inst[31:25];
	wire[11:0] I_imm = inst[31:20];
	wire[19:0] U_imm = inst[31:12];
	wire[11:0] S_imm = {inst[31:25], inst[11:7]};
	reg[31:0] imm1;
	reg[31:0] imm2;
	reg inst_valid;

	wire[`RegBus] rd = inst[11:7];
	wire[`RegBus] rs = inst[19:15];
	wire[`RegBus] rt = inst[24:20];

	reg stallreq_for_reg1_load;
	reg stallreq_for_reg2_load;
	assign stallreq = stallreq_for_reg1_load || stallreq_for_reg2_load;

	wire prev_is_load;
	assign prev_is_load = (ex_aluop == `EXE_LB_OP)  || 
                          (ex_aluop == `EXE_LH_OP)  ||
                          (ex_aluop == `EXE_LW_OP)  ||
                          (ex_aluop == `EXE_LBU_OP) ||
                          (ex_aluop == `EXE_LHU_OP);

    wire[`InstAddrBus] reg1_plus_I_imm;
    wire[`InstAddrBus] pc_plus_J_imm;
    wire[`InstAddrBus] pc_plus_B_imm;
    wire[`InstAddrBus] pc_plus_4;
    assign reg1_plus_I_imm = opv1 + {{20{I_imm[11]}}, I_imm};
    assign pc_plus_J_imm = pc + {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
   	assign pc_plus_B_imm = pc + {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign pc_plus_4 = pc + 4;

    wire reg1_reg2_eq;
    wire reg1_reg2_ne;
    wire reg1_reg2_lt;
    wire reg1_reg2_ltu;
    wire reg1_reg2_ge;
    wire reg1_reg2_geu;
    assign reg1_reg2_eq = (opv1 == opv2);
    assign reg1_reg2_ne = (opv1 != opv2);
	assign reg1_reg2_lt = ($signed(opv1) < $signed(opv2));
	assign reg1_reg2_ltu = (opv1 < opv2);
	assign reg1_reg2_ge = ($signed(opv1) >= $signed(opv2));
	assign reg1_reg2_geu = (opv1 >= opv2);

	reg is_branch_inst; // 这条指令到底是不是分支/跳转指令？
    reg actual_taken;   // 实际上到底跳没跳？
    reg [31:0] actual_addr; // 实际上跳去哪了？

	`define SET_INST(i_alusel, i_aluop, i_inst_valid, i_re1, i_reg_addr1, i_re2, i_reg_addr2, i_we, i_reg_waddr, i_imm1, i_imm2, i_mem_offset) \
		aluop = i_aluop; \
		alusel = i_alusel; \
		inst_valid = i_inst_valid; \
		re1 = i_re1; \
		reg_addr1 = i_reg_addr1; \
		re2 = i_re2; \
		reg_addr2 = i_reg_addr2; \
		we = i_we; \
		reg_waddr = i_reg_waddr; \
		imm1 = i_imm1; \
		imm2 = i_imm2; \
		mem_offset = i_mem_offset;

/*`define SET_BRANCH(i_br, i_br_addr, i_link_addr) \
		actual_taken = i_br; \
		actual_addr = i_br_addr; \
		link_addr = i_link_addr; \
        is_branch_inst = 1; // 只要调了这个宏，说明它就是个跳转指令！*/

	always @ (*) begin
		if (rst) begin
			`SET_INST(`EXE_RES_NOP, `EXE_NOP_OP, 1, 0, rs, 0, rt, 0, rd, 0, 0, 0)
			is_branch_inst = 1'b0;
			actual_taken = 1'b0;
			actual_addr = 0;
			link_addr = 0;
		end else begin
			`SET_INST(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
			is_branch_inst = 1'b0;
			actual_taken = 1'b0;
			actual_addr = 0;
			link_addr = 0;
			case (opcode)
				`OP_LUI : begin
					`SET_INST(`EXE_RES_ARITH, `EXE_ADD_OP, 1, 0, 0, 0, 0, 1, rd, ({U_imm, 12'b0}), 0, 0)
				end
				`OP_AUIPC : begin
					`SET_INST(`EXE_RES_ARITH, `EXE_ADD_OP, 1, 0, 0, 0, 0, 1, rd, ({U_imm, 12'b0}), pc, 0)
				end
				`OP_JAL : begin
					`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_JAL_OP, 1, 0, 0, 0, 0, 1, rd, 0, 0, 0)
					is_branch_inst = 1'b1;
					actual_taken = 1'b1;
					actual_addr = pc_plus_J_imm;
					link_addr = pc_plus_4;
				end
				`OP_JALR : begin
					`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_JALR_OP, 1, 1, rs, 0, 0, 1, rd, 0, 0, 0)
					is_branch_inst = 1'b1;
					actual_taken = 1'b1;
					actual_addr = reg1_plus_I_imm & ~32'h1; // JALR 的目标地址要把最低位置0
					link_addr = pc_plus_4;
				end
				`OP_BRANCH : begin
					is_branch_inst = 1'b1;
					actual_addr = pc_plus_B_imm; // 先算出分支目标地址，后面再根据条件决定要不要跳
					case (funct3)
						`FUNCT3_BEQ : begin
							`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_BEQ_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, 0)
							actual_taken = reg1_reg2_eq;
						end
						`FUNCT3_BNE : begin
							`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_BNE_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, 0)
							actual_taken = reg1_reg2_ne;
						end
						`FUNCT3_BLT : begin
							`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_BLT_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, 0)
							actual_taken = reg1_reg2_lt;
						end
						`FUNCT3_BGE : begin
							`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_BGE_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, 0)
							actual_taken = reg1_reg2_ge;
						end
						`FUNCT3_BLTU : begin
							`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_BLTU_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, 0)
							actual_taken = reg1_reg2_ltu;
						end
						`FUNCT3_BGEU : begin
							`SET_INST(`EXE_RES_JUMP_BRANCH, `EXE_BGEU_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, 0)
							actual_taken = reg1_reg2_geu;
						end
						default : begin
						end
					endcase // funct3
				end
				`OP_LOAD : begin
					case (funct3)
						`FUNCT3_LB : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_LB_OP, 1, 1, rs, 0, 0, 1, rd, 0, 0, ({{20{I_imm[11]}}, I_imm}))
						end
						`FUNCT3_LH : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_LH_OP, 1, 1, rs, 0, 0, 1, rd, 0, 0, ({{20{I_imm[11]}}, I_imm}))
						end
						`FUNCT3_LW : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_LW_OP, 1, 1, rs, 0, 0, 1, rd, 0, 0, ({{20{I_imm[11]}}, I_imm}))
						end
						`FUNCT3_LBU : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_LBU_OP, 1, 1, rs, 0, 0, 1, rd, 0, 0, ({{20{I_imm[11]}}, I_imm}))
						end
						`FUNCT3_LHU : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_LHU_OP, 1, 1, rs, 0, 0, 1, rd, 0, 0, ({{20{I_imm[11]}}, I_imm}))
						end
						default : begin
						end
					endcase // funct3
				end
				`OP_STORE : begin
					case (funct3)
						`FUNCT3_SB : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_SB_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, ({{20{S_imm[11]}}, S_imm}))
						end
						`FUNCT3_SH : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_SH_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, ({{20{S_imm[11]}}, S_imm}))
						end
						`FUNCT3_SW : begin
							`SET_INST(`EXE_RES_LOAD_STORE, `EXE_SW_OP, 1, 1, rs, 1, rt, 0, 0, 0, 0, ({{20{S_imm[11]}}, S_imm}))
						end
						default : begin
						end
					endcase // funct3
				end
				`OP_OP_IMM : begin
					case (funct3)
						`FUNCT3_ADDI : begin
							`SET_INST(`EXE_RES_ARITH, `EXE_ADD_OP, 1, 1, rs, 0, 0, 1, rd, 0, ({{20{I_imm[11]}}, I_imm}), 0)
						end
						`FUNCT3_SLTI : begin
							`SET_INST(`EXE_RES_ARITH, `EXE_SLT_OP, 1, 1, rs, 0, 0, 1, rd, 0, ({{20{I_imm[11]}}, I_imm}), 0)
						end
						`FUNCT3_SLTIU : begin
							`SET_INST(`EXE_RES_ARITH, `EXE_SLTU_OP, 1, 1, rs, 0, 0, 1, rd, 0, ({{20{I_imm[11]}}, I_imm}), 0)
						end
						`FUNCT3_XORI : begin
							`SET_INST(`EXE_RES_LOGIC, `EXE_XOR_OP, 1, 1, rs, 0, 0, 1, rd, 0, ({{20{I_imm[11]}}, I_imm}), 0)
						end
						`FUNCT3_ORI : begin
							`SET_INST(`EXE_RES_LOGIC, `EXE_OR_OP, 1, 1, rs, 0, 0, 1, rd, 0, ({{20{I_imm[11]}}, I_imm}), 0)
						end
						`FUNCT3_ANDI : begin
							`SET_INST(`EXE_RES_LOGIC, `EXE_AND_OP, 1, 1, rs, 0, 0, 1, rd, 0, ({{20{I_imm[11]}}, I_imm}), 0)
						end
						`FUNCT3_SLLI : begin
							`SET_INST(`EXE_RES_SHIFT, `EXE_SLL_OP, 1, 1, rs, 0, 0, 1, rd, 0, rt, 0)
						end
						`FUNCT3_SRLI_SRAI : begin
							case (funct7)
								`FUNCT7_SRLI : begin
									`SET_INST(`EXE_RES_SHIFT, `EXE_SRL_OP, 1, 1, rs, 0, 0, 1, rd, 0, rt, 0)
								end
								`FUNCT7_SRAI : begin
									`SET_INST(`EXE_RES_SHIFT, `EXE_SRA_OP, 1, 1, rs, 0, 0, 1, rd, 0, rt, 0)
								end
								default : begin
								end
							endcase
						end
						default : begin
						end
					endcase // funct3
				end
				`OP_OP : begin
					if (funct7 == `FUNCT7_M) begin
						case (funct3)
							`FUNCT3_MUL : begin
								`SET_INST(`EXE_RES_MUL, `EXE_MUL_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_MULH : begin
								`SET_INST(`EXE_RES_MUL, `EXE_MULH_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_MULHSU : begin
								`SET_INST(`EXE_RES_MUL, `EXE_MULHSU_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_MULHU : begin
								`SET_INST(`EXE_RES_MUL, `EXE_MULHU_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_DIV : begin
								`SET_INST(`EXE_RES_MUL, `EXE_DIV_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_DIVU : begin
								`SET_INST(`EXE_RES_MUL, `EXE_DIVU_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_REM : begin
								`SET_INST(`EXE_RES_MUL, `EXE_REM_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_REMU : begin
								`SET_INST(`EXE_RES_MUL, `EXE_REMU_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							default: begin
							end
						endcase
					end else begin
						case (funct3)
							`FUNCT3_ADD_SUB : begin
								case (funct7)
									`FUNCT7_ADD : begin
										`SET_INST(`EXE_RES_ARITH, `EXE_ADD_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
									end
									`FUNCT7_SUB : begin
										`SET_INST(`EXE_RES_ARITH, `EXE_SUB_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
									end
									default : begin
									end
								endcase // funct7
							end
							`FUNCT3_SLL : begin
								`SET_INST(`EXE_RES_SHIFT, `EXE_SLL_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_SLT : begin
								`SET_INST(`EXE_RES_ARITH, `EXE_SLT_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_SLTU : begin
								`SET_INST(`EXE_RES_ARITH, `EXE_SLTU_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_XOR : begin
								`SET_INST(`EXE_RES_LOGIC, `EXE_XOR_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_SRL_SRA : begin
								case (funct7)
									`FUNCT7_SRL : begin
										`SET_INST(`EXE_RES_SHIFT, `EXE_SRL_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
									end
									`FUNCT7_SRA : begin
										`SET_INST(`EXE_RES_SHIFT, `EXE_SRA_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
									end
									default : begin
									end
								endcase // funct7
							end
							`FUNCT3_OR : begin
								`SET_INST(`EXE_RES_LOGIC, `EXE_OR_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							`FUNCT3_AND : begin
								`SET_INST(`EXE_RES_LOGIC, `EXE_AND_OP, 1, 1, rs, 1, rt, 1, rd, 0, 0, 0)
							end
							default : begin
							end
						endcase
					end // funct3
				end
				`OP_MISC_MEM : begin
				end
				default      : begin
				end
			endcase // op
		end // end else
	end // always @ (*)

	`define SET_OPV(opv, re, reg_addr, reg_data, imm, stallreq) \
		stallreq = 0; \
		if(rst) begin \
			opv = 0; \
		end else if (re && (reg_addr == 0)) begin \
			opv = 0; \
		end else if (re && prev_is_load && (ex_reg_waddr == reg_addr)) begin \
			stallreq = 1; \
		end else if (re && ex_we && (ex_reg_waddr == reg_addr)) begin \
			opv = ex_reg_wdata; \
		end else if (re && mem_we && (mem_reg_waddr == reg_addr)) begin \
			opv = mem_reg_wdata; \
		end else if(re) begin \
			opv = reg_data; \
		end else if(!re) begin \
			opv = imm; \
		end else begin \
			opv = 0; \
		end

	always @ (*) begin
		`SET_OPV(opv1, re1, reg_addr1, reg_data1, imm1, stallreq_for_reg1_load)
	end

	always @ (*) begin
		`SET_OPV(opv2, re2, reg_addr2, reg_data2, imm2, stallreq_for_reg2_load)
	end

    always @(*) begin
        br = 0;
        br_addr = 0;
        
        if (is_branch_inst) begin
            // 情况 1：猜跳没跳的方向猜错了
            if (id_pred_taken != actual_taken) begin
                br = 1; 
                // 如果实际要跳，那就按实际的跳；如果实际没跳，那就回到 PC+4 的正轨上
                br_addr = actual_taken ? actual_addr : (pc + 4);
                
            // 情况 2：方向猜对了，但跳去的地址猜错了
            end else if (actual_taken && (id_pred_addr != actual_addr)) begin
                br = 1;
                br_addr = actual_addr;
            end
        end
    end

    // ----------------------------------------------------
    // 发送成绩单，让 BPU 长经验
    // ----------------------------------------------------
    assign bpu_upd_en_o    = is_branch_inst; // 只要是分支指令，就去更新
    assign bpu_upd_taken_o = actual_taken;   // 告诉它到底跳没跳
    assign bpu_upd_addr_o  = actual_addr;    // 告诉它真实的地址

endmodule // stage_id