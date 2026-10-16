`timescale 1ns/1ps
//==============================================================================
// riscv_top.v : CPU core + instruction memory + data memory (Harvard)
//==============================================================================
module riscv_top (
    input wire clk,
    input wire rst_n
);
    wire [31:0] imem_addr, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we;
    wire [2:0]  dmem_funct3;

    riscv_core u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_we(dmem_we),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata)
    );

    imem u_imem (.addr(imem_addr), .instr(imem_data));

    dmem u_dmem (
        .clk(clk), .we(dmem_we), .funct3(dmem_funct3),
        .addr(dmem_addr), .wdata(dmem_wdata), .rdata(dmem_rdata)
    );
endmodule