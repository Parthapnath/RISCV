`timescale 1ns/1ps
//==============================================================================
// imm_gen.v : immediate generator (I, S, B, U, J formats)
//==============================================================================
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];

    always @* begin
        case (opcode)
            7'b0010011,                                   // OP-IMM
            7'b0000011,                                   // LOAD
            7'b1100111: imm = {{20{instr[31]}}, instr[31:20]};                       // JALR  (I-type)
            7'b0100011: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};          // STORE (S-type)
            7'b1100011: imm = {{19{instr[31]}}, instr[31], instr[7],
                               instr[30:25], instr[11:8], 1'b0};                     // BRANCH (B-type)
            7'b0110111,                                   // LUI
            7'b0010111: imm = {instr[31:12], 12'b0};                                 // AUIPC (U-type)
            7'b1101111: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                               instr[20], instr[30:21], 1'b0};                       // JAL (J-type)
            default:    imm = 32'd0;
        endcase
    end
endmodule