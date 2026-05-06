`timescale 1ns/1ps
`include "defines.v"

module cpu_core (
	input  wire clk,
	input  wire rst,
	
	// --- 指令存储器(ROM)接口 ---
	output wire [31:0] inst_addr_o,   // CPU想取哪条指令
	input  wire [31:0] inst_data_i,   // ROM返回的指令机器码
	output wire        inst_re_o,     // 读使能
	
	// --- 数据存储器(RAM)/外设总线接口 ---
	output wire [31:0] data_addr_o,   // CPU想读写哪个内存/外设地址
	output wire [31:0] data_wdata_o,  // CPU想写的数据
	input  wire [31:0] data_rdata_i,  // RAM/外设返回的数据
	output wire        data_we_o,     // 写使能 (为1时写，为0时只读)
	output wire [ 3:0] data_be_o      // 字节掩码 (Byte Enable)
);

	// -------- 以下是 CPU 内部连接线 --------
	wire[5:0] stall;
	wire stallreq_if, stallreq_id, stallreq_ex, stallreq_mem;

	// PC
	wire[`InstAddrBus] pc;
	wire br;
	wire[`InstAddrBus] br_addr;

	// IF/ID
	wire[`MemAddrBus] if_pc;
	wire[`InstBus] if_inst;
	wire[`InstAddrBus] id_pc;
	wire[`InstBus] id_inst;

	// ID/EX
	wire id_re1, id_re2, id_we;
	wire[`RegBus] id_reg_data1, id_reg_data2, id_opv1, id_opv2, id_mem_offset;
	wire[`RegAddrBus] id_reg_addr1, id_reg_addr2, id_reg_waddr;
	wire[`AluOpBus] id_aluop;
	wire[`AluSelBus] id_alusel;
	wire[`InstAddrBus] id_link_addr;

	wire ex_we_i;
	wire[`AluOpBus] ex_aluop;
	wire[`AluSelBus] ex_alusel;
	wire[`RegBus] ex_opv1, ex_opv2, ex_mem_offset;
	wire[`RegAddrBus] ex_reg_waddr_i;
	wire[`InstAddrBus] ex_link_addr_i;

	// EX/MEM
	wire ex_we_o;
	wire[`RegAddrBus] ex_reg_waddr_o;
	wire[`RegBus] ex_reg_wdata, ex_rt_data;
	wire[`MemAddrBus] ex_mem_addr;
	wire[`AluOpBus] ex_aluop_o;

	wire mem_we_i;
	wire[`RegAddrBus] mem_reg_waddr_i;
	wire[`RegBus] mem_reg_wdata_i, mem_rt_data;
	wire[`MemAddrBus] mem_mem_addr;
	wire[`AluOpBus] mem_aluop;

	// MEM/WB
	wire mem_we_o;
	wire[`RegAddrBus] mem_reg_waddr_o;
	wire[`RegBus] mem_reg_wdata_o;

	wire wb_we;
	wire[`RegAddrBus] wb_reg_waddr;
	wire[`RegBus] wb_reg_wdata;

	//BPU连线
    wire pred_taken;
    wire [`InstAddrBus] pred_addr;
    wire id_pred_taken;
    wire [`InstAddrBus] id_pred_addr;
    
    // BPU 更新连线 (从 stage_id 出来的信号)
    wire bpu_upd_en;
    wire bpu_upd_taken;
    wire [`InstAddrBus] bpu_upd_addr;

	// CSR 相关连线
	wire[31:0] csr_rdata, csr_mtvec, csr_mepc;
	wire[11:0] csr_raddr, csr_waddr;
	wire [31:0] csr_wdata;
	wire        csr_we;
	// EX 级 CSR 写与 ID 级 CSR 读同址：csr_reg 仍为旧值，用 EX _wdata 旁路到 ID（stall 会冻住 EX 导致死锁）
	wire        id_is_csr_access;
	wire        csr_ex_to_id_fwd;
	wire [31:0] csr_rdata_to_id;
	assign id_is_csr_access = (id_inst[6:0] == `OP_SYSTEM) && (id_inst[14:12] != 3'b000);
	assign csr_ex_to_id_fwd = csr_we && id_is_csr_access && (id_inst[31:20] == csr_waddr);
	assign csr_rdata_to_id  = csr_ex_to_id_fwd ? csr_wdata : csr_rdata;
    
	wire        trap_en, mret_en;
	wire [31:0] trap_epc, trap_cause, trap_tval;
    
    // 指令退休标志 (用于 mcycle / minstret 计数)
    wire        inst_ret_en;
    // 【简化策略】：对于极简 CPU，只要没卡住，就可以近似认为执行了一条指令
    assign      inst_ret_en = !stall[0];

    
    // 一些没用上的线，接地即可
    wire mem_re_temp; 

	// -------- 实例化5个阶段和段间寄存器 --------

	ctrl ctrl0 (
		.rst(rst), .stallreq_if(stallreq_if), .stallreq_id(stallreq_id),
		.stallreq_ex(stallreq_ex), .stallreq_mem(stallreq_mem), .stall(stall)
	);

	reg_pc reg_pc0 (
		.clk(clk), .rst(rst), .stall(stall), .br(br), .br_addr(br_addr),
		.pc_o(pc), .pred_taken_i(pred_taken), .pred_addr_i(pred_addr)
	);

	bpu bpu0(
        .clk         (clk),
        .rst         (rst),
        // 预测端口 (连给 IF 阶段和 PC)
        .pc_i        (pc),
        .pred_taken_o(pred_taken),
        .pred_addr_o (pred_addr),
        // 更新端口 (接来自 ID 阶段的真实判决结果)
        .upd_en_i    (bpu_upd_en),
        .upd_pc_i    (id_pc),
        .upd_taken_i (bpu_upd_taken),
        .upd_addr_i  (bpu_upd_addr)
    );

	stage_if stage_if0 (
		.clk(clk), .rst(rst), .pc_i(pc), .stall(stall),
        .mem_data_i(inst_data_i),  // 直接接外部ROM数据
		.br(br), 
		.mem_re(inst_re_o),        // 直接接外部ROM使能
        .mem_addr_o(inst_addr_o),  // 直接接外部ROM地址
		.pc_o(if_pc), .inst_o(if_inst), .stallreq(stallreq_if)
	);

	reg_if_id reg_if_id0 (
		.clk(clk), .rst(rst), .if_pc(if_pc), .if_inst(if_inst),
		.stall(stall), .br(br), .if_pred_taken(pred_taken), .if_pred_addr(pred_addr),
		.id_pc(id_pc), .id_inst(id_inst), .id_pred_taken(id_pred_taken), .id_pred_addr(id_pred_addr)
	);

	stage_id stage_id0 (
		.rst(rst), .pc(id_pc), .inst(id_inst), .reg_data1(id_reg_data1), .reg_data2(id_reg_data2),
		.ex_aluop(ex_aluop), .ex_we(ex_we_o), .ex_reg_wdata(ex_reg_wdata), .ex_reg_waddr(ex_reg_waddr_o),
		.mem_we(mem_we_o), .mem_reg_wdata(mem_reg_wdata_o), .mem_reg_waddr(mem_reg_waddr_o),
		.re1(id_re1), .re2(id_re2), .reg_addr1(id_reg_addr1), .reg_addr2(id_reg_addr2),
		.aluop(id_aluop), .alusel(id_alusel), .opv1(id_opv1), .opv2(id_opv2),
		.we(id_we), .reg_waddr(id_reg_waddr), .stallreq(stallreq_id),
		.br(br), .br_addr(br_addr), .link_addr(id_link_addr), .mem_offset(id_mem_offset),
		.id_pred_taken(id_pred_taken), .id_pred_addr(id_pred_addr),
		.bpu_upd_en_o(bpu_upd_en), .bpu_upd_taken_o(bpu_upd_taken), .bpu_upd_addr_o(bpu_upd_addr),
		.csr_rdata_i(csr_rdata_to_id),.csr_mtvec_i(csr_mtvec),.csr_mepc_i(csr_mepc),.csr_raddr_o(csr_raddr)
	);

	regfile regfile0 (
		.clk(clk), .rst(rst),
		.we(wb_we), .waddr(wb_reg_waddr), .wdata(wb_reg_wdata),
		.re1(id_re1), .re2(id_re2), .raddr1(id_reg_addr1), .raddr2(id_reg_addr2),
		.rdata1(id_reg_data1), .rdata2(id_reg_data2)
	);

	reg_id_ex reg_id_ex0 (
		.clk(clk), .rst(rst),
		.id_aluop(id_aluop), .id_alusel(id_alusel), .id_opv1(id_opv1), .id_opv2(id_opv2),
		.id_reg_waddr(id_reg_waddr), .id_we(id_we), .id_link_addr(id_link_addr), .id_mem_offset(id_mem_offset),
		.stall(stall),
		.ex_aluop(ex_aluop), .ex_alusel(ex_alusel), .ex_opv1(ex_opv1), .ex_opv2(ex_opv2),
		.ex_reg_waddr(ex_reg_waddr_i), .ex_we(ex_we_i), .ex_link_addr(ex_link_addr_i), .ex_mem_offset(ex_mem_offset)
	);

	stage_ex stage_ex0 (
		.clk(clk), .rst(rst), .aluop(ex_aluop), .alusel(ex_alusel), .opv1(ex_opv1), .opv2(ex_opv2),
		.reg_waddr_i(ex_reg_waddr_i), .we_i(ex_we_i), .link_addr(ex_link_addr_i), .mem_offset(ex_mem_offset),
		.reg_waddr_o(ex_reg_waddr_o), .we_o(ex_we_o), .reg_wdata(ex_reg_wdata), .stallreq(stallreq_ex),
		.mem_addr(ex_mem_addr), .ex_aluop(ex_aluop_o), .rt_data(ex_rt_data),
		.csr_we_o(csr_we),.csr_waddr_o(csr_waddr),.csr_wdata_o(csr_wdata),.trap_en_o(trap_en),.trap_epc_o(trap_epc),.trap_cause_o(trap_cause),.trap_tval_o(trap_tval),.mret_en_o(mret_en)
	);

	reg_ex_mem reg_ex_mem0 (
		.clk(clk), .rst(rst),
		.ex_reg_waddr(ex_reg_waddr_o), .ex_we(ex_we_o), .ex_reg_wdata(ex_reg_wdata),
		.stall(stall), .ex_mem_addr(ex_mem_addr), .ex_aluop(ex_aluop_o), .ex_rt_data(ex_rt_data),
		.mem_reg_waddr(mem_reg_waddr_i), .mem_we(mem_we_i), .mem_reg_wdata(mem_reg_wdata_i),
		.mem_mem_addr(mem_mem_addr), .mem_aluop(mem_aluop), .mem_rt_data(mem_rt_data)
	);

	stage_mem stage_mem0 (
		.clk(clk), .rst(rst), .stall(stall),
		.reg_waddr_i(mem_reg_waddr_i), .we_i(mem_we_i), .reg_wdata_i(mem_reg_wdata_i),
		.mem_addr_i(mem_mem_addr), .aluop(mem_aluop), .rt_data(mem_rt_data),
        
        .mem_data_i(data_rdata_i), // 外部RAM传回的数据
        
		.reg_waddr_o(mem_reg_waddr_o), .we_o(mem_we_o), .reg_wdata_o(mem_reg_wdata_o),
        
		.mem_addr_o(data_addr_o),  // 送给外部RAM的地址
		.mem_re(mem_re_temp),
		.mem_we(data_we_o),        // 送给外部RAM的写使能
		.mem_sel(data_be_o),       // 送给外部RAM的掩码
		.mem_data_o(data_wdata_o), // 送给外部RAM的写数据
		.stallreq(stallreq_mem)
	);

	reg_mem_wb reg_mem_wb0 (
		.clk(clk), .rst(rst),
		.mem_reg_waddr(mem_reg_waddr_o), .mem_we(mem_we_o), .mem_reg_wdata(mem_reg_wdata_o),
		.stall(stall),
		.wb_reg_waddr(wb_reg_waddr), .wb_we(wb_we), .wb_reg_wdata(wb_reg_wdata)
	);

	csr_reg u_csr_reg (
		.clk         (clk),
		.rst         (rst),
		.we          (csr_we),
		.waddr       (csr_waddr),
		.wdata       (csr_wdata),
		.raddr       (csr_raddr),
		.rdata       (csr_rdata),
		.trap_en     (trap_en),
		.trap_epc    (trap_epc),
		.trap_cause  (trap_cause),
		.trap_tval   (trap_tval),
		.trap_vec    (csr_mtvec), // 注意这里，输出异常入口给 ID
		.mepc_o      (csr_mepc),  // 输出返回地址给 ID
		.mret_en     (mret_en),
		.inst_ret_en (inst_ret_en)
	);

endmodule