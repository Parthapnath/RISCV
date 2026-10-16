`timescale 1ns/1ps
//==============================================================================
// hazard_unit.v : load-use hazard detection
//  A load's data only exists after the MEM stage, so an instruction that needs
//  it in the very next cycle must wait one cycle (stall). After the stall the
//  value is forwarded from MEM/WB.
//==============================================================================
module hazard_unit (
    input  wire       id_ex_mem_read,   // instruction in EX is a load
    input  wire [4:0] id_ex_rd,
    input  wire [4:0] if_id_rs1,
    input  wire [4:0] if_id_rs2,
    input  wire       uses_rs1,         // instruction in ID really reads rs1
    input  wire       uses_rs2,
    output wire       stall
);
    assign stall = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                   ( (uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                     (uses_rs2 && (id_ex_rd == if_id_rs2)) );
endmodule