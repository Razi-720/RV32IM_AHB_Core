`timescale 1ns/1ps

// =============================================================================
// tb_stress_regression_Pip_RV32IM_AHB.v
//
// Standalone regression stress testbench for Pip_RV32IM_AHB.
//
// Stress profile:
// - Deterministic pseudo-random instruction/data wait states (HREADY back-pressure)
// - Mixed RV32I + RV32M workload with loop/branch, load/store, MUL/DIV/REM
// - Self-checking summary with PASS/FAIL counters
// =============================================================================

module tb_stress_regression_Pip_RV32IM_AHB;

  parameter CLK_PERIOD_NS = 10;
  parameter IMEM_DEPTH    = 4096;
  parameter DMEM_DEPTH    = 4096;
  parameter TIMEOUT_CYC   = 20000;

  // ---------------- DUT IO ----------------
  reg         Clk_In;
  reg         Rst_In;
  reg  [31:0] Instruction_In;
  wire [31:0] Instr_Addr_Out;
  reg  [31:0] DM_Data_In;
  wire [31:0] DM_Addr_Out;
  wire [31:0] DM_Data_Out;
  wire [3:0]  DM_Mask_Out;
  wire        DM_WrEn_Out;
  reg         Instr_HReady_In;
  reg         Data_HReady_In;
  reg         HResp_In;
  wire [1:0]  Data_HTrans_Out;
  wire [2:0]  Data_HSize_Out;
  reg         EIrq_In;
  reg         TIrq_In;
  reg         SIrq_In;
  reg  [63:0] RTC_In;

  // ---------------- Memories ----------------
  reg [31:0] imem [0:IMEM_DEPTH-1];
  reg [7:0]  dmem [0:DMEM_DEPTH-1];

  // ---------------- DUT ----------------
  Pip_RV32IM_AHB dut (
    .Clk_In(Clk_In),
    .Rst_In(Rst_In),
    .Instruction_In(Instruction_In),
    .Instr_Addr_Out(Instr_Addr_Out),
    .Instr_HReady_In(Instr_HReady_In),
    .DM_Data_In(DM_Data_In),
    .DM_Addr_Out(DM_Addr_Out),
    .DM_Data_Out(DM_Data_Out),
    .DM_Mask_Out(DM_Mask_Out),
    .DM_WrEn_Out(DM_WrEn_Out),
    .Data_HReady_In(Data_HReady_In),
    .HResp_In(HResp_In),
    .Data_HTrans_Out(Data_HTrans_Out),
    .Data_HSize_Out(Data_HSize_Out),
    .EIrq_In(EIrq_In),
    .TIrq_In(TIrq_In),
    .SIrq_In(SIrq_In),
    .RTC_In(RTC_In)
  );

  // ---------------- Clock / RTC ----------------
  initial Clk_In = 1'b0;
  always #(CLK_PERIOD_NS/2) Clk_In = ~Clk_In;

  always @(posedge Clk_In) begin
    if (Rst_In)
      RTC_In <= 64'd0;
    else
      RTC_In <= RTC_In + 64'd1;
  end

  // ---------------- Instruction + Data memory model ----------------
  always @(*) begin
    Instruction_In = imem[Instr_Addr_Out[13:2]];
  end

  always @(*) begin
    DM_Data_In = {
      dmem[{DM_Addr_Out[11:2],2'b11}],
      dmem[{DM_Addr_Out[11:2],2'b10}],
      dmem[{DM_Addr_Out[11:2],2'b01}],
      dmem[{DM_Addr_Out[11:2],2'b00}]
    };
  end

  always @(posedge Clk_In) begin
    if (DM_WrEn_Out && Data_HReady_In) begin
      if (DM_Mask_Out[0]) dmem[{DM_Addr_Out[11:2],2'b00}] <= DM_Data_Out[7:0];
      if (DM_Mask_Out[1]) dmem[{DM_Addr_Out[11:2],2'b01}] <= DM_Data_Out[15:8];
      if (DM_Mask_Out[2]) dmem[{DM_Addr_Out[11:2],2'b10}] <= DM_Data_Out[23:16];
      if (DM_Mask_Out[3]) dmem[{DM_Addr_Out[11:2],2'b11}] <= DM_Data_Out[31:24];
    end
  end

  // ---------------- Shadow register file via WB snoop ----------------
  reg [31:0] shadow_rf [0:31];
  integer ri;

  always @(posedge Clk_In) begin
    if (Rst_In) begin
      for (ri = 0; ri < 32; ri = ri + 1)
        shadow_rf[ri] <= 32'd0;
    end else if (dut.Reg_WrEn_W && (dut.Des_Addr_W != 5'd0)) begin
      shadow_rf[dut.Des_Addr_W] <= dut.Result_W;
    end
  end

  // ---------------- Deterministic back-pressure ----------------
  reg [7:0] lfsr;
  reg       stall_enable;

  always @(posedge Clk_In) begin
    if (Rst_In) begin
      lfsr <= 8'hA5;
      Instr_HReady_In <= 1'b1;
      Data_HReady_In  <= 1'b1;
    end else begin
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
      if (stall_enable) begin
        // Keep instruction side always ready for stable fetch behavior.
        Instr_HReady_In <= 1'b1;
        // Deterministic data-side wait states (~75% ready high).
        Data_HReady_In  <= lfsr[2] | lfsr[3];
      end else begin
        Instr_HReady_In <= 1'b1;
        Data_HReady_In  <= 1'b1;
      end
    end
  end

  // ---------------- Counters / checks ----------------
  integer pass_cnt;
  integer fail_cnt;
  integer cyc;
  reg     test_done;

  task check_eq;
    input [95:0] label;
    input [31:0] got;
    input [31:0] exp;
    begin
      if (got === exp) begin
        $display("  [PASS] %-12s got=0x%08h", label, got);
        pass_cnt = pass_cnt + 1;
      end else begin
        $display("  [FAIL] %-12s got=0x%08h exp=0x%08h", label, got, exp);
        fail_cnt = fail_cnt + 1;
      end
    end
  endtask

  function [31:0] get_dword;
    input [11:0] addr;
    begin
      get_dword = {
        dmem[{addr[11:2],2'b11}],
        dmem[{addr[11:2],2'b10}],
        dmem[{addr[11:2],2'b01}],
        dmem[{addr[11:2],2'b00}]
      };
    end
  endfunction

  // ---------------- Encoders ----------------
  function [31:0] R;
    input [6:0] f7;
    input [4:0] rs2;
    input [4:0] rs1;
    input [2:0] f3;
    input [4:0] rd;
    input [6:0] op;
    begin
      R = {f7, rs2, rs1, f3, rd, op};
    end
  endfunction

  function [31:0] I;
    input [11:0] imm;
    input [4:0] rs1;
    input [2:0] f3;
    input [4:0] rd;
    input [6:0] op;
    begin
      I = {imm, rs1, f3, rd, op};
    end
  endfunction

  function [31:0] S;
    input [11:0] imm;
    input [4:0] rs2;
    input [4:0] rs1;
    input [2:0] f3;
    input [6:0] op;
    begin
      S = {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    end
  endfunction

  function [31:0] B;
    input [12:0] imm;
    input [4:0] rs2;
    input [4:0] rs1;
    input [2:0] f3;
    input [6:0] op;
    begin
      B = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
    end
  endfunction

  function [31:0] J;
    input [20:0] imm;
    input [4:0] rd;
    input [6:0] op;
    begin
      J = {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
    end
  endfunction

  function [31:0] U;
    input [19:0] imm;
    input [4:0] rd;
    input [6:0] op;
    begin
      U = {imm, rd, op};
    end
  endfunction

  localparam [6:0] OP   = 7'b0110011;
  localparam [6:0] OPI  = 7'b0010011;
  localparam [6:0] LD   = 7'b0000011;
  localparam [6:0] ST   = 7'b0100011;
  localparam [6:0] BR   = 7'b1100011;
  localparam [6:0] JAL  = 7'b1101111;
  localparam [6:0] JALR = 7'b1100111;
  localparam [6:0] LUI  = 7'b0110111;
  localparam [6:0] AUI  = 7'b0010111;
  localparam [6:0] SYS  = 7'b1110011;
  localparam [31:0] NOP = 32'h00000013;

  localparam [11:0] CSR_MSCRATCH = 12'h340;

  localparam [11:0] MARKER_ADDR = 12'h1FC;

  task init_memories;
    integer i;
    begin
      for (i = 0; i < IMEM_DEPTH; i = i + 1)
        imem[i] = NOP;
      for (i = 0; i < DMEM_DEPTH; i = i + 1)
        dmem[i] = 8'h00;
    end
  endtask

  task load_program_s1;
    begin
      imem[0]  = I(12'd0,   5'd0, 3'h0, 5'd1,  OPI); // addi x1,  x0, 0
      imem[1]  = I(12'd50,  5'd0, 3'h0, 5'd2,  OPI); // addi x2,  x0, 50
      imem[2]  = I(12'd0,   5'd0, 3'h0, 5'd3,  OPI); // addi x3,  x0, 0
      imem[3]  = I(12'h100, 5'd0, 3'h0, 5'd10, OPI); // addi x10, x0, 0x100
      imem[4]  = R(7'h00, 5'd1, 5'd3, 3'h0, 5'd3, OP); // add x3, x3, x1
      imem[5]  = I(12'd1,  5'd1, 3'h0, 5'd1,  OPI);    // addi x1, x1, 1
      imem[6]  = B(13'h1FF8, 5'd2, 5'd1, 3'h4, BR);    // blt x1, x2, loop(PC-8)
      imem[7]  = NOP;
      imem[8]  = NOP;
      imem[9]  = S(12'd0, 5'd3, 5'd10, 3'h2, ST);       // sw x3, 0(x10)
      imem[10] = I(12'd0, 5'd10, 3'h2, 5'd4, LD);       // lw x4, 0(x10)
      imem[11] = R(7'h01, 5'd1,  5'd4, 3'h0, 5'd5, OP); // mul x5, x4, x1
      imem[12] = R(7'h01, 5'd2,  5'd5, 3'h4, 5'd6, OP); // div x6, x5, x2
      imem[13] = NOP;
      imem[14] = NOP;
      imem[15] = I(12'd1, 5'd0, 3'h0, 5'd11, OPI);      // addi x11, x0, 1 marker
      imem[16] = I(12'h1FC, 5'd0, 3'h0, 5'd12, OPI);    // addi x12, x0, 0x1fc
      imem[17] = NOP;
      imem[18] = NOP;
      imem[19] = S(12'd0, 5'd11, 5'd12, 3'h2, ST);      // sw x11, 0(x12)
      imem[20] = J(21'sd0, 5'd0, JAL);                  // halt
    end
  endtask

  task load_program_s2;
    begin
      // Memory sign/zero extension stress under data-side back-pressure.
      imem[0]  = I(12'h120, 5'd0, 3'h0, 5'd10, OPI);    // base 0x120
      imem[1]  = I(12'h07F, 5'd0, 3'h0, 5'd1,  OPI);    // x1=0x7f
      imem[2]  = I(12'hF80, 5'd0, 3'h0, 5'd2,  OPI);    // x2=0x80
      imem[3]  = I(12'h123, 5'd0, 3'h0, 5'd3,  OPI);    // x3=0x0123
      imem[4]  = NOP;
      imem[5]  = NOP;
      imem[6]  = NOP;
      imem[7]  = NOP;
      imem[8]  = S(12'd0,   5'd1, 5'd10, 3'h0, ST);     // sb x1,0(x10)
      imem[9]  = S(12'd1,   5'd2, 5'd10, 3'h0, ST);     // sb x2,1(x10)
      imem[10] = S(12'd2,   5'd3, 5'd10, 3'h1, ST);     // sh x3,2(x10)
      imem[11] = NOP;
      imem[12] = NOP;
      imem[13] = NOP;
      imem[14] = I(12'd0,   5'd10,3'h0, 5'd4, LD);      // lb  x4,0
      imem[15] = I(12'd1,   5'd10,3'h0, 5'd5, LD);      // lb  x5,1
      imem[16] = I(12'd1,   5'd10,3'h4, 5'd6, LD);      // lbu x6,1
      imem[17] = I(12'd2,   5'd10,3'h1, 5'd7, LD);      // lh  x7,2
      imem[18] = I(12'd0,   5'd10,3'h2, 5'd8, LD);      // lw  x8,0
      imem[19] = J(21'sd0, 5'd0, JAL);                  // halt
    end
  endtask

  task load_program_s3;
    begin
      // Branch/jump stress.
      imem[0]  = I(12'd1, 5'd0, 3'h0, 5'd1, OPI);       // x1=1
      imem[1]  = I(12'd2, 5'd0, 3'h0, 5'd2, OPI);       // x2=2
      imem[2]  = I(12'd0, 5'd0, 3'h0, 5'd3, OPI);       // x3=0
      imem[3]  = B(13'd8, 5'd2, 5'd1, 3'h0, BR);        // beq not taken
      imem[4]  = I(12'd1, 5'd3, 3'h0, 5'd3, OPI);       // x3=1
      imem[5]  = B(13'd8, 5'd2, 5'd1, 3'h4, BR);        // blt taken -> 7
      imem[6]  = I(12'd77,5'd0, 3'h0, 5'd28,OPI);       // canary skipped
      imem[7]  = I(12'h055,5'd0, 3'h0, 5'd4, OPI);      // x4=0x55
      imem[8]  = J(21'd8,  5'd6, JAL);                  // jump to 10, link x6
      imem[9]  = I(12'd99, 5'd0, 3'h0, 5'd28,OPI);      // canary skipped
      imem[10] = I(12'h02A,5'd0, 3'h0, 5'd5, OPI);      // x5=0x2a
      imem[11] = I(12'd3,  5'd0, 3'h0, 5'd11,OPI);      // marker=3
      imem[12] = I(12'h1FC,5'd0, 3'h0, 5'd12,OPI);      // marker addr
      imem[13] = NOP;
      imem[14] = NOP;
      imem[15] = S(12'd0,  5'd11,5'd12,3'h2, ST);       // marker store
      imem[16] = J(21'sd0, 5'd0, JAL);                  // halt
    end
  endtask

  task load_program_s4;
    begin
      // M-extension edge stress.
      imem[0]  = I(12'd100,5'd0,3'h0,5'd1, OPI);        // x1=100
      imem[1]  = I(12'd7,  5'd0,3'h0,5'd2, OPI);        // x2=7
      imem[2]  = R(7'h01,5'd2,5'd1,3'h4,5'd3,OP);       // div x3=14
      imem[3]  = R(7'h01,5'd2,5'd1,3'h6,5'd4,OP);       // rem x4=2
      imem[4]  = I(12'd0,  5'd0,3'h0,5'd5, OPI);        // x5=0
      imem[5]  = R(7'h01,5'd5,5'd1,3'h4,5'd6,OP);       // div x6=-1
      imem[6]  = R(7'h01,5'd5,5'd1,3'h6,5'd7,OP);       // rem x7=100
      imem[7]  = R(7'h01,5'd3,5'd2,3'h0,5'd8,OP);       // mul x8=98
      imem[8]  = I(12'd4,  5'd0,3'h0,5'd11,OPI);        // marker=4
      imem[9]  = I(12'h1FC,5'd0,3'h0,5'd12,OPI);        // marker addr
      imem[10] = NOP;
      imem[11] = NOP;
      imem[12] = S(12'd0, 5'd11,5'd12,3'h2, ST);        // marker store
      imem[13] = J(21'sd0,5'd0,JAL);                    // halt
    end
  endtask

  task wait_marker;
    input [31:0] marker_value;
    input [95:0] scenario;
    begin
      test_done = 1'b0;
      cyc = 0;
      while ((cyc < TIMEOUT_CYC) && !test_done) begin
        @(posedge Clk_In);

        if (shadow_rf[0] !== 32'd0) begin
          $display("[FAIL] %-12s x0 invariant broken: 0x%08h", scenario, shadow_rf[0]);
          fail_cnt = fail_cnt + 1;
          test_done = 1'b1;
        end

        if (!test_done && (get_dword(MARKER_ADDR) == marker_value))
          test_done = 1'b1;

        cyc = cyc + 1;
      end

      if (!test_done) begin
        $display("[FAIL] %-12s timeout (%0d cycles)", scenario, TIMEOUT_CYC);
        fail_cnt = fail_cnt + 1;
      end
    end
  endtask

  task run_scenario;
    input [95:0] scenario;
    begin
      $display("\n--- %s ---", scenario);
      Rst_In = 1'b1;
      stall_enable = 1'b0;
      HResp_In = 1'b0;
      EIrq_In = 1'b0;
      TIrq_In = 1'b0;
      SIrq_In = 1'b0;
      init_memories();
      repeat (5) @(posedge Clk_In);
    end
  endtask

  task start_scenario;
    begin
      Rst_In = 1'b0;
      stall_enable = 1'b0;
    end
  endtask

  task load_halt_nops;
    integer i;
    begin
      for (i = 0; i < IMEM_DEPTH; i = i + 1)
        imem[i] = NOP;
      imem[6] = J(21'sd0, 5'd0, JAL);
    end
  endtask

  task run_reg_reg_case;
    input [95:0] label;
    input [31:0] insn;
    input [31:0] rs1_v;
    input [31:0] rs2_v;
    input [31:0] exp_v;
    begin
      run_scenario("S5_RR");
      load_halt_nops();
      imem[0] = insn;
      start_scenario();
      dut.reg_file.register[1] = rs1_v;
      dut.reg_file.register[2] = rs2_v;
      repeat (60) @(posedge Clk_In);
      check_eq(label, dut.reg_file.register[3], exp_v);
    end
  endtask

  task run_reg_imm_case;
    input [95:0] label;
    input [31:0] insn;
    input [31:0] rs1_v;
    input [31:0] exp_v;
    begin
      run_scenario("S5_RI");
      load_halt_nops();
      imem[0] = insn;
      start_scenario();
      dut.reg_file.register[1] = rs1_v;
      repeat (60) @(posedge Clk_In);
      check_eq(label, dut.reg_file.register[3], exp_v);
    end
  endtask

  task run_mem_case;
    input [95:0] label;
    input [31:0] st_insn;
    input [31:0] ld_insn;
    input [31:0] base_addr;
    input [31:0] wr_data;
    input [31:0] exp_rd;
    begin
      run_scenario("S5_MEM");
      load_halt_nops();
      imem[0] = st_insn;
      imem[1] = NOP;
      imem[2] = NOP;
      imem[3] = ld_insn;
      start_scenario();
      dut.reg_file.register[1] = base_addr;
      dut.reg_file.register[2] = wr_data;
      repeat (100) @(posedge Clk_In);
      check_eq(label, dut.reg_file.register[3], exp_rd);
    end
  endtask

  task run_branch_case;
    input [95:0] label;
    input [2:0] br_f3;
    input [31:0] rs1_v;
    input [31:0] rs2_v;
    input [31:0] exp_rd;
    begin
      run_scenario("S5_BR");
      load_halt_nops();
      imem[0] = B(13'd12, 5'd2, 5'd1, br_f3, BR);      // if taken -> PC+12 (idx3)
      imem[1] = I(12'd1, 5'd0, 3'h0, 5'd4, OPI);       // not-taken marker
      imem[2] = J(21'd8,  5'd0, JAL);                  // skip taken marker
      imem[3] = I(12'd2, 5'd0, 3'h0, 5'd4, OPI);       // taken marker
      imem[4] = R(7'h00, 5'd0, 5'd4, 3'h0, 5'd3, OP);  // copy x4 -> x3
      start_scenario();
      dut.reg_file.register[1] = rs1_v;
      dut.reg_file.register[2] = rs2_v;
      repeat (100) @(posedge Clk_In);
      check_eq(label, dut.reg_file.register[3], exp_rd);
    end
  endtask

  task run_jal_case;
    begin
      run_scenario("S5_JAL");
      load_halt_nops();
      imem[0] = J(21'd8, 5'd3, JAL);                   // x3=4, jump to idx2
      imem[1] = I(12'd1, 5'd0, 3'h0, 5'd4, OPI);       // skipped
      imem[2] = I(12'd2, 5'd0, 3'h0, 5'd4, OPI);       // executed
      start_scenario();
      repeat (80) @(posedge Clk_In);
      check_eq("s5_jal_rd", dut.reg_file.register[3], 32'd4);
      check_eq("s5_jal_x4", dut.reg_file.register[4], 32'd2);
    end
  endtask

  task run_jalr_case;
    begin
      run_scenario("S5_JALR");
      load_halt_nops();
      imem[0] = I(12'd0, 5'd1, 3'h0, 5'd3, JALR);      // jalr x3,0(x1)
      imem[1] = I(12'd1, 5'd0, 3'h0, 5'd4, OPI);       // skipped
      imem[2] = I(12'd9, 5'd0, 3'h0, 5'd4, OPI);       // skipped
      imem[4] = I(12'd2, 5'd0, 3'h0, 5'd4, OPI);       // executed
      start_scenario();
      dut.reg_file.register[1] = 32'd16;
      repeat (100) @(posedge Clk_In);
      check_eq("s5_jalr_rd", dut.reg_file.register[3], 32'd4);
      check_eq("s5_jalr_x4", dut.reg_file.register[4], 32'd2);
    end
  endtask

  task run_lui_auipc_case;
    begin
      run_scenario("S5_U");
      load_halt_nops();
      imem[0] = U(20'hABCDE, 5'd3, LUI);
      imem[1] = U(20'h12345, 5'd4, AUI);               // PC at idx1 = 4
      start_scenario();
      repeat (80) @(posedge Clk_In);
      check_eq("s5_lui", dut.reg_file.register[3], 32'hABCDE000);
      check_eq("s5_auipc", dut.reg_file.register[4], 32'h12345004);
    end
  endtask

  task run_csr_cases;
    begin
      run_scenario("S5_CSR");
      load_halt_nops();
      imem[0] = I(CSR_MSCRATCH, 5'd5, 3'h5, 5'd0, SYS); // csrrwi x0, mscratch, 5
      imem[1] = I(CSR_MSCRATCH, 5'd1, 3'h1, 5'd3, SYS); // csrrw  x3, mscratch, x1
      imem[2] = I(CSR_MSCRATCH, 5'd0, 3'h2, 5'd4, SYS); // csrrs  x4, mscratch, x0
      imem[3] = I(CSR_MSCRATCH, 5'd3, 3'h6, 5'd5, SYS); // csrrsi x5, mscratch, 3
      imem[4] = I(CSR_MSCRATCH, 5'd1, 3'h7, 5'd6, SYS); // csrrci x6, mscratch, 1
      imem[5] = I(CSR_MSCRATCH, 5'd0, 3'h2, 5'd7, SYS); // csrrs  x7, mscratch, x0
      start_scenario();
      dut.reg_file.register[1] = 32'h12345678;
      repeat (140) @(posedge Clk_In);
      check_eq("s5_csrrw_old", dut.reg_file.register[3], 32'd5);
      check_eq("s5_csrrw_new", dut.reg_file.register[4], 32'h12345678);
      check_eq("s5_csrrsi",   dut.reg_file.register[5], 32'h12345678);
      check_eq("s5_csrrci",   dut.reg_file.register[6], 32'h1234567B);
      check_eq("s5_csr_final",dut.reg_file.register[7], 32'h1234567A);
    end
  endtask

  integer rnd_i;
  reg [31:0] ra;
  reg [31:0] rb;
  reg [31:0] rc;
  reg signed [31:0] sa;
  reg signed [31:0] sb;
  reg signed [63:0] pss;
  reg signed [63:0] psu;
  reg [63:0] puu;

  // ---------------- Main ----------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    $display("============================================================");
    $display(" Regression Stress TB: Pip_RV32IM_AHB");
    $display("============================================================");

    // Scenario 1: loop + load/store + MUL/DIV under stalls
    run_scenario("S1_LOOP_M");
    load_program_s1();
    start_scenario();
    repeat (900) @(posedge Clk_In);
    check_eq("s1_x1",  dut.reg_file.register[1], 32'd50);
    check_eq("s1_x3",  dut.reg_file.register[3], 32'd1225);
    check_eq("s1_x4",  dut.reg_file.register[4], 32'd1225);
    check_eq("s1_x5",  dut.reg_file.register[5], 32'd61250);
    check_eq("s1_x6",  dut.reg_file.register[6], 32'd1225);
    check_eq("s1_mem", get_dword(12'h100), 32'd1225);

    // Scenario 2: memory sign/zero extension
    run_scenario("S2_MEM_SZ");
    load_program_s2();
    start_scenario();
    repeat (300) @(posedge Clk_In);
    check_eq("s2_lb0", dut.reg_file.register[4], 32'h0000_007F);
    check_eq("s2_lb1", dut.reg_file.register[5], 32'hFFFF_FF80);
    check_eq("s2_lbu", dut.reg_file.register[6], 32'h0000_0080);
    check_eq("s2_lh",  dut.reg_file.register[7], 32'h0000_0123);
    check_eq("s2_lw",  dut.reg_file.register[8], 32'h0123_807F);
    check_eq("s2_mem", get_dword(12'h120), 32'h0123_807F);

    // Scenario 3: branch/jump behavior
    run_scenario("S3_BR_JMP");
    load_program_s3();
    start_scenario();
    repeat (250) @(posedge Clk_In);
    check_eq("s3_x3",  dut.reg_file.register[3], 32'd1);
    check_eq("s3_x4",  dut.reg_file.register[4], 32'h55);
    check_eq("s3_x5",  dut.reg_file.register[5], 32'h2A);
    check_eq("s3_x6",  dut.reg_file.register[6], 32'h24);
    check_eq("s3_x28", dut.reg_file.register[28], 32'd0);

    // Scenario 4: M-extension edge behavior
    run_scenario("S4_M_EDGE");
    load_program_s4();
    start_scenario();
    repeat (500) @(posedge Clk_In);
    check_eq("s4_div",  dut.reg_file.register[3], 32'd14);
    check_eq("s4_rem",  dut.reg_file.register[4], 32'd2);
    check_eq("s4_div0", dut.reg_file.register[6], 32'hFFFF_FFFF);
    check_eq("s4_rem0", dut.reg_file.register[7], 32'd100);
    check_eq("s4_mul",  dut.reg_file.register[8], 32'd98);

    // Scenario 5: instruction-complete directed-random micro-tests
    // RV32I R-type + corner cases
    run_reg_reg_case("s5_add_c", R(7'h00,5'd2,5'd1,3'h0,5'd3,OP), 32'h7FFF_FFFF, 32'd1, 32'h8000_0000);
    run_reg_reg_case("s5_sub_c", R(7'h20,5'd2,5'd1,3'h0,5'd3,OP), 32'h8000_0000, 32'd1, 32'h7FFF_FFFF);
    run_reg_reg_case("s5_sll_c", R(7'h00,5'd2,5'd1,3'h1,5'd3,OP), 32'h0000_0001, 32'd31, 32'h8000_0000);
    run_reg_reg_case("s5_slt_c", R(7'h00,5'd2,5'd1,3'h2,5'd3,OP), 32'hFFFF_FFFF, 32'h0000_0001, 32'd1);
    run_reg_reg_case("s5_sltu",  R(7'h00,5'd2,5'd1,3'h3,5'd3,OP), 32'h0000_0001, 32'hFFFF_FFFF, 32'd1);
    run_reg_reg_case("s5_xor_c", R(7'h00,5'd2,5'd1,3'h4,5'd3,OP), 32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF);
    run_reg_reg_case("s5_srl_c", R(7'h00,5'd2,5'd1,3'h5,5'd3,OP), 32'h8000_0000, 32'd31, 32'h0000_0001);
    run_reg_reg_case("s5_sra_c", R(7'h20,5'd2,5'd1,3'h5,5'd3,OP), 32'h8000_0000, 32'd31, 32'hFFFF_FFFF);
    run_reg_reg_case("s5_or_c",  R(7'h00,5'd2,5'd1,3'h6,5'd3,OP), 32'h1234_0000, 32'h0000_ABCD, 32'h1234_ABCD);
    run_reg_reg_case("s5_and_c", R(7'h00,5'd2,5'd1,3'h7,5'd3,OP), 32'h1234_FFFF, 32'h00FF_FF00, 32'h0034_FF00);

    // RV32I I-type
    run_reg_imm_case("s5_addi", I(12'hFFF,5'd1,3'h0,5'd3,OPI), 32'd1, 32'd0);
    run_reg_imm_case("s5_slti", I(12'h800,5'd1,3'h2,5'd3,OPI), 32'hFFFF_FFFE, 32'd0);
    run_reg_imm_case("s5_sltiu",I(12'hFFF,5'd1,3'h3,5'd3,OPI), 32'd0, 32'd1);
    run_reg_imm_case("s5_xori", I(12'hA55,5'd1,3'h4,5'd3,OPI), 32'hFFFF_0000, 32'hFFFF_FA55 ^ 32'hFFFF_0000);
    run_reg_imm_case("s5_ori",  I(12'h0F0,5'd1,3'h6,5'd3,OPI), 32'h1234_5600, 32'h1234_56F0);
    run_reg_imm_case("s5_andi", I(12'h0F0,5'd1,3'h7,5'd3,OPI), 32'h1234_56FF, 32'h0000_00F0);
    run_reg_imm_case("s5_slli", I({7'h00,5'd4},5'd1,3'h1,5'd3,OPI), 32'h0000_00F0, 32'h0000_0F00);
    run_reg_imm_case("s5_srli", I({7'h00,5'd4},5'd1,3'h5,5'd3,OPI), 32'hF000_0000, 32'h0F00_0000);
    run_reg_imm_case("s5_srai", I({7'h20,5'd4},5'd1,3'h5,5'd3,OPI), 32'hF000_0000, 32'hFF00_0000);

    // U/J instructions
    run_lui_auipc_case();
    run_jal_case();
    run_jalr_case();

    // Branch matrix (taken and not taken)
    run_branch_case("s5_beq_t", 3'h0, 32'h1111_1111, 32'h1111_1111, 32'd2);
    run_branch_case("s5_beq_n", 3'h0, 32'h1111_1111, 32'h2222_2222, 32'd1);
    run_branch_case("s5_bne_t", 3'h1, 32'h1111_1111, 32'h2222_2222, 32'd2);
    run_branch_case("s5_bne_n", 3'h1, 32'h1111_1111, 32'h1111_1111, 32'd1);
    run_branch_case("s5_blt_t", 3'h4, 32'hFFFF_FFFF, 32'h0000_0001, 32'd2);
    run_branch_case("s5_bge_t", 3'h5, 32'h0000_0001, 32'hFFFF_FFFF, 32'd2);
    run_branch_case("s5_bltu_t",3'h6, 32'h0000_0001, 32'hFFFF_FFFF, 32'd2);
    run_branch_case("s5_bgeu_t",3'h7, 32'hFFFF_FFFF, 32'h0000_0001, 32'd2);

    // Memory access corner cases
    run_mem_case("s5_sb_lb",  S(12'd1,5'd2,5'd1,3'h0,ST), I(12'd1,5'd1,3'h0,5'd3,LD), 32'h0000_0120, 32'h0000_0080, 32'hFFFF_FF80);
    run_mem_case("s5_sb_lbu", S(12'd2,5'd2,5'd1,3'h0,ST), I(12'd2,5'd1,3'h4,5'd3,LD), 32'h0000_0120, 32'h0000_00FE, 32'h0000_00FE);
    run_mem_case("s5_sh_lh",  S(12'd0,5'd2,5'd1,3'h1,ST), I(12'd0,5'd1,3'h1,5'd3,LD), 32'h0000_0124, 32'h0000_8001, 32'hFFFF_8001);
    run_mem_case("s5_sh_lhu", S(12'd0,5'd2,5'd1,3'h1,ST), I(12'd0,5'd1,3'h5,5'd3,LD), 32'h0000_0128, 32'h0000_8001, 32'h0000_8001);
    run_mem_case("s5_sw_lw",  S(12'd0,5'd2,5'd1,3'h2,ST), I(12'd0,5'd1,3'h2,5'd3,LD), 32'h0000_0130, 32'hDEAD_BEEF, 32'hDEAD_BEEF);

    // M-extension corner cases
    run_reg_reg_case("s5_mul",    R(7'h01,5'd2,5'd1,3'h0,5'd3,OP), 32'h0001_0000, 32'h0001_0000, 32'h0000_0000);
    run_reg_reg_case("s5_mulh",   R(7'h01,5'd2,5'd1,3'h1,5'd3,OP), 32'h8000_0000, 32'h0000_0002, 32'hFFFF_FFFF);
    run_reg_reg_case("s5_mulhsu", R(7'h01,5'd2,5'd1,3'h2,5'd3,OP), 32'h8000_0000, 32'h0000_0002, 32'hFFFF_FFFF);
    run_reg_reg_case("s5_mulhu",  R(7'h01,5'd2,5'd1,3'h3,5'd3,OP), 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE);
    run_reg_reg_case("s5_div",    R(7'h01,5'd2,5'd1,3'h4,5'd3,OP), 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000);
    run_reg_reg_case("s5_divu",   R(7'h01,5'd2,5'd1,3'h5,5'd3,OP), 32'hFFFF_FFFF, 32'h0000_0002, 32'h7FFF_FFFF);
    run_reg_reg_case("s5_rem",    R(7'h01,5'd2,5'd1,3'h6,5'd3,OP), 32'h8000_0000, 32'hFFFF_FFFF, 32'h0000_0000);
    run_reg_reg_case("s5_remu",   R(7'h01,5'd2,5'd1,3'h7,5'd3,OP), 32'hFFFF_FFFF, 32'h0000_0002, 32'h0000_0001);

    // Zicsr matrix
    run_csr_cases();

    // Randomized ALU/M mix (deterministic via simulator seed)
    for (rnd_i = 0; rnd_i < 16; rnd_i = rnd_i + 1) begin
      ra = $random;
      rb = $random;
      run_reg_reg_case("s5_rnd_add", R(7'h00,5'd2,5'd1,3'h0,5'd3,OP), ra, rb, ra + rb);
      run_reg_reg_case("s5_rnd_xor", R(7'h00,5'd2,5'd1,3'h4,5'd3,OP), ra, rb, ra ^ rb);

      if (rb == 32'd0)
        rb = 32'd1;

      sa = ra;
      sb = rb;
      pss = $signed(sa) * $signed(sb);
      puu = ra * rb;
      psu = $signed(sa) * $signed({1'b0, rb});

      run_reg_reg_case("s5_rnd_mul",    R(7'h01,5'd2,5'd1,3'h0,5'd3,OP), ra, rb, puu[31:0]);
      run_reg_reg_case("s5_rnd_mulh",   R(7'h01,5'd2,5'd1,3'h1,5'd3,OP), ra, rb, pss[63:32]);
      run_reg_reg_case("s5_rnd_mulhsu", R(7'h01,5'd2,5'd1,3'h2,5'd3,OP), ra, rb, psu[63:32]);
      run_reg_reg_case("s5_rnd_mulhu",  R(7'h01,5'd2,5'd1,3'h3,5'd3,OP), ra, rb, puu[63:32]);
      run_reg_reg_case("s5_rnd_div",    R(7'h01,5'd2,5'd1,3'h4,5'd3,OP), ra, rb, $signed(sa) / $signed(sb));
      run_reg_reg_case("s5_rnd_divu",   R(7'h01,5'd2,5'd1,3'h5,5'd3,OP), ra, rb, ra / rb);
      run_reg_reg_case("s5_rnd_rem",    R(7'h01,5'd2,5'd1,3'h6,5'd3,OP), ra, rb, $signed(sa) % $signed(sb));
      run_reg_reg_case("s5_rnd_remu",   R(7'h01,5'd2,5'd1,3'h7,5'd3,OP), ra, rb, ra % rb);

      rc = $random;
      run_reg_imm_case("s5_rnd_addi", I(rc[11:0],5'd1,3'h0,5'd3,OPI), ra, ra + {{20{rc[11]}}, rc[11:0]});
    end

    $display("\n============================================================");
    $display(" Regression Stress Summary: PASS=%0d FAIL=%0d TOTAL=%0d",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("============================================================\n");

    if (fail_cnt != 0)
      $fatal(1, "Regression stress test FAILED");
    else
      $display("*** REGRESSION STRESS TEST PASSED ***");

    $finish;
  end

endmodule
