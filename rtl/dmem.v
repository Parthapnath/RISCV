`timescale 1ns/1ps
//==============================================================================
// dmem.v : data memory (byte/half/word access, asynchronous read,
//          synchronous write). Accesses must be naturally aligned.
//  funct3: 000 LB/SB, 001 LH/SH, 010 LW/SW, 100 LBU, 101 LHU
//==============================================================================
module dmem #(
    parameter ADDR_BITS = 10                    // 2**10 words = 4 KB
)(
    input  wire        clk,
    input  wire        we,
    input  wire [2:0]  funct3,
    input  wire [31:0] addr,                    // byte address
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);
    reg [31:0] mem [0:(1<<ADDR_BITS)-1];
    reg [31:0] tmp;
    integer i;
    initial for (i = 0; i < (1<<ADDR_BITS); i = i + 1) mem[i] = 32'd0;

    wire [ADDR_BITS-1:0] widx    = addr[ADDR_BITS+1:2];
    wire [1:0]           boff    = addr[1:0];
    wire [31:0]          word    = mem[widx];
    wire [31:0]          shifted = word >> {boff, 3'b000};

    // ---------------- write (read-modify-write of one word) ----------------
    always @(posedge clk) begin
        if (we) begin
            tmp = mem[widx];
            case (funct3[1:0])
                2'b00: case (boff)                                  // SB
                           2'd0: tmp[7:0]   = wdata[7:0];
                           2'd1: tmp[15:8]  = wdata[7:0];
                           2'd2: tmp[23:16] = wdata[7:0];
                           2'd3: tmp[31:24] = wdata[7:0];
                       endcase
                2'b01: if (boff[1]) tmp[31:16] = wdata[15:0];       // SH
                       else         tmp[15:0]  = wdata[15:0];
                default: tmp = wdata;                               // SW
            endcase
            mem[widx] <= tmp;
        end
    end

    // ---------------- read (with sign / zero extension) ----------------
    always @* begin
        case (funct3)
            3'b000:  rdata = {{24{shifted[7]}},  shifted[7:0]};     // LB
            3'b001:  rdata = {{16{shifted[15]}}, shifted[15:0]};    // LH
            3'b100:  rdata = {24'd0, shifted[7:0]};                 // LBU
            3'b101:  rdata = {16'd0, shifted[15:0]};                // LHU
            default: rdata = word;                                  // LW
        endcase
    end
endmodule