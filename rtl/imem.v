`timescale 1ns/1ps
//==============================================================================
// imem.v : instruction memory (word-addressed ROM model, asynchronous read)
//  Filled with NOPs at time 0; the testbench loads a program with $readmemh.
//==============================================================================
module imem #(
    parameter ADDR_BITS = 10                    // 2**10 words = 4 KB
)(
    input  wire [31:0] addr,                    // byte address (PC)
    output wire [31:0] instr
);
    reg [31:0] mem [0:(1<<ADDR_BITS)-1];

    integer i;
    initial for (i = 0; i < (1<<ADDR_BITS); i = i + 1) mem[i] = 32'h0000_0013;  // NOP

    assign instr = mem[addr[ADDR_BITS+1:2]];
endmodule