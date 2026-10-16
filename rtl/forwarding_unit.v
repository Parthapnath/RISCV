`timescale 1ns/1ps
//==============================================================================
// forwarding_unit.v : data forwarding for the EX stage
//  fwd = 2'b10 : take value from EX/MEM (instruction 1 ahead)
//  fwd = 2'b01 : take value from MEM/WB (instruction 2 ahead)
//  fwd = 2'b00 : use the value read from the register file
//  EX/MEM has priority because it holds the newer result.
//==============================================================================
module forwarding_unit (
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,
    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,
    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,
    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);
    always @* begin
        fwd_a = 2'b00;
        fwd_b = 2'b00;

        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            fwd_a = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1))
            fwd_a = 2'b01;

        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            fwd_b = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            fwd_b = 2'b01;
    end
endmodule