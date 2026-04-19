// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
// Date        : Sun Apr 19 17:14:06 2026
// Host        : LAPTOP-7G2ET7IJ running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               f:/vivadoproogram/riscv_cpu_code_storage/riscv_cpu_code_storage.srcs/sources_1/ip/dmem/dmem_stub.v
// Design      : dmem
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z020clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_2,Vivado 2018.3" *)
module dmem(clka, wea, addra, dina, clkb, enb, addrb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,wea[0:0],addra[12:0],dina[31:0],clkb,enb,addrb[12:0],doutb[31:0]" */;
  input clka;
  input [0:0]wea;
  input [12:0]addra;
  input [31:0]dina;
  input clkb;
  input enb;
  input [12:0]addrb;
  output [31:0]doutb;
endmodule
