`timescale 1ns/1ps
//==============================================================================
// riscv_core.v : 5-stage pipelined RV32I core
//
//   IF  -> ID  -> EX  -> MEM -> WB
//
//  Hazard handling
//   * Data hazards      : forwarding from EX/MEM and MEM/WB into EX
//   * Load-use hazard   : 1-cycle stall (PC and IF/ID frozen, bubble into EX)
//   * Control hazards   : branches/jumps resolved in EX, predict-not-taken,
//                         2 wrongly fetched instructions are flushed on a taken branch
//  Registers named  <from>_<to>_<signal>  hold values between pipeline stages.
//  The *_instr and *_valid registers exist only for debug / CPI measurement.
//==============================================================================
module riscv_core (
    input  wire        clk,
    input  wire        rst_n,

    // instruction memory port
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // data memory port
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_we,
    output wire [2:0]  dmem_funct3,
    input  wire [31:0] dmem_rdata
);
    localparam [31:0] NOP = 32'h0000_0013;

    //==========================================================================
    // Global control wires
    //==========================================================================
    wire        stall;            // load-use hazard
    wire        ex_redirect;      // taken branch / jump resolved in EX
    wire [31:0] ex_target;        // where to go

    //==========================================================================
    // IF : instruction fetch
    //==========================================================================
    reg  [31:0] pc;
    assign imem_addr = pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           pc <= 32'd0;
        else if (ex_redirect) pc <= ex_target;
        else if (!stall)      pc <= pc + 32'd4;
    end

    // ---------------- IF/ID pipeline register ----------------
    reg [31:0] if_id_pc, if_id_instr;
    reg        if_id_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc <= 32'd0;  if_id_instr <= NOP;  if_id_valid <= 1'b0;
        end else if (ex_redirect) begin                 // flush wrong-path instruction
            if_id_pc <= 32'd0;  if_id_instr <= NOP;  if_id_valid <= 1'b0;
        end else if (!stall) begin
            if_id_pc <= pc;     if_id_instr <= imem_data; if_id_valid <= 1'b1;
        end                                             // stall: hold
    end

    //==========================================================================
    // ID : decode + register read
    //==========================================================================
    wire [4:0] id_rs1 = if_id_instr[19:15];
    wire [4:0] id_rs2 = if_id_instr[24:20];
    wire [4:0] id_rd  = if_id_instr[11:7];

    wire        id_reg_write, id_mem_read, id_mem_write, id_mem_to_reg;
    wire [1:0]  id_alu_a_sel;
    wire        id_alu_b_sel;
    wire [3:0]  id_alu_ctrl;
    wire        id_is_branch, id_is_jal, id_is_jalr, id_uses_rs1, id_uses_rs2;
    wire [31:0] id_imm, id_rs1_data, id_rs2_data;

    // write-back wires (declared here, driven in WB)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    control_unit u_ctrl (
        .instr(if_id_instr),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg), .alu_a_sel(id_alu_a_sel), .alu_b_sel(id_alu_b_sel),
        .alu_ctrl(id_alu_ctrl), .is_branch(id_is_branch), .is_jal(id_is_jal),
        .is_jalr(id_is_jalr), .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2)
    );

    imm_gen u_imm (.instr(if_id_instr), .imm(id_imm));

    regfile u_regfile (
        .clk(clk), .we(wb_reg_write), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2), .rdata1(id_rs1_data), .rdata2(id_rs2_data)
    );

    // load-use hazard detection (uses ID/EX registers declared below)
    reg        id_ex_mem_read;
    reg [4:0]  id_ex_rd;

    hazard_unit u_hazard (
        .id_ex_mem_read(id_ex_mem_read), .id_ex_rd(id_ex_rd),
        .if_id_rs1(id_rs1), .if_id_rs2(id_rs2),
        .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2),
        .stall(stall)
    );

    // ---------------- ID/EX pipeline register ----------------
    reg [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm, id_ex_instr;
    reg [4:0]  id_ex_rs1, id_ex_rs2;
    reg [2:0]  id_ex_funct3;
    reg        id_ex_reg_write, id_ex_mem_write, id_ex_mem_to_reg;
    reg [1:0]  id_ex_alu_a_sel;
    reg        id_ex_alu_b_sel;
    reg [3:0]  id_ex_alu_ctrl;
    reg        id_ex_is_branch, id_ex_is_jal, id_ex_is_jalr, id_ex_valid;

    wire id_bubble = stall || ex_redirect;     // insert a bubble (NOP) into EX

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || id_bubble) begin
            id_ex_pc <= 32'd0;  id_ex_rs1_data <= 32'd0;  id_ex_rs2_data <= 32'd0;
            id_ex_imm <= 32'd0; id_ex_instr <= NOP;
            id_ex_rs1 <= 5'd0;  id_ex_rs2 <= 5'd0;  id_ex_rd <= 5'd0;  id_ex_funct3 <= 3'd0;
            id_ex_reg_write <= 1'b0;  id_ex_mem_read <= 1'b0;  id_ex_mem_write <= 1'b0;
            id_ex_mem_to_reg <= 1'b0; id_ex_alu_a_sel <= 2'd0; id_ex_alu_b_sel <= 1'b0;
            id_ex_alu_ctrl <= 4'd0;
            id_ex_is_branch <= 1'b0;  id_ex_is_jal <= 1'b0;   id_ex_is_jalr <= 1'b0;
            id_ex_valid <= 1'b0;
        end else begin
            id_ex_pc <= if_id_pc;  id_ex_rs1_data <= id_rs1_data;  id_ex_rs2_data <= id_rs2_data;
            id_ex_imm <= id_imm;   id_ex_instr <= if_id_instr;
            id_ex_rs1 <= id_rs1;   id_ex_rs2 <= id_rs2;  id_ex_rd <= id_rd;
            id_ex_funct3 <= if_id_instr[14:12];
            id_ex_reg_write <= id_reg_write;   id_ex_mem_read <= id_mem_read;
            id_ex_mem_write <= id_mem_write;   id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_alu_a_sel <= id_alu_a_sel;   id_ex_alu_b_sel <= id_alu_b_sel;
            id_ex_alu_ctrl <= id_alu_ctrl;
            id_ex_is_branch <= id_is_branch;   id_ex_is_jal <= id_is_jal;
            id_ex_is_jalr <= id_is_jalr;       id_ex_valid <= if_id_valid;
        end
    end

    //==========================================================================
    // EX : execute, forwarding, branch resolution
    //==========================================================================
    reg [31:0] ex_mem_result, ex_mem_store_data, ex_mem_instr;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_mem_to_reg, ex_mem_valid;

    wire [1:0] fwd_a, fwd_b;

    reg        mem_wb_reg_write;
    reg [4:0]  mem_wb_rd;

    forwarding_unit u_fwd (
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
        .ex_mem_rd(ex_mem_rd), .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd(mem_wb_rd), .mem_wb_reg_write(mem_wb_reg_write),
        .fwd_a(fwd_a), .fwd_b(fwd_b)
    );

    wire [31:0] ex_rs1 = (fwd_a == 2'b10) ? ex_mem_result :
                         (fwd_a == 2'b01) ? wb_data       : id_ex_rs1_data;
    wire [31:0] ex_rs2 = (fwd_b == 2'b10) ? ex_mem_result :
                         (fwd_b == 2'b01) ? wb_data       : id_ex_rs2_data;

    wire [31:0] alu_a = (id_ex_alu_a_sel == 2'd1) ? id_ex_pc :
                        (id_ex_alu_a_sel == 2'd2) ? 32'd0    : ex_rs1;
    wire [31:0] alu_b = id_ex_alu_b_sel ? id_ex_imm : ex_rs2;
    wire [31:0] alu_result;

    alu u_alu (.a(alu_a), .b(alu_b), .ctrl(id_ex_alu_ctrl), .y(alu_result));

    // JAL/JALR write PC+4 (return address) to rd instead of the ALU result
    wire        ex_link   = id_ex_is_jal | id_ex_is_jalr;
    wire [31:0] ex_result = ex_link ? (id_ex_pc + 32'd4) : alu_result;

    // branch condition
    reg br_cond;
    always @* begin
        case (id_ex_funct3)
            3'b000:  br_cond = (ex_rs1 == ex_rs2);                          // BEQ
            3'b001:  br_cond = (ex_rs1 != ex_rs2);                          // BNE
            3'b100:  br_cond = ($signed(ex_rs1) <  $signed(ex_rs2));        // BLT
            3'b101:  br_cond = ($signed(ex_rs1) >= $signed(ex_rs2));        // BGE
            3'b110:  br_cond = (ex_rs1 <  ex_rs2);                          // BLTU
            3'b111:  br_cond = (ex_rs1 >= ex_rs2);                          // BGEU
            default: br_cond = 1'b0;
        endcase
    end

    assign ex_redirect = (id_ex_is_branch & br_cond) | id_ex_is_jal | id_ex_is_jalr;
    assign ex_target   = id_ex_is_jalr ? ((ex_rs1 + id_ex_imm) & 32'hFFFF_FFFE)
                                       : (id_ex_pc + id_ex_imm);

    // ---------------- EX/MEM pipeline register ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_result <= 32'd0;  ex_mem_store_data <= 32'd0;  ex_mem_instr <= NOP;
            ex_mem_rd <= 5'd0;       ex_mem_funct3 <= 3'd0;
            ex_mem_reg_write <= 1'b0; ex_mem_mem_read <= 1'b0; ex_mem_mem_write <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0; ex_mem_valid <= 1'b0;
        end else begin
            ex_mem_result <= ex_result;       ex_mem_store_data <= ex_rs2;
            ex_mem_instr <= id_ex_instr;      ex_mem_rd <= id_ex_rd;
            ex_mem_funct3 <= id_ex_funct3;
            ex_mem_reg_write <= id_ex_reg_write;   ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;   ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_valid <= id_ex_valid;
        end
    end

    //==========================================================================
    // MEM : data memory access
    //==========================================================================
    assign dmem_addr   = ex_mem_result;
    assign dmem_wdata  = ex_mem_store_data;
    assign dmem_we     = ex_mem_mem_write;
    assign dmem_funct3 = ex_mem_funct3;

    // ---------------- MEM/WB pipeline register ----------------
    reg [31:0] mem_wb_result, mem_wb_mem_data, mem_wb_instr;
    reg        mem_wb_mem_to_reg, mem_wb_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_result <= 32'd0;  mem_wb_mem_data <= 32'd0;  mem_wb_instr <= NOP;
            mem_wb_rd <= 5'd0;       mem_wb_reg_write <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0; mem_wb_valid <= 1'b0;
        end else begin
            mem_wb_result <= ex_mem_result;   mem_wb_mem_data <= dmem_rdata;
            mem_wb_instr <= ex_mem_instr;     mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_valid <= ex_mem_valid;
        end
    end

    //==========================================================================
    // WB : write back
    //==========================================================================
    assign wb_data      = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_result;
    assign wb_rd        = mem_wb_rd;
    assign wb_reg_write = mem_wb_reg_write;

    //==========================================================================
    // Performance counters (for CPI measurement)
    //==========================================================================
    reg [31:0] cycle_count, instret_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cycle_count <= 32'd0; instret_count <= 32'd0; end
        else begin
            cycle_count <= cycle_count + 32'd1;
            if (mem_wb_valid) instret_count <= instret_count + 32'd1;
        end
    end

endmodule