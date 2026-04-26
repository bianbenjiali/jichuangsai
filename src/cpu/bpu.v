`timescale 1ns/1ps
`include "defines.v"

module bpu(
    input  wire clk,
    input  wire rst,

    input  wire [`InstAddrBus] pc_i,        // 当前 IF 阶段即将要取的 PC
    output wire                pred_taken_o, // 预测的分支是否被采取 (1: 预测跳转，0: 预测不跳转)
    output wire [`InstAddrBus] pred_addr_o,  // 预测的跳转目标地址

    input  wire                upd_en_o,    // ID 阶段发现是一条分支指令
    input  wire [`InstAddrBus] upd_pc_i,    // ID 阶段的分支指令的 PC
    input  wire                upd_taken_i, // ID 阶段的分支指令实际是否被采取
    input  wire [`InstAddrBus] upd_addr_i,  // ID 阶段的分支指令的实际跳转目标地址
);

    // 提取 PC 的[6:2] 位作为“页码” (共 5 位，对应 32 行)
    wire [4:0] pred_idx = pc_i[6:2];
    wire [4:0] upd_idx  = upd_pc_i[6:2];

    // BTB 表与 BHT 表
    reg [24:0]          btb_tag   [0:31]; // 记录 PC 的高位防伪
    reg [`InstAddrBus]  btb_target[0:31]; // 记录上次跳去了哪里
    reg [1:0]           bht_state [0:31]; // 2-bit 饱和计数器
    reg                 valid     [0:31]; // 有效位

    integer i;

    // 预测逻辑
    wire hit = valid[pred_idx] && (btb_tag[pred_idx] == pc_i[31:7]); 
    
    assign pred_taken_o = hit && (bht_state[pred_idx][1] == 1'b1);
    assign pred_addr_o  = btb_target[pred_idx];

    // 更新逻辑
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                valid[i]     <= 1'b0;
                bht_state[i] <= 2'b01; 
            end
        end else if (upd_en_i) begin
            valid[upd_idx]      <= 1'b1;
            btb_tag[upd_idx]    <= upd_pc_i[31:7];
            btb_target[upd_idx] <= upd_addr_i;

            // 2-bit 状态机更新
            if (upd_taken_i) begin
                if (bht_state[upd_idx] != 2'b11) bht_state[upd_idx] <= bht_state[upd_idx] + 2'b01;
            end else begin
                if (bht_state[upd_idx] != 2'b00) bht_state[upd_idx] <= bht_state[upd_idx] - 2'b01;
            end
        end
    end
endmodule