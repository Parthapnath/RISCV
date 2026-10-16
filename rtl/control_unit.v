`timescale 1ns/1ps
//==============================================================================
// control_unit.v : main decoder (opcode -> control signals)
//  alu_a_sel : 0 = rs1, 1 = PC, 2 = zero
//  alu_b_sel : 0 = rs2, 1 = immediate
//  FENCE / ECALL / EBREAK are decoded as NOPs (not needed for this core)
//==============================================================================
module control_unit (
    input  wire [31:0] instr,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_to_reg,
    output reg  [1:0]  alu_a_sel,
    output reg         alu_b_sel,
    output reg  [3:0]  alu_ctrl,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         uses_rs1,
    output reg         uses_rs2
);
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;

    localparam ALU_ADD  = 4'd0, ALU_SUB = 4'd1, ALU_SLL = 4'd2, ALU_SLT = 4'd3,
               ALU_SLTU = 4'd4, ALU_XOR = 4'd5, ALU_SRL = 4'd6, ALU_SRA = 4'd7,
               ALU_OR   = 4'd8, ALU_AND = 4'd9;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire       alt    = instr[30];          // SUB / SRA select bit

    always @* begin
        // safe defaults = a NOP
        reg_write  = 1'b0;  mem_read  = 1'b0;  mem_write = 1'b0;  mem_to_reg = 1'b0;
        alu_a_sel  = 2'd0;  alu_b_sel = 1'b0;  alu_ctrl  = ALU_ADD;
        is_branch  = 1'b0;  is_jal    = 1'b0;  is_jalr   = 1'b0;
        uses_rs1   = 1'b0;  uses_rs2  = 1'b0;

        case (opcode)
            OP_LUI:    begin reg_write = 1; alu_a_sel = 2'd2; alu_b_sel = 1; end
            OP_AUIPC:  begin reg_write = 1; alu_a_sel = 2'd1; alu_b_sel = 1; end
            OP_JAL:    begin reg_write = 1; is_jal  = 1; end
            OP_JALR:   begin reg_write = 1; is_jalr = 1; uses_rs1 = 1; end
            OP_BRANCH: begin is_branch = 1; uses_rs1 = 1; uses_rs2 = 1; end
            OP_LOAD:   begin reg_write = 1; mem_read = 1; mem_to_reg = 1;
                             alu_b_sel = 1; uses_rs1 = 1; end
            OP_STORE:  begin mem_write = 1; alu_b_sel = 1; uses_rs1 = 1; uses_rs2 = 1; end
            OP_IMM, OP_REG: begin
                reg_write = 1;
                uses_rs1  = 1;
                if (opcode == OP_REG) uses_rs2 = 1;
                else                  alu_b_sel = 1;
                case (funct3)
                    3'b000: alu_ctrl = (opcode == OP_REG && alt) ? ALU_SUB : ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = alt ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                endcase
            end
            default: ;   // FENCE, SYSTEM, unknown -> NOP
        endcase
    end
endmodule