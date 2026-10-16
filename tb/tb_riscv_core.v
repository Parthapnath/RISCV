`timescale 1ns/1ps
//==============================================================================
// tb_riscv_core.v : self-checking testbench for the 5-stage RV32I core
//
//  For each test program (tests/*.hex) the testbench:
//    1. clears memories/registers and loads the program into instruction memory
//    2. releases reset and runs until the final "j done" instruction retires
//    3. compares registers / data memory against hand-computed expected values
//    4. reports cycles, retired instructions and CPI
//==============================================================================
module tb_riscv_core;

    reg clk = 0, rst_n = 0;
    riscv_top dut (.clk(clk), .rst_n(rst_n));

    always #5 clk = ~clk;                          // 100 MHz

    integer i;
    integer errors_total = 0;
    integer test_errors, test_checks;
    integer cycles, retired, timeout;
    reg     finished;
    integer tot_cycles = 0, tot_retired = 0;

    // ---------------- helper tasks ----------------
    task check_reg(input integer n, input [31:0] expected);
        reg [31:0] got;
        begin
            got = dut.u_core.u_regfile.regs[n];
            test_checks = test_checks + 1;
            if (got !== expected) begin
                test_errors = test_errors + 1;
                $display("  [FAIL] x%0d = %h, expected %h", n, got, expected);
            end
        end
    endtask

    task check_mem(input integer byte_addr, input [31:0] expected);
        reg [31:0] got;
        begin
            got = dut.u_dmem.mem[byte_addr >> 2];
            test_checks = test_checks + 1;
            if (got !== expected) begin
                test_errors = test_errors + 1;
                $display("  [FAIL] mem[%0d] = %h, expected %h", byte_addr, got, expected);
            end
        end
    endtask

    task run_program(input [8*32-1:0] fname, input integer nwords);
        begin
            rst_n = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                dut.u_imem.mem[i] = 32'h0000_0013;
                dut.u_dmem.mem[i] = 32'd0;
            end
            for (i = 0; i < 32; i = i + 1) dut.u_core.u_regfile.regs[i] = 32'd0;
            $readmemh(fname, dut.u_imem.mem, 0, nwords-1);
            repeat (3) @(negedge clk);
            rst_n = 1;

            finished = 0; timeout = 0;
            while (!finished && timeout < 50000) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (dut.u_core.mem_wb_valid && dut.u_core.mem_wb_instr == 32'h0000_006f)
                    finished = 1;                   // the final "j done" reached write-back
            end
            @(posedge clk); #1;                     // let it be counted as retired
            cycles  = dut.u_core.cycle_count;
            retired = dut.u_core.instret_count;
            tot_cycles  = tot_cycles  + cycles;
            tot_retired = tot_retired + retired;
            test_errors = 0; test_checks = 0;
            if (!finished) begin
                test_errors = 1;
                $display("  [FAIL] TIMEOUT: program never reached its final loop");
            end
        end
    endtask

    task report(input [8*32-1:0] name);
        begin
            errors_total = errors_total + test_errors;
            if (test_errors == 0)
                $display("[PASS] %0s : %0d checks | %0d cycles, %0d instructions, CPI = %0d.%02d",
                         name, test_checks, cycles, retired,
                         (cycles*100/retired)/100, (cycles*100/retired)%100);
            else
                $display("[FAIL] %0s : %0d of %0d checks failed", name, test_errors, test_checks);
        end
    endtask

    // ---------------- main ----------------
    initial begin
        $dumpfile("sim/cpu.vcd");
        $dumpvars(0, tb_riscv_core);

        // ===== TEST 1: ALU, immediates, shifts, LUI/AUIPC, x0 =====
        run_program("tests/test_alu.hex", 27);
        check_reg( 0, 32'h0000_0000);   // x0 stays zero
        check_reg( 1, 32'd10);          check_reg( 2, 32'd3);
        check_reg( 3, 32'd13);          check_reg( 4, 32'd7);
        check_reg( 5, 32'd2);           check_reg( 6, 32'd11);
        check_reg( 7, 32'd9);           check_reg( 8, 32'd80);
        check_reg( 9, 32'd1);           check_reg(10, 32'hFFFF_FFF0);
        check_reg(11, 32'hFFFF_FFFE);   check_reg(12, 32'h1FFF_FFFE);
        check_reg(13, 32'd1);           check_reg(14, 32'd0);
        check_reg(15, 32'd1);           check_reg(16, 32'd0);
        check_reg(17, 32'd245);         check_reg(18, 32'd122);
        check_reg(19, 32'd2);           check_reg(20, 32'd48);
        check_reg(21, 32'd15);          check_reg(22, 32'hFFFF_FFFC);
        check_reg(23, 32'h1234_5678);   check_reg(24, 32'h0000_1060);
        report("test_alu");

        // ===== TEST 2: forwarding, load-use, byte/half access, branches, jumps =====
        run_program("tests/test_hazard.hex", 56);
        check_reg( 1, 32'd3);           check_reg( 2, 32'd6);
        check_reg( 3, 32'd9);           check_reg( 4, 32'd256);
        check_reg( 5, 32'd42);          // overwritten inside the called function
        check_reg( 6, 32'd18);          // load-use hazard result (9+9); 0xFFFFFFFF would mean 'bad' ran
        check_reg( 7, 32'hFFFF_FFFE);   check_reg( 8, 32'hFFFF_FFFE);   // LB sign-extends
        check_reg( 9, 32'd254);         // LBU zero-extends
        check_reg(10, 32'hFFFF_FFFE);   // LH sign-extends
        check_reg(11, 32'd65534);       // LHU zero-extends
        check_reg(12, 32'h0000_FFFE);
        check_reg(13, 32'd85);          check_reg(14, 32'h0000_5500);   // SB into byte lane 1
        check_reg(15, 32'd9);           check_reg(16, 32'd9);           // load -> store
        check_reg(17, 32'd5);           check_reg(18, 32'd5);
        check_reg(19, 32'd0);           // flushed after taken BEQ
        check_reg(20, 32'd1);           check_reg(21, 32'd2);
        check_reg(22, 32'd0);           check_reg(23, 32'd0);           // skipped by taken branches
        check_reg(24, 32'hFFFF_FFFF);
        check_reg(25, 32'd0);           check_reg(26, 32'd0);
        check_reg(27, 32'd55);          // loop: 1+2+...+10
        check_reg(28, 32'd11);
        check_reg(29, 32'd11);
        check_reg(30, 32'd192);         // JAL return address
        check_reg(31, 32'd7);           // executed after JALR returned
        check_mem(256, 32'd9);          check_mem(260, 32'h0000_00FE);
        check_mem(264, 32'h0000_FFFE);  check_mem(268, 32'h0000_5500);
        check_mem(272, 32'd9);
        report("test_hazard");

        // ===== TEST 3: bubble sort of 8 words in data memory =====
        run_program("tests/test_sort.hex", 31);
        check_mem(256, 32'd1);  check_mem(260, 32'd2);  check_mem(264, 32'd3);  check_mem(268, 32'd4);
        check_mem(272, 32'd6);  check_mem(276, 32'd7);  check_mem(280, 32'd8);  check_mem(284, 32'd9);
        report("test_sort");

        $display("--------------------------------------------------");
        $display("Total: %0d cycles, %0d instructions, overall CPI = %0d.%02d",
                 tot_cycles, tot_retired,
                 (tot_cycles*100/tot_retired)/100, (tot_cycles*100/tot_retired)%100);
        if (errors_total == 0) $display("*** RISC-V CORE: ALL TESTS PASSED ***");
        else                   $display("*** RISC-V CORE: %0d ERRORS ***", errors_total);
        $finish;
    end
endmodule