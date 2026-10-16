`timescale 1ns/1ps
//==============================================================================
// regfile.v : 32 x 32-bit register file, 2 read ports, 1 write port
//  - x0 always reads as zero and ignores writes
//  - Write-through: if the write-back stage writes a register in the same
//    cycle the decode stage reads it, the new value is returned (solves the
//    3-instruction-apart data hazard without extra logic)
//==============================================================================
module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);
    reg [31:0] regs [0:31];

    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;   // simulation only

    always @(posedge clk)
        if (we && (waddr != 5'd0)) regs[waddr] <= wdata;

    assign rdata1 = (raddr1 == 5'd0)               ? 32'd0 :
                    (we && (waddr == raddr1))      ? wdata :
                                                     regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0)               ? 32'd0 :
                    (we && (waddr == raddr2))      ? wdata :
                                                     regs[raddr2];
endmodule