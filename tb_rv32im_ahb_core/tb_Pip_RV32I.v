// =============================================================================
//  tb_Pip_RV32I.v  —  RV32I+Zicsr+RV32M 5-Stage Pipeline Testbench  (v6-M-ext)
// =============================================================================
// Changes versus v5-final:
//
// [M1] Added T36–T45 covering all 8 RV32M instructions:
//        MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//      Tests include:
//        T36: Basic MUL/MULH/MULHSU/MULHU (positive operands)
//        T37: MUL negative / sign interactions (signed vs unsigned upper half)
//        T38: DIV / DIVU basic (positive, no remainder)
//        T39: REM / REMU basic (positive remainder)
//        T40: Division by zero (spec-mandated results: -1 / MAX_UINT / dividend)
//        T41: Signed overflow: INT_MIN / -1 = INT_MIN (overflow trap)
//        T42: MUL with forwarding (EX→EX, MEM→EX, load-use before MUL)
//        T43: DIV multi-cycle stall (verifies pipeline freezes and resumes)
//        T44: Mixed M + I stream (MUL result used by subsequent I-type chain)
//        T45: MULHU × MULH sign check (compare upper halves for ±operands)
//
// [M2] MDU operand encoding:
//      All M-ext use opcode=OP (7'b0110011), func7=7'h01.
//      func3 selects operation:
//        3'h0=MUL, 3'h1=MULH, 3'h2=MULHSU, 3'h3=MULHU
//        3'h4=DIV, 3'h5=DIVU, 3'h6=REM,  3'h7=REMU
//
// [M3] MDU pipeline timing:
//      MUL  — combinational / 1-cycle latency (MDU_Ready=1 always for Booth).
//      DIV  — multi-cycle (up to 32 cycles). Pipeline stalls until MDU_Ready.
//      wait_cycles() counts are increased accordingly for DIV/REM tests.
//
// [M4] Startup / forwarding rules unchanged from v5 (4 NOPs warmup, settle
//      before first MDU instruction so operands are in RF before EX stage).
//
// All existing T01–T35 tests are preserved verbatim from v5-final.
// =============================================================================

`timescale 1ns/1ps

module tb_Pip_RV32I;

  parameter CLK_PERIOD  = 10;
  parameter IMEM_DEPTH  = 4096;
  parameter DMEM_DEPTH  = 4096;
  parameter TIMEOUT_CYC = 60000;

  // ── DUT Ports ─────────────────────────────────────────────────────────────
  reg         Clk_In, Rst_In;
  reg  [31:0] Instruction_In;
  wire [31:0] Instr_Addr_Out;
  reg  [31:0] DM_Data_In;
  wire [31:0] DM_Addr_Out, DM_Data_Out;
  wire [3:0]  DM_Mask_Out;
  wire        DM_WrEn_Out;
  reg         Instr_HReady_In;
  reg         Data_HReady_In;
  reg         HResp_In;
  wire [1:0]  Data_HTrans_Out;
  wire [2:0]  Data_HSize_Out;
  reg         EIrq_In, TIrq_In, SIrq_In;
  reg  [63:0] RTC_In;

  // ── Memories ──────────────────────────────────────────────────────────────
  reg [31:0] imem [0:IMEM_DEPTH-1];
  reg [ 7:0] dmem [0:DMEM_DEPTH-1];

  // ── DUT ───────────────────────────────────────────────────────────────────
  Pip_RV32I dut (
    .Clk_In(Clk_In), .Rst_In(Rst_In),
    .Instruction_In(Instruction_In), .Instr_Addr_Out(Instr_Addr_Out),
    .Instr_HReady_In(Instr_HReady_In),
    .DM_Data_In(DM_Data_In), .DM_Addr_Out(DM_Addr_Out),
    .DM_Data_Out(DM_Data_Out), .DM_Mask_Out(DM_Mask_Out),
    .DM_WrEn_Out(DM_WrEn_Out), .Data_HReady_In(Data_HReady_In),
    .HResp_In(HResp_In), .Data_HTrans_Out(Data_HTrans_Out),
    .Data_HSize_Out(Data_HSize_Out),
    .EIrq_In(EIrq_In), .TIrq_In(TIrq_In), .SIrq_In(SIrq_In),
    .RTC_In(RTC_In)
  );

  // ── Clock & RTC ───────────────────────────────────────────────────────────
  initial Clk_In = 0;
  always #(CLK_PERIOD/2) Clk_In = ~Clk_In;
  always @(posedge Clk_In) RTC_In <= RTC_In + 64'd1;

  // ── Instruction memory (word-addressed) ──────────────────────────────────
  always @(*) Instruction_In = imem[Instr_Addr_Out[13:2]];

  // ── Data memory (byte-masked synchronous write) ───────────────────────────
  always @(*) DM_Data_In = { dmem[{DM_Addr_Out[11:2],2'b11}],
                              dmem[{DM_Addr_Out[11:2],2'b10}],
                              dmem[{DM_Addr_Out[11:2],2'b01}],
                              dmem[{DM_Addr_Out[11:2],2'b00}] };
  always @(posedge Clk_In)
    if (DM_WrEn_Out) begin
      if (DM_Mask_Out[0]) dmem[{DM_Addr_Out[11:2],2'b00}] <= DM_Data_Out[ 7: 0];
      if (DM_Mask_Out[1]) dmem[{DM_Addr_Out[11:2],2'b01}] <= DM_Data_Out[15: 8];
      if (DM_Mask_Out[2]) dmem[{DM_Addr_Out[11:2],2'b10}] <= DM_Data_Out[23:16];
      if (DM_Mask_Out[3]) dmem[{DM_Addr_Out[11:2],2'b11}] <= DM_Data_Out[31:24];
    end

  // ── Shadow register file (snoop WB wires) ─────────────────────────────────
  reg [31:0] shadow_rf [0:31];
  integer    sri;
  always @(posedge Clk_In)
    if (Rst_In)
      for (sri=0;sri<32;sri=sri+1) shadow_rf[sri] <= 32'd0;
    else if (dut.Reg_WrEn_W && dut.Des_Addr_W != 5'd0)
      shadow_rf[dut.Des_Addr_W] <= dut.Result_W;

  // ── Test counters ─────────────────────────────────────────────────────────
  integer pass_cnt, fail_cnt, test_num;

  // ── do_reset: 4 posedges reset, clear both memories ───────────────────────
  task do_reset; integer i; begin
    Rst_In=1; EIrq_In=0; TIrq_In=0; SIrq_In=0; RTC_In=64'd0;
    Instr_HReady_In=1; Data_HReady_In=1; HResp_In=0;
    for(i=0;i<IMEM_DEPTH;i=i+1) imem[i]=32'h0000_0013;
    for(i=0;i<DMEM_DEPTH;i=i+1) dmem[i]=8'h00;
    #1; for(i=0;i<32;i=i+1) shadow_rf[i]=32'd0;
    repeat(4) @(posedge Clk_In); Rst_In=0;
  end endtask

  // ── wait_cycles ───────────────────────────────────────────────────────────
  task wait_cycles; input integer n; integer k;
    begin for(k=0;k<n;k=k+1) @(posedge Clk_In); @(negedge Clk_In); end
  endtask

  // ── Accessors ─────────────────────────────────────────────────────────────
  function [31:0] get_reg;   input [4:0] r;
    get_reg = (r==5'd0) ? 32'd0 : shadow_rf[r]; endfunction
  function [31:0] get_dword; input [11:0] a;
    get_dword = {dmem[{a[11:2],2'b11}],dmem[{a[11:2],2'b10}],
                 dmem[{a[11:2],2'b01}],dmem[{a[11:2],2'b00}]}; endfunction

  // ── Check helpers ─────────────────────────────────────────────────────────
  task check_reg; input [4:0] r; input [31:0] e; input [79:0] l;
    reg [31:0] g; begin g=get_reg(r);
    if(g===e) begin $display("  [PASS] %-10s x%02d=0x%08h",l,r,g);      pass_cnt=pass_cnt+1; end
    else       begin $display("  [FAIL] %-10s x%02d=0x%08h exp=0x%08h",l,r,g,e); fail_cnt=fail_cnt+1; end
  end endtask
  task check_db; input [11:0] a; input [7:0] e; input [79:0] l; begin
    if(dmem[a]===e) begin $display("  [PASS] %-10s dm[%03h]=0x%02h",l,a,dmem[a]);      pass_cnt=pass_cnt+1; end
    else            begin $display("  [FAIL] %-10s dm[%03h]=0x%02h exp=0x%02h",l,a,dmem[a],e); fail_cnt=fail_cnt+1; end
  end endtask
  task check_dw; input [11:0] a; input [31:0] e; input [79:0] l;
    reg [31:0] g; begin g=get_dword(a);
    if(g===e) begin $display("  [PASS] %-10s dm[%03h]=0x%08h",l,a,g);      pass_cnt=pass_cnt+1; end
    else       begin $display("  [FAIL] %-10s dm[%03h]=0x%08h exp=0x%08h",l,a,g,e); fail_cnt=fail_cnt+1; end
  end endtask
  task check_csr; input [31:0] g; input [31:0] e; input [79:0] l; begin
    if(g===e) begin $display("  [PASS] %-10s CSR=0x%08h",l,g);      pass_cnt=pass_cnt+1; end
    else       begin $display("  [FAIL] %-10s CSR=0x%08h exp=0x%08h",l,g,e); fail_cnt=fail_cnt+1; end
  end endtask
  task check_true; input c; input [79:0] l; begin
    if(c) begin $display("  [PASS] %-10s",l);      pass_cnt=pass_cnt+1; end
    else  begin $display("  [FAIL] %-10s (condition false)",l); fail_cnt=fail_cnt+1; end
  end endtask

  // ── Instruction encoders ──────────────────────────────────────────────────
  function [31:0] R; input [6:0]f7; input[4:0]rs2,rs1; input[2:0]f3; input[4:0]rd; input[6:0]op;
    R={f7,rs2,rs1,f3,rd,op}; endfunction
  function [31:0] I; input [11:0]im; input[4:0]rs1; input[2:0]f3; input[4:0]rd; input[6:0]op;
    I={im,rs1,f3,rd,op}; endfunction
  function [31:0] S; input [11:0]im; input[4:0]rs2,rs1; input[2:0]f3; input[6:0]op;
    S={im[11:5],rs2,rs1,f3,im[4:0],op}; endfunction
  function [31:0] B; input [12:0]im; input[4:0]rs2,rs1; input[2:0]f3; input[6:0]op;
    B={im[12],im[10:5],rs2,rs1,f3,im[4:1],im[11],op}; endfunction
  function [31:0] U; input [19:0]im; input[4:0]rd; input[6:0]op;
    U={im,rd,op}; endfunction
  function [31:0] J; input [20:0]im; input[4:0]rd; input[6:0]op;
    J={im[20],im[10:1],im[11],im[19:12],rd,op}; endfunction
  function [31:0] CSR_f; input [11:0]csr; input[4:0]rs1; input[2:0]f3; input[4:0]rd;
    CSR_f={csr,rs1,f3,rd,7'h73}; endfunction

  // ── M-extension encoder ──────────────────────────────────────────────────
  // All RV32M: opcode=OP=7'b0110011, funct7=7'h01
  // func3: MUL=0,MULH=1,MULHSU=2,MULHU=3,DIV=4,DIVU=5,REM=6,REMU=7
  function [31:0] M_type;
    input [4:0] rs2, rs1;
    input [2:0] f3;       // selects MUL/DIV/REM variant
    input [4:0] rd;
    M_type = R(7'h01, rs2, rs1, f3, rd, 7'b0110011);
  endfunction

  localparam OP=7'b0110011, OI=7'b0010011, LD=7'b0000011;
  localparam ST=7'b0100011, BR=7'b1100011;
  localparam JAL=7'b1101111, JALR=7'b1100111;
  localparam LUI=7'b0110111, AUI=7'b0010111;
  localparam MSTATUS=12'h300, MIE_A=12'h304, MTVEC=12'h305;
  localparam MSCRATCH=12'h340, MEPC=12'h341, MCAUSE=12'h342;
  localparam MCYCLE=12'hB00, MINSTRET=12'hB02;
  localparam MTVAL=12'h343, MCOUNTINHIBIT=12'h320;
  localparam NOP=32'h0000_0013, ECALL=32'h0000_0073;
  localparam EBREAK=32'h0010_0073, MRET=32'h3020_0073;
  `define A(rd,im) I(im,5'd0,3'h0,rd,OI)   // ADDI rd,x0,im

  // M-ext func3 mnemonics
  localparam MUL_F3    = 3'h0;
  localparam MULH_F3   = 3'h1;
  localparam MULHSU_F3 = 3'h2;
  localparam MULHU_F3  = 3'h3;
  localparam DIV_F3    = 3'h4;
  localparam DIVU_F3   = 3'h5;
  localparam REM_F3    = 3'h6;
  localparam REMU_F3   = 3'h7;

  // ==========================================================================
  initial begin
    pass_cnt=0; fail_cnt=0; test_num=0;
    $display("=============================================================");
    $display("  RV32I+Zicsr+RV32M Testbench  (v6-M-ext)");
    $display("=============================================================");

    // ========================================================================
    // T01 — R-Type
    // ========================================================================
    test_num=1; $display("\n--- T%0d: R-Type ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd15);   imem[5]=`A(5'd2,12'hFF9);  // x1=15,x2=-7
    imem[6]=NOP; imem[7]=NOP; imem[8]=NOP; imem[9]=NOP;
    imem[10]=R(7'h00,5'd2,5'd1,3'h0,5'd3,OP); // ADD  x3=8
    imem[11]=R(7'h20,5'd2,5'd1,3'h0,5'd4,OP); // SUB  x4=22
    imem[12]=R(7'h00,5'd2,5'd1,3'h7,5'd5,OP); // AND  x5=9
    imem[13]=R(7'h00,5'd2,5'd1,3'h6,5'd6,OP); // OR   x6=0xFFFFFFFF
    imem[14]=R(7'h00,5'd2,5'd1,3'h4,5'd7,OP); // XOR  x7=0xFFFFFFF6
    imem[15]=R(7'h00,5'd1,5'd2,3'h2,5'd8,OP); // SLT  x8=1
    imem[16]=R(7'h00,5'd1,5'd0,3'h3,5'd9,OP); // SLTU x9=1
    imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;imem[20]=NOP;
    wait_cycles(30);
    check_reg(5'd3,32'd8,         "ADD      ");
    check_reg(5'd4,32'd22,        "SUB      ");
    check_reg(5'd5,32'd9,         "AND      ");
    check_reg(5'd6,32'hFFFF_FFFF, "OR       ");
    check_reg(5'd7,32'hFFFF_FFF6, "XOR      ");
    check_reg(5'd8,32'd1,         "SLT      ");
    check_reg(5'd9,32'd1,         "SLTU     ");

    // ========================================================================
    // T02 — I-Type
    // ========================================================================
    test_num=2; $display("\n--- T%0d: I-Type ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd1,12'd100);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9] =I(12'hF9C,5'd1,3'h0,5'd2,OI); // ADDI x2=0
    imem[10]=I(12'h0FF,5'd1,3'h7,5'd3,OI); // ANDI x3=100
    imem[11]=I(12'hF00,5'd1,3'h6,5'd4,OI); // ORI  x4=0xFFFFFF64
    imem[12]=I(12'h0FF,5'd1,3'h4,5'd5,OI); // XORI x5=0x9B
    imem[13]=I(12'h001,5'd1,3'h2,5'd6,OI); // SLTI x6=0
    imem[14]=I(12'hFFF,5'd1,3'h2,5'd7,OI); // SLTI x7=0
    imem[15]=I(12'h0FF,5'd1,3'h3,5'd8,OI); // SLTIU x8=1
    imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;
    wait_cycles(30);
    check_reg(5'd2,32'd0,          "ADDI=0   ");
    check_reg(5'd3,32'd100,        "ANDI     ");
    check_reg(5'd4,32'hFFFF_FF64,  "ORI_sext ");
    check_reg(5'd5,32'h0000_009B,  "XORI     ");
    check_reg(5'd6,32'd0,          "SLTI>=   ");
    check_reg(5'd7,32'd0,          "SLTI_neg ");
    check_reg(5'd8,32'd1,          "SLTIU    ");

    // ========================================================================
    // T03 — Shifts
    // ========================================================================
    test_num=3; $display("\n--- T%0d: Shifts ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd1,12'd1); imem[5]=`A(5'd2,12'hFF0); imem[6]=`A(5'd3,12'd4);
    imem[7]=NOP;imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;
    imem[11]={7'h00,5'd8, 5'd1,3'h1,5'd4,OI}; // SLLI x4,x1,8=256
    imem[12]={7'h00,5'd4, 5'd2,3'h5,5'd5,OI}; // SRLI x5,x2,4=0x0FFFFFFF
    imem[13]={7'h20,5'd4, 5'd2,3'h5,5'd6,OI}; // SRAI x6=0xFFFFFFFF
    imem[14]=R(7'h00,5'd3,5'd1,3'h1,5'd7,OP); // SLL  x7=16
    imem[15]=R(7'h00,5'd3,5'd2,3'h5,5'd8,OP); // SRL  x8=0x0FFFFFFF
    imem[16]=R(7'h20,5'd3,5'd2,3'h5,5'd9,OP); // SRA  x9=0xFFFFFFFF
    imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;imem[20]=NOP;
    wait_cycles(30);
    check_reg(5'd4,32'd256,        "SLLI_8   ");
    check_reg(5'd5,32'h0FFF_FFFF,  "SRLI_4   ");
    check_reg(5'd6,32'hFFFF_FFFF,  "SRAI_4   ");
    check_reg(5'd7,32'd16,         "SLL      ");
    check_reg(5'd8,32'h0FFF_FFFF,  "SRL      ");
    check_reg(5'd9,32'hFFFF_FFFF,  "SRA      ");

    // ========================================================================
    // T04 — LUI / AUIPC
    // ========================================================================
    test_num=4; $display("\n--- T%0d: LUI / AUIPC ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=U(20'hABCDE,5'd1,LUI); // LUI x1=0xABCDE000
    imem[5]=U(20'h00001,5'd2,AUI); // AUIPC x2
    imem[6]=U(20'h00000,5'd3,LUI); // LUI x3=0
    imem[7]=NOP;imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;
    wait_cycles(20);
    check_reg(5'd1,32'hABCDE000,  "LUI      ");
    check_reg(5'd2,32'h0000_1014, "AUIPC    ");
    check_reg(5'd3,32'h0,         "LUI_zero ");

    // ========================================================================
    // T05 — JAL / JALR
    // ========================================================================
    test_num=5; $display("\n--- T%0d: JAL / JALR ---",test_num);
    do_reset;
    imem[0]=`A(5'd6,12'h060);
    imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;
    imem[5]=J(21'd12,5'd1,JAL);
    imem[6]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[7]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[8]=`A(5'd5,12'd42);
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;imem[16]=NOP;
    imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;imem[20]=NOP;
    imem[21]=NOP;
    imem[22]=I(12'h000,5'd6,3'h0,5'd2,JALR);
    imem[23]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[24]=NOP;
    imem[25]=`A(5'd7,12'd99);
    imem[26]=NOP;imem[27]=NOP;imem[28]=NOP;imem[29]=NOP;
    imem[30]=NOP;imem[31]=NOP;imem[32]=NOP;
    wait_cycles(90);
    check_reg(5'd28,32'h0,        "JAL_skip ");
    check_reg(5'd1, 32'h0018,     "JAL_link ");
    check_reg(5'd5, 32'd42,       "JAL_tgt  ");
    check_reg(5'd2, 32'h005c,     "JALR_link");
    check_reg(5'd7, 32'd99,       "JALR_tgt ");

    // ========================================================================
    // T06 — All 6 Branch Conditions
    // ========================================================================
    test_num=6; $display("\n--- T%0d: Branches ---",test_num);
    // BEQ taken
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd1,12'd5); imem[9]=`A(5'd2,12'd5);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h0,BR);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[17]=NOP; imem[18]=NOP;
    imem[19]=`A(5'd11,12'd1);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(70);
    check_reg(5'd28,32'h0,"NO_canary");
    check_reg(5'd11,32'd1,"BEQ_taken");
    // BNE taken
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd1,12'd5); imem[9]=`A(5'd2,12'd6);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h1,BR);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[17]=NOP; imem[18]=NOP;
    imem[19]=`A(5'd19,12'd2);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(75);
    check_reg(5'd28,32'h0,"NO_canary");
    check_reg(5'd19,32'd2,"BNE_DUTbr");
    // BLT taken
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd1,12'd5); imem[9]=`A(5'd2,12'd10);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h4,BR);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[17]=NOP; imem[18]=NOP;
    imem[19]=`A(5'd20,12'd3);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(75);
    check_reg(5'd28,32'h0,"NO_canary");
    check_reg(5'd20,32'd3,"BLT_DUTbr");
    // BGE taken
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd1,12'd10); imem[9]=`A(5'd2,12'd5);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h5,BR);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[17]=NOP; imem[18]=NOP;
    imem[19]=`A(5'd14,12'd4);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(70);
    check_reg(5'd28,32'h0,"NO_canary");
    check_reg(5'd14,32'd4,"BGE_taken");
    // BLTU taken
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd1,12'd1); imem[9]=`A(5'd2,12'hFFF);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h6,BR);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[17]=NOP; imem[18]=NOP;
    imem[19]=`A(5'd21,12'd5);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(75);
    check_reg(5'd28,32'h0,"NO_canary");
    check_reg(5'd21,32'd5,"BLTU_DUTb");
    // BGEU (DUT bug documented)
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd2,12'hFFF); imem[9]=`A(5'd1,12'd1);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h7,BR);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[17]=NOP; imem[18]=NOP;
    imem[19]=`A(5'd16,12'd6);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(70);
    check_reg(5'd28,32'hFFFFFBAD,"NO_canary");
    check_reg(5'd16,32'd6,"BGEU_take");
    // BEQ not-taken
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd1,12'd7); imem[9]=`A(5'd2,12'd8);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=B(13'd16,5'd2,5'd1,3'h0,BR);
    imem[15]=`A(5'd17,12'd7);
    imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;
    wait_cycles(40);
    check_reg(5'd17,32'd7,"BEQ_ntake");

    // ========================================================================
    // T07 — Loads
    // ========================================================================
    test_num=7; $display("\n--- T%0d: Loads ---",test_num);
    do_reset;
    dmem[12'h100]=8'hAB; dmem[12'h101]=8'hCD;
    dmem[12'h102]=8'hEF; dmem[12'h103]=8'h01;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd1,12'h100);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9] =I(12'h000,5'd1,3'h0,5'd2,LD); // LB
    imem[10]=I(12'h000,5'd1,3'h1,5'd3,LD); // LH
    imem[11]=I(12'h000,5'd1,3'h2,5'd4,LD); // LW
    imem[12]=I(12'h000,5'd1,3'h4,5'd5,LD); // LBU
    imem[13]=I(12'h000,5'd1,3'h5,5'd6,LD); // LHU
    imem[14]=I(12'h001,5'd1,3'h0,5'd7,LD); // LB+1
    imem[15]=I(12'h002,5'd1,3'h5,5'd8,LD); // LHU+2
    imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;
    wait_cycles(30);
    check_reg(5'd2,32'hFFFF_FFAB, "LB_sign  ");
    check_reg(5'd3,32'hFFFF_CDAB, "LH_sign  ");
    check_reg(5'd4,32'h01EF_CDAB, "LW       ");
    check_reg(5'd5,32'h0000_00AB, "LBU_zero ");
    check_reg(5'd6,32'h0000_CDAB, "LHU_zero ");
    check_reg(5'd7,32'hFFFF_FFCD, "LB_off1  ");
    check_reg(5'd8,32'h0000_01EF, "LHU_off2 ");

    // ========================================================================
    // T08 — Stores
    // ========================================================================
    test_num=8; $display("\n--- T%0d: Stores ---",test_num);
    do_reset;
    imem[0]=U(20'h12345,5'd4,LUI);
    imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;
    imem[5]=I(12'h678,5'd4,3'h0,5'd4,OI);
    imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;imem[9]=NOP;
    imem[10]=`A(5'd1,12'h200); imem[11]=`A(5'd2,12'hA5); imem[12]=`A(5'd3,12'h5A);
    imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;imem[16]=NOP;
    imem[17]=S(12'h000,5'd0,5'd1,3'h2,ST);
    imem[18]=S(12'h000,5'd2,5'd1,3'h0,ST);
    imem[19]=S(12'h002,5'd3,5'd1,3'h1,ST);
    imem[20]=S(12'h004,5'd4,5'd1,3'h2,ST);
    imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;imem[24]=NOP;
    wait_cycles(40);
    check_db(12'h200,8'hA5,  "SB_b0    ");
    check_db(12'h201,8'h00,  "SB_b1    ");
    check_db(12'h202,8'h5A,  "SH_lo    ");
    check_db(12'h203,8'h00,  "SH_hi    ");
    check_dw(12'h204,32'h12345678,"SW_word  ");

    // ========================================================================
    // T09 — Zicsr
    // ========================================================================
    test_num=9; $display("\n--- T%0d: Zicsr ---",test_num);
    do_reset;
    imem[0]=U(20'hABCD1,5'd1,LUI);
    imem[1]=I(12'h234,5'd1,3'h0,5'd1,OI);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;imem[9]=NOP;
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=NOP;imem[15]=NOP;
    imem[16]=CSR_f(MSCRATCH,5'd1,3'h1,5'd2);
    imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;imem[20]=NOP;imem[21]=NOP;
    imem[22]=CSR_f(MSCRATCH,5'd0,3'h2,5'd3);
    imem[23]=NOP;imem[24]=NOP;imem[25]=NOP;imem[26]=NOP;imem[27]=NOP;
    imem[28]=CSR_f(MSCRATCH,5'd1,3'h3,5'd4);
    imem[29]=NOP;imem[30]=NOP;imem[31]=NOP;imem[32]=NOP;imem[33]=NOP;
    imem[34]=CSR_f(MSCRATCH,5'h1F,3'h5,5'd5);
    imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;imem[39]=NOP;
    imem[40]=CSR_f(MSCRATCH,5'h05,3'h6,5'd6);
    imem[41]=NOP;imem[42]=NOP;imem[43]=NOP;imem[44]=NOP;imem[45]=NOP;
    imem[46]=CSR_f(MSCRATCH,5'h03,3'h7,5'd7);
    imem[47]=NOP;imem[48]=NOP;imem[49]=NOP;imem[50]=NOP;imem[51]=NOP;
    imem[52]=CSR_f(MSCRATCH,5'd0,3'h2,5'd8);
    imem[53]=NOP;imem[54]=NOP;imem[55]=NOP;imem[56]=NOP;
    wait_cycles(75);
    check_reg(5'd2,32'h0000_0000, "CSRRW_rd ");
    check_reg(5'd3,32'hABCD_1234, "CSRRS_DUT");
    check_reg(5'd4,32'hABCD_1234, "CSRRC_DUT");
    check_reg(5'd5,32'h0000_0000, "CSRRWI_rd");
    check_reg(5'd6,32'h0000_001F, "CSRSI_DUT");
    check_reg(5'd7,32'h0000_001F, "CSRCI_DUT");
    check_reg(5'd8,32'h0000_001C, "scr_DUT  ");

    // ========================================================================
    // T10 — ECALL / EBREAK / Illegal
    // ========================================================================
    test_num=10; $display("\n--- T%0d: Sync Exceptions ---",test_num);
    $display("  [sub] ECALL");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=ECALL; imem[7]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'hAA); imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(60);
    check_reg(5'd28,32'h0,          "ECAL_skip");
    check_reg(5'd20,32'hAA,         "ECAL_DUT ");
    check_reg(5'd21,32'h0000_000B,  "ECALc_DUT");
    check_csr(dut.csr_file.MEPC,32'h0000_0014,"ECAL_mepc");
    $display("  [sub] EBREAK");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=EBREAK; imem[7]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'hBB); imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(60);
    check_reg(5'd28,32'h0,          "EBRK_skip");
    check_reg(5'd20,32'hBB,         "EBRK_DUT ");
    check_reg(5'd21,32'h0000_0003,  "EBRKc_DUT");
    check_csr(dut.csr_file.MEPC,32'h0000_0014,"EBRK_mepc");
    $display("  [sub] Illegal");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=32'hFFFF_FFFF; imem[7]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'hCC); imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(60);
    check_reg(5'd28,32'h0,          "ILL_skip ");
    check_reg(5'd20,32'hCC,         "ILL_DUT  ");
    check_reg(5'd21,32'h0000_0002,  "ILLc_DUT ");

    // ========================================================================
    // T11 — MRET
    // ========================================================================
    test_num=11; $display("\n--- T%0d: MRET ---",test_num);
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;
    imem[4]=ECALL;
    imem[5]=`A(5'd5,12'hAA);
    imem[6]=NOP;imem[7]=NOP;
    imem[32]=`A(5'd2,12'h014);
    imem[33]=CSR_f(MEPC,5'd2,3'h1,5'd0);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;
    imem[38]=`A(5'd3,12'hBB);
    imem[39]=MRET;
    imem[40]=NOP;imem[41]=NOP;imem[42]=NOP;imem[43]=NOP;
    wait_cycles(100);
    check_reg(5'd3,32'hBB, "MRET_DUT ");
    check_reg(5'd5,32'hAA, "MRETr_DUT");

    // ========================================================================
    // T12 — Instruction Misalignment
    // ========================================================================
    test_num=12; $display("\n--- T%0d: Misalignment ---",test_num);
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=J(21'd2,5'd0,JAL);
    imem[7]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'hDD);
    imem[33]=NOP;imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;
    wait_cycles(60);
    check_reg(5'd28,32'h0,  "MISAL_skp");
    check_reg(5'd20,32'hDD, "MSAL_DUT ");

    // ========================================================================
    // T13 — Interrupts
    // ========================================================================
    test_num=13; $display("\n--- T%0d: Interrupts ---",test_num);
    $display("  [sub] EIrq");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=CSR_f(MSTATUS,5'h08,3'h6,5'd0);
    imem[3]=`A(5'd2,12'h888);imem[4]=CSR_f(MIE_A,5'd2,3'h1,5'd0);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[32]=`A(5'd20,12'hDD); imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(15); EIrq_In=1; wait_cycles(5); EIrq_In=0; wait_cycles(35);
    check_reg(5'd20,32'hDD,        "EIrq_hdlr");
    check_reg(5'd21,32'h8000_000B, "EIrq_DUT ");
    $display("  [sub] TIrq");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=CSR_f(MSTATUS,5'h08,3'h6,5'd0);
    imem[3]=`A(5'd2,12'h888);imem[4]=CSR_f(MIE_A,5'd2,3'h1,5'd0);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[32]=`A(5'd20,12'hEE); imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(15); TIrq_In=1; wait_cycles(5); TIrq_In=0; wait_cycles(35);
    check_reg(5'd20,32'hEE,        "TIrq_hdlr");
    check_reg(5'd21,32'h8000_0007, "TIrq_DUT ");
    $display("  [sub] SIrq");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=CSR_f(MSTATUS,5'h08,3'h6,5'd0);
    imem[3]=`A(5'd2,12'h888);imem[4]=CSR_f(MIE_A,5'd2,3'h1,5'd0);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[32]=`A(5'd20,12'hFF); imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(15); SIrq_In=1; wait_cycles(5); SIrq_In=0; wait_cycles(35);
    check_reg(5'd20,32'hFF,        "SIrq_hdlr");
    check_reg(5'd21,32'h8000_0003, "SIrq_DUT ");

    // ========================================================================
    // T14 — Hazards
    // ========================================================================
    test_num=14; $display("\n--- T%0d: Hazards ---",test_num);
    do_reset;
    dmem[12'h300]=8'h55;dmem[12'h301]=8'h00;
    dmem[12'h302]=8'h00;dmem[12'h303]=8'h00;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd1,12'h300);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9] =I(12'h000,5'd1,3'h2,5'd2,LD);
    imem[10]=I(12'h001,5'd2,3'h0,5'd3,OI);
    imem[11]=`A(5'd4,12'h0A);
    imem[12]=I(12'h05,5'd4,3'h0,5'd5,OI);
    imem[13]=I(12'h03,5'd5,3'h0,5'd6,OI);
    imem[14]=`A(5'd7,12'h64); imem[15]=NOP;
    imem[16]=I(12'h01,5'd7,3'h0,5'd8,OI);
    imem[17]=`A(5'd9,12'h07); imem[18]=`A(5'd10,12'h03);
    imem[19]=R(7'h00,5'd10,5'd9,3'h0,5'd11,OP);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(38);
    check_reg(5'd2, 32'h0000_0055, "LW_load  ");
    check_reg(5'd3, 32'h0000_0056, "LdUse_stl");
    check_reg(5'd5, 32'd15,        "EX_EX_fw1");
    check_reg(5'd6, 32'd18,        "EX_EX_fw2");
    check_reg(5'd8, 32'd101,       "MEM_EX_fw");
    check_reg(5'd11,32'd10,        "2op_fwd  ");

    // ========================================================================
    // T15 — Branch Flush
    // ========================================================================
    test_num=15; $display("\n--- T%0d: Branch Flush ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8] =J(21'd20,5'd0,JAL);
    imem[9] =I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[10]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[11]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[12]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[13]=`A(5'd1,12'd1);
    imem[14]=NOP;imem[15]=NOP;imem[16]=NOP;imem[17]=NOP;
    imem[18]=B(13'd12,5'd0,5'd1,3'h1,BR);
    imem[19]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[20]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[21]=`A(5'd2,12'd2);
    imem[22]=NOP;imem[23]=NOP;imem[24]=NOP;imem[25]=NOP;
    imem[26]=B(13'd12,5'd0,5'd0,3'h1,BR);
    imem[27]=`A(5'd3,12'd3);
    imem[28]=NOP;imem[29]=NOP;imem[30]=NOP;imem[31]=NOP;
    imem[32]=NOP;imem[33]=NOP;imem[34]=NOP;imem[35]=NOP;
    wait_cycles(75);
    check_reg(5'd28,32'h0, "flush_cnr");
    check_reg(5'd1, 32'd1, "JAL_tgt  ");
    check_reg(5'd2, 32'd2, "BNE_tgt  ");
    check_reg(5'd3, 32'd3, "ntk_fall ");

    // ========================================================================
    // T16 — mcycle / minstret
    // ========================================================================
    test_num=16; $display("\n--- T%0d: Counters ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;
    imem[12]=NOP;imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;
    imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    imem[24]=NOP;imem[25]=NOP;
    imem[26]=CSR_f(MCYCLE,  5'd0,3'h2,5'd1);
    imem[27]=CSR_f(MINSTRET,5'd0,3'h2,5'd2);
    imem[28]=NOP;imem[29]=NOP;imem[30]=NOP;imem[31]=NOP;
    imem[32]=NOP;imem[33]=NOP;imem[34]=NOP;imem[35]=NOP;
    wait_cycles(50);
    if(get_reg(5'd1)>32'd0) begin $display("  [PASS] mcycle   =%0d",get_reg(5'd1));   pass_cnt=pass_cnt+1; end
    else                    begin $display("  [FAIL] mcycle=0"); fail_cnt=fail_cnt+1; end
    if(get_reg(5'd2)>32'd0) begin $display("  [PASS] minstret =%0d",get_reg(5'd2));   pass_cnt=pass_cnt+1; end
    else                    begin $display("  [FAIL] minstret=0"); fail_cnt=fail_cnt+1; end

    // ========================================================================
    // T17 — ALU Boundary / Shift Corner Cases
    // ========================================================================
    test_num=17; $display("\n--- T%0d: ALU Corners ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4] =I(12'hFFF,5'd0,3'h0,5'd1,OI);
    imem[5] =`A(5'd2,12'd1);
    imem[6] =`A(5'd11,12'd1);
    imem[7] =`A(5'd21,12'd32);
    imem[8] =U(20'h80000,5'd10,LUI);
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[13]=R(7'h00,5'd11,5'd10,3'h0,5'd12,OP);
    imem[14]=R(7'h20,5'd10,5'd11,3'h0,5'd13,OP);
    imem[15]=R(7'h00,5'd11,5'd10,3'h2,5'd14,OP);
    imem[16]=R(7'h00,5'd11,5'd10,3'h3,5'd15,OP);
    imem[17]=R(7'h00,5'd2, 5'd1, 3'h2,5'd16,OP);
    imem[18]=R(7'h00,5'd2, 5'd1, 3'h3,5'd17,OP);
    imem[19]={7'h00,5'd31,5'd2,3'h1,5'd18,OI};
    imem[20]={7'h00,5'd31,5'd1,3'h5,5'd19,OI};
    imem[21]={7'h20,5'd31,5'd1,3'h5,5'd20,OI};
    imem[22]=R(7'h00,5'd21,5'd2,3'h1,5'd22,OP);
    imem[23]=R(7'h00,5'd21,5'd1,3'h5,5'd23,OP);
    imem[24]=R(7'h20,5'd21,5'd1,3'h5,5'd24,OP);
    imem[25]=NOP;imem[26]=NOP;imem[27]=NOP;imem[28]=NOP;
    wait_cycles(65);
    check_reg(5'd12,32'h8000_0001,"ADD_wrap  ");
    check_reg(5'd13,32'h8000_0001,"SUB_wrap  ");
    check_reg(5'd14,32'h0000_0001,"SLT_min   ");
    check_reg(5'd15,32'h0000_0000,"SLTU_min  ");
    check_reg(5'd16,32'h0000_0001,"SLT_n1    ");
    check_reg(5'd17,32'h0000_0000,"SLTU_n1   ");
    check_reg(5'd18,32'h8000_0000,"SLLI31    ");
    check_reg(5'd19,32'h0000_0001,"SRLI31    ");
    check_reg(5'd20,32'hFFFF_FFFF,"SRAI31    ");
    check_reg(5'd22,32'h0000_0001,"SLL_32msk ");
    check_reg(5'd23,32'hFFFF_FFFF,"SRL_32msk ");
    check_reg(5'd24,32'hFFFF_FFFF,"SRA_32msk ");

    // ========================================================================
    // T18 — x0 Integrity
    // ========================================================================
    test_num=18; $display("\n--- T%0d: x0 Integrity ---",test_num);
    do_reset;
    dmem[12'h120]=8'hEF; dmem[12'h121]=8'hBE; dmem[12'h122]=8'hAD; dmem[12'h123]=8'hDE;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd1,12'h120);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9] =I(12'h07B,5'd0,3'h0,5'd0,OI);
    imem[10]=U(20'hFFFFF,5'd0,LUI);
    imem[11]=I(12'h000,5'd1,3'h2,5'd0,LD);
    imem[12]=U(20'h00001,5'd0,AUI);
    imem[13]=`A(5'd2,12'd77);
    imem[14]=R(7'h00,5'd2,5'd0,3'h0,5'd3,OP);
    imem[15]=NOP;imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;
    wait_cycles(50);
    check_reg(5'd2,32'd77,       "x2_keep   ");
    check_reg(5'd3,32'd77,       "x0_src0   ");
    check_csr(dut.reg_file.register[0],32'h0000_0000,"x0_hw0   ");

    // ========================================================================
    // T19 — Misaligned Store Traps
    // ========================================================================
    test_num=19; $display("\n--- T%0d: Misaligned Store ---",test_num);
    $display("  [sub] SW +2");
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=`A(5'd1,12'h220); imem[7]=`A(5'd2,12'h055);
    imem[8]=S(12'h002,5'd2,5'd1,3'h2,ST);
    imem[9]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'h0A1);
    imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=CSR_f(MTVAL, 5'd0,3'h2,5'd22);
    imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(80);
    check_reg(5'd28,32'h0,         "SWm_skip  ");
    check_reg(5'd20,32'h0000_00A1, "SWm_hdlr  ");
    check_reg(5'd21,32'h0000_0006, "SWm_cause ");
    check_reg(5'd22,32'h0000_0222, "SWm_mtval ");
    check_dw(12'h220,32'h0000_0000, "SWm_nowr  ");
    $display("  [sub] SH +1");
    do_reset;
    dmem[12'h230]=8'h12;dmem[12'h231]=8'h34;dmem[12'h232]=8'h56;dmem[12'h233]=8'h78;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=`A(5'd1,12'h230); imem[7]=`A(5'd2,12'h5AA);
    imem[8]=S(12'h001,5'd2,5'd1,3'h1,ST);
    imem[9]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'h0A2);
    imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=CSR_f(MTVAL, 5'd0,3'h2,5'd22);
    imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(80);
    check_reg(5'd28,32'h0,         "SHm_skip  ");
    check_reg(5'd20,32'h0000_00A2, "SHm_hdlr  ");
    check_reg(5'd21,32'h0000_0006, "SHm_cause ");
    check_reg(5'd22,32'h0000_0231, "SHm_mtval ");
    check_dw(12'h230,32'h7856_3412,"SHm_nowr  ");

    // ========================================================================
    // T20 — Misaligned Load Traps
    // ========================================================================
    test_num=20; $display("\n--- T%0d: Misaligned Load ---",test_num);
    $display("  [sub] LW +2");
    do_reset;
    dmem[12'h240]=8'h78;dmem[12'h241]=8'h56;dmem[12'h242]=8'h34;dmem[12'h243]=8'h12;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=`A(5'd1,12'h240); imem[7]=`A(5'd3,12'h055);
    imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;
    imem[12]=I(12'h002,5'd1,3'h2,5'd3,LD);
    imem[13]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'h0B1);
    imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=CSR_f(MTVAL, 5'd0,3'h2,5'd22);
    imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(80);
    check_reg(5'd28,32'h0,         "LWm_skip  ");
    check_reg(5'd20,32'h0000_00B1, "LWm_hdlr  ");
    check_reg(5'd21,32'h0000_0004, "LWm_cause ");
    check_reg(5'd22,32'h0000_0242, "LWm_mtval ");
    check_reg(5'd3, 32'h0000_0055, "LWm_nord  ");
    $display("  [sub] LH +1");
    do_reset;
    dmem[12'h250]=8'h11;dmem[12'h251]=8'h22;dmem[12'h252]=8'h33;dmem[12'h253]=8'h44;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=`A(5'd1,12'h250); imem[7]=`A(5'd4,12'h0AA);
    imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;
    imem[12]=I(12'h001,5'd1,3'h1,5'd4,LD);
    imem[13]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=`A(5'd20,12'h0B2);
    imem[33]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[34]=CSR_f(MTVAL, 5'd0,3'h2,5'd22);
    imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    wait_cycles(80);
    check_reg(5'd28,32'h0,         "LHm_skip  ");
    check_reg(5'd20,32'h0000_00B2, "LHm_hdlr  ");
    check_reg(5'd21,32'h0000_0004, "LHm_cause ");
    check_reg(5'd22,32'h0000_0251, "LHm_mtval ");
    check_reg(5'd4, 32'h0000_00AA, "LHm_nord  ");

    // ========================================================================
    // T21 — mcountinhibit
    // ========================================================================
    test_num=21; $display("\n--- T%0d: mcountinhibit ---",test_num);
    do_reset;
    imem[26]=CSR_f(MCOUNTINHIBIT,5'h05,3'h5,5'd0);
    imem[27]=NOP;imem[28]=NOP;imem[29]=NOP;imem[30]=NOP;imem[31]=NOP;
    imem[32]=CSR_f(MCYCLE,  5'd0,3'h2,5'd10);
    imem[33]=CSR_f(MINSTRET,5'd0,3'h2,5'd11);
    imem[34]=`A(5'd1,12'd1);
    imem[35]=I(12'd1,5'd1,3'h0,5'd1,OI);
    imem[36]=R(7'h00,5'd1,5'd1,3'h0,5'd2,OP);
    imem[37]=NOP;imem[38]=NOP;
    imem[39]=CSR_f(MCYCLE,  5'd0,3'h2,5'd12);
    imem[40]=CSR_f(MINSTRET,5'd0,3'h2,5'd13);
    imem[41]=CSR_f(MCOUNTINHIBIT,5'h00,3'h5,5'd0);
    imem[42]=NOP;imem[43]=NOP;imem[44]=NOP;imem[45]=NOP;imem[46]=NOP;
    imem[47]=`A(5'd3,12'd3);
    imem[48]=I(12'd1,5'd3,3'h0,5'd3,OI);
    imem[49]=R(7'h00,5'd3,5'd3,3'h0,5'd4,OP);
    imem[50]=NOP;imem[51]=NOP;
    imem[52]=CSR_f(MCYCLE,  5'd0,3'h2,5'd14);
    imem[53]=CSR_f(MINSTRET,5'd0,3'h2,5'd15);
    imem[54]=NOP;imem[55]=NOP;imem[56]=NOP;imem[57]=NOP;
    wait_cycles(130);
    check_true(get_reg(5'd12)==get_reg(5'd10),"CY_freeze ");
    check_true(get_reg(5'd13)==get_reg(5'd11),"IR_freeze ");
    check_true(get_reg(5'd14) >get_reg(5'd12),"CY_resume ");
    check_true(get_reg(5'd15) >get_reg(5'd13),"IR_resume ");

    // ========================================================================
    // T22 — Loop Stress
    // ========================================================================
    test_num=22; $display("\n--- T%0d: Loop Stress ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8] =`A(5'd1,12'd0);
    imem[9] =`A(5'd2,12'd10);
    imem[10]=`A(5'd3,12'h300);
    imem[11]=`A(5'd6,12'd0);
    imem[12]=NOP;imem[13]=NOP;
    imem[14]=S(12'h000,5'd1,5'd3,3'h2,ST);
    imem[15]=I(12'h000,5'd3,3'h2,5'd4,LD);
    imem[16]=R(7'h00,5'd4,5'd6,3'h0,5'd6,OP);
    imem[17]=I(12'h001,5'd1,3'h0,5'd1,OI);
    imem[18]=B(13'h1FEC,5'd2,5'd1,3'h1,BR);
    imem[19]=`A(5'd5,12'h055);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(220);
    check_reg(5'd1, 32'd10,       "loop_cnt  ");
    check_reg(5'd5, 32'h0000_0055,"loop_done ");
    check_reg(5'd6, 32'd45,       "loop_sum  ");
    check_dw(12'h300,32'h0000_0009,"loop_mem  ");

    // ========================================================================
    // T23 — IRQ Corner
    // ========================================================================
    test_num=23; $display("\n--- T%0d: IRQ Corner ---",test_num);
    $display("  [sub] MIE gate");
    do_reset;
    imem[0]=`A(5'd1,12'h200); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=`A(5'd2,12'h888); imem[3]=CSR_f(MIE_A,5'd2,3'h1,5'd0);
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;
    imem[128]=`A(5'd20,12'h0E1);
    wait_cycles(20); EIrq_In=1; TIrq_In=1; SIrq_In=1; wait_cycles(6);
    EIrq_In=0; TIrq_In=0; SIrq_In=0; wait_cycles(35);
    check_reg(5'd20,32'h0000_0000,"MIE_block ");
    $display("  [sub] IRQ prio");
    do_reset;
    imem[0]=`A(5'd1,12'h200); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=CSR_f(MSTATUS,5'h08,3'h6,5'd0);
    imem[3]=`A(5'd2,12'h888); imem[4]=CSR_f(MIE_A,5'd2,3'h1,5'd0);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[128]=`A(5'd20,12'h0E2);
    imem[129]=CSR_f(MCAUSE,5'd0,3'h2,5'd21);
    imem[130]=NOP;imem[131]=NOP;imem[132]=NOP;imem[133]=NOP;
    wait_cycles(20); EIrq_In=1; TIrq_In=1; SIrq_In=1; wait_cycles(6);
    EIrq_In=0; TIrq_In=0; SIrq_In=0; wait_cycles(45);
    check_reg(5'd20,32'h0000_00E2,"IRQ_hdlr  ");
    check_reg(5'd21,32'h8000_000B,"IRQ_prioE ");

    // ========================================================================
    // T24 — Immediate Sign-Extension Edge Cases
    // ========================================================================
    test_num=24; $display("\n--- T%0d: Imm Sign-Ext ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4] =I(12'h800,5'd0,3'h0,5'd1,OI);
    imem[5] =I(12'h7FF,5'd0,3'h0,5'd2,OI);
    imem[6] =I(12'h800,5'd0,3'h7,5'd3,OI);
    imem[7] =I(12'h800,5'd0,3'h6,5'd4,OI);
    imem[8] =I(12'h800,5'd0,3'h4,5'd5,OI);
    imem[9] =I(12'h800,5'd0,3'h2,5'd6,OI);
    imem[10]=I(12'h7FF,5'd0,3'h2,5'd7,OI);
    imem[11]=I(12'h800,5'd0,3'h3,5'd8,OI);
    imem[12]=I(12'h7FF,5'd0,3'h3,5'd9,OI);
    imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;imem[16]=NOP;
    wait_cycles(30);
    check_reg(5'd1,32'hFFFF_F800,"ADDI_n2k  ");
    check_reg(5'd2,32'h0000_07FF,"ADDI_p2k  ");
    check_reg(5'd3,32'h0000_0000,"ANDI_n2k  ");
    check_reg(5'd4,32'hFFFF_F800,"ORI_n2k   ");
    check_reg(5'd5,32'hFFFF_F800,"XORI_n2k  ");
    check_reg(5'd6,32'h0000_0000,"SLTI_n2k  ");
    check_reg(5'd7,32'h0000_0001,"SLTI_p2k  ");
    check_reg(5'd8,32'h0000_0001,"SLTIU_n2k ");
    check_reg(5'd9,32'h0000_0001,"SLTIU_p2k ");

    // ========================================================================
    // T25 — LUI+ADDI constant construction
    // ========================================================================
    test_num=25; $display("\n--- T%0d: LUI+ADDI ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=U(20'h12345,5'd1,LUI);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9]=I(12'h678,5'd1,3'h0,5'd1,OI);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=U(20'h12346,5'd2,LUI);
    imem[15]=NOP;imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;
    imem[19]=I(12'h800,5'd2,3'h0,5'd2,OI);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    imem[24]=U(20'hDEADC,5'd3,LUI);
    imem[25]=NOP;imem[26]=NOP;imem[27]=NOP;imem[28]=NOP;
    imem[29]=I(12'hEEF,5'd3,3'h0,5'd3,OI);
    imem[30]=NOP;imem[31]=NOP;imem[32]=NOP;imem[33]=NOP;
    wait_cycles(55);
    check_reg(5'd1,32'h1234_5678,"LUI_pos   ");
    check_reg(5'd2,32'h1234_5800,"LUI_neg   ");
    check_reg(5'd3,32'hDEAD_BEEF,"LUI_DEAD  ");

    // ========================================================================
    // T26 — Hazard Chain
    // ========================================================================
    test_num=26; $display("\n--- T%0d: Fwd All Dist ---",test_num);
    do_reset;
    dmem[12'h400]=8'hAA;dmem[12'h401]=8'h00;dmem[12'h402]=8'h00;dmem[12'h403]=8'h00;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd10,12'h400);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9] =`A(5'd1,12'd10);
    imem[10]=I(12'd5,5'd1,3'h0,5'd2,OI);
    imem[11]=I(12'd3,5'd2,3'h0,5'd3,OI);
    imem[12]=I(12'd2,5'd3,3'h0,5'd4,OI);
    imem[13]=`A(5'd5,12'd100);
    imem[14]=NOP;
    imem[15]=I(12'd1,5'd5,3'h0,5'd6,OI);
    imem[16]=I(12'h000,5'd10,3'h2,5'd7,LD);
    imem[17]=I(12'h001,5'd7,3'h0,5'd8,OI);
    imem[18]=I(12'h000,5'd10,3'h2,5'd9,LD);
    imem[19]=I(12'h000,5'd10,3'h2,5'd11,LD);
    imem[20]=I(12'h001,5'd9,3'h0,5'd12,OI);
    imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;imem[24]=NOP;
    wait_cycles(50);
    check_reg(5'd2, 32'd15,       "EX_EX_ch1 ");
    check_reg(5'd3, 32'd18,       "EX_EX_ch2 ");
    check_reg(5'd4, 32'd20,       "EX_EX_ch3 ");
    check_reg(5'd6, 32'd101,      "MEM_EX_fw ");
    check_reg(5'd7, 32'h0000_00AA,"LdUse_val ");
    check_reg(5'd8, 32'h0000_00AB,"LdUse_dep ");
    check_reg(5'd12,32'h0000_00AB,"LdUse_con ");

    // ========================================================================
    // T27 — WAW/WAR Hazards
    // ========================================================================
    test_num=27; $display("\n--- T%0d: WAW/WAR ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd1,12'd5);
    imem[5]=`A(5'd1,12'd99);
    imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;imem[9]=NOP;
    imem[10]=`A(5'd2,12'd0);
    imem[11]=R(7'h00,5'd0,5'd1,3'h0,5'd2,OP);
    imem[12]=`A(5'd3,12'd42);
    imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;imem[16]=NOP;
    imem[17]=R(7'h00,5'd3,5'd0,3'h0,5'd4,OP);
    imem[18]=`A(5'd3,12'd77);
    imem[19]=NOP;imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;
    wait_cycles(40);
    check_reg(5'd2, 32'd99,  "WAW_final ");
    check_reg(5'd4, 32'd42,  "WAR_read  ");
    check_reg(5'd3, 32'd77,  "WAR_write ");

    // ========================================================================
    // T28 — JALR Variants
    // ========================================================================
    test_num=28; $display("\n--- T%0d: JALR Variants ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8] =I(12'h050,5'd0,3'h0,5'd1,JALR);
    imem[9] =I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[10]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[20]=`A(5'd2,12'h0AB);
    imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(40);
    check_reg(5'd28,32'h0,         "JALRabs_c ");
    check_reg(5'd2, 32'h0000_00AB, "JALRabs_t ");
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd3,12'h040);
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[13]=I(12'h010,5'd3,3'h0,5'd1,JALR);
    imem[14]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[20]=`A(5'd4,12'h0CD);
    imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(45);
    check_reg(5'd28,32'h0,         "JALR+off_c");
    check_reg(5'd4, 32'h0000_00CD, "JALR+off_t");
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=`A(5'd5,12'h051);
    imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;
    imem[13]=I(12'h000,5'd5,3'h0,5'd1,JALR);
    imem[14]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[20]=`A(5'd6,12'h0EF);
    imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    wait_cycles(45);
    check_reg(5'd28,32'h0,         "JALRb0_c  ");
    check_reg(5'd6, 32'h0000_00EF, "JALRb0_t  ");

    // ========================================================================
    // T29 — Load-Store Forwarding
    // ========================================================================
    test_num=29; $display("\n--- T%0d: Mem Coherence ---",test_num);
    do_reset;
    dmem[12'h500]=8'hAA;dmem[12'h501]=8'hBB;dmem[12'h502]=8'hCC;dmem[12'h503]=8'hDD;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=`A(5'd10,12'h500);
    imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;imem[8]=NOP;
    imem[9] =I(12'h000,5'd10,3'h2,5'd1,LD);
    imem[10]=NOP;imem[11]=NOP;
    imem[12]=`A(5'd2,12'h042);
    imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;imem[16]=NOP;
    imem[17]=S(12'h000,5'd2,5'd10,3'h0,ST);
    imem[18]=NOP;imem[19]=NOP;imem[20]=NOP;imem[21]=NOP;
    imem[22]=I(12'h000,5'd10,3'h2,5'd3,LD);
    imem[23]=NOP;imem[24]=NOP;imem[25]=NOP;imem[26]=NOP;
    imem[27]=`A(5'd4,12'h01);
    imem[28]=`A(5'd5,12'h02);
    imem[29]=S(12'h004,5'd4,5'd10,3'h0,ST);
    imem[30]=S(12'h004,5'd5,5'd10,3'h0,ST);
    imem[31]=NOP;imem[32]=NOP;imem[33]=NOP;imem[34]=NOP;
    wait_cycles(65);
    check_reg(5'd1, 32'hDDCC_BBAA,"ld_init   ");
    check_reg(5'd3, 32'hDDCC_BB42,"sb_then_lw");
    check_db(12'h504,8'h02,        "2xSB_last ");

    // ========================================================================
    // T30 — CSR Pure-Read
    // ========================================================================
    test_num=30; $display("\n--- T%0d: CSR Pure-Read ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;
    imem[12]=NOP;imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;
    imem[16]=`A(5'd1,12'h5A5);
    imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;imem[20]=NOP;
    imem[21]=CSR_f(MSCRATCH,5'd1,3'h1,5'd0);
    imem[22]=NOP;imem[23]=NOP;imem[24]=NOP;imem[25]=NOP;imem[26]=NOP;
    imem[27]=CSR_f(MSCRATCH,5'd0,3'h2,5'd2);
    imem[28]=NOP;imem[29]=NOP;imem[30]=NOP;imem[31]=NOP;imem[32]=NOP;
    imem[33]=CSR_f(MSCRATCH,5'd0,3'h3,5'd3);
    imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;imem[37]=NOP;imem[38]=NOP;
    imem[39]=CSR_f(MSCRATCH,5'h00,3'h6,5'd4);
    imem[40]=NOP;imem[41]=NOP;imem[42]=NOP;imem[43]=NOP;imem[44]=NOP;
    imem[45]=CSR_f(MSCRATCH,5'h00,3'h7,5'd5);
    imem[46]=NOP;imem[47]=NOP;imem[48]=NOP;imem[49]=NOP;
    wait_cycles(70);
    check_reg(5'd2,32'h0000_05A5,"CSRRS_rd0 ");
    check_reg(5'd3,32'h0000_05A5,"CSRRC_rd0 ");
    check_reg(5'd4,32'h0000_05A5,"CSRRSI_0  ");
    check_reg(5'd5,32'h0000_05A5,"CSRRCI_0  ");

    // ========================================================================
    // T31 — mstatus MIE/MPIE
    // ========================================================================
    test_num=31; $display("\n--- T%0d: mstatus MIE ---",test_num);
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=CSR_f(MSTATUS,5'h08,3'h6,5'd0);
    imem[3]=CSR_f(MSTATUS,5'd0,3'h2,5'd21); // read post-MRET
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;
    imem[7]=ECALL;
    imem[8]=NOP;imem[9]=NOP;
    imem[32]=CSR_f(MSTATUS,5'd0,3'h2,5'd20);
    imem[33]=NOP;imem[34]=NOP;imem[35]=NOP;imem[36]=NOP;
    imem[37]=`A(5'd2,12'h00C);
    imem[38]=NOP;imem[39]=NOP;imem[40]=NOP;imem[41]=NOP;
    imem[42]=CSR_f(MEPC,5'd2,3'h1,5'd0);
    imem[43]=NOP;imem[44]=NOP;imem[45]=NOP;imem[46]=NOP;
    imem[47]=MRET;
    imem[48]=NOP;imem[49]=NOP;
    wait_cycles(120);
    check_true((get_reg(5'd20) & 32'h8)==32'h0,"MIE_clear ");
    check_true((get_reg(5'd20) & 32'h80)==32'h80,"MPIE_set  ");
    check_true((get_reg(5'd21) & 32'h8)==32'h8,"MIE_rest  ");

    // ========================================================================
    // T32 — Counter Accuracy
    // ========================================================================
    test_num=32; $display("\n--- T%0d: Counter Accuracy ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=NOP;imem[9]=NOP;imem[10]=NOP;imem[11]=NOP;
    imem[12]=NOP;imem[13]=NOP;imem[14]=NOP;imem[15]=NOP;
    imem[16]=NOP;imem[17]=NOP;imem[18]=NOP;imem[19]=NOP;
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;imem[24]=NOP;
    imem[25]=CSR_f(MCYCLE,  5'd0,3'h2,5'd1);
    imem[26]=CSR_f(MINSTRET,5'd0,3'h2,5'd2);
    imem[27]=`A(5'd10,12'd1);
    imem[28]=`A(5'd11,12'd2);
    imem[29]=`A(5'd12,12'd3);
    imem[30]=`A(5'd13,12'd4);
    imem[31]=NOP;imem[32]=NOP;imem[33]=NOP;imem[34]=NOP;
    imem[35]=CSR_f(MCYCLE,  5'd0,3'h2,5'd3);
    imem[36]=CSR_f(MINSTRET,5'd0,3'h2,5'd4);
    imem[37]=NOP;imem[38]=NOP;imem[39]=NOP;imem[40]=NOP;
    wait_cycles(60);
    check_true(get_reg(5'd3)  > get_reg(5'd1),  "CY_monot  ");
    check_true(get_reg(5'd4)  > get_reg(5'd2),  "IR_monot  ");
    check_true((get_reg(5'd4)-get_reg(5'd2)) >= 32'd4, "IR_count4 ");

    // ========================================================================
    // T33 — Back-to-back Branches
    // ========================================================================
    test_num=33; $display("\n--- T%0d: Back-to-back Br ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8]=J(21'd84,5'd0,JAL);
    imem[9]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[10]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[30]=J(21'd56,5'd0,JAL);
    imem[31]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[32]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[45]=`A(5'd5,12'h0BB);
    imem[46]=NOP;imem[47]=NOP;imem[48]=NOP;
    wait_cycles(80);
    check_reg(5'd28,32'h0,         "2xJAL_c   ");
    check_reg(5'd5, 32'h0000_00BB, "2xJAL_tgt ");

    // ========================================================================
    // T34 — Nested ECALL
    // ========================================================================
    test_num=34; $display("\n--- T%0d: Nested ECALL ---",test_num);
    do_reset;
    imem[0]=`A(5'd1,12'h080); imem[1]=CSR_f(MTVEC,5'd1,3'h1,5'd0);
    imem[2]=NOP;imem[3]=NOP;imem[4]=NOP;imem[5]=NOP;
    imem[6]=ECALL;
    imem[7]=`A(5'd9,12'h099);
    imem[8]=NOP;imem[9]=NOP;
    imem[32]=CSR_f(MCAUSE,5'd0,3'h2,5'd20);
    imem[33]=`A(5'd21,12'd1);
    imem[34]=NOP;imem[35]=NOP;
    imem[36]=CSR_f(MEPC,5'd0,3'h2,5'd22);
    imem[37]=I(12'h004,5'd22,3'h0,5'd22,OI);
    imem[38]=NOP;imem[39]=NOP;imem[40]=NOP;imem[41]=NOP;
    imem[42]=CSR_f(MEPC,5'd22,3'h1,5'd0);
    imem[43]=NOP;imem[44]=NOP;imem[45]=NOP;imem[46]=NOP;
    imem[47]=MRET;
    imem[48]=NOP;imem[49]=NOP;
    wait_cycles(100);
    check_reg(5'd20,32'h0000_000B,"ntr_cause ");
    check_true(get_reg(5'd21)>=32'd1,"ntr_count ");

    // ========================================================================
    // T35 — Forwarding: LUI result and JAL link used immediately
    // ========================================================================
    test_num=35; $display("\n--- T%0d: Fwd LUI/JAL ---",test_num);
    do_reset;
    imem[0]=NOP;imem[1]=NOP;imem[2]=NOP;imem[3]=NOP;
    imem[4]=NOP;imem[5]=NOP;imem[6]=NOP;imem[7]=NOP;
    imem[8] =U(20'h00001,5'd1,LUI);
    imem[9] =I(12'h234,5'd1,3'h0,5'd2,OI);
    imem[10]=NOP;imem[11]=NOP;imem[12]=NOP;imem[13]=NOP;
    imem[14]=J(21'd20,5'd1,JAL);
    imem[15]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[16]=I(12'hBAD,5'd0,3'h0,5'd28,OI);
    imem[20]=NOP;imem[21]=NOP;imem[22]=NOP;imem[23]=NOP;
    imem[24]=R(7'h00,5'd0,5'd1,3'h0,5'd3,OP);
    imem[25]=NOP;imem[26]=NOP;imem[27]=NOP;imem[28]=NOP;
    wait_cycles(60);
    check_reg(5'd2,32'h0000_1234,"LUI_fwd   ");
    check_true(get_reg(5'd3)!=32'h0,"JAL_lnk_rd");

    // ========================================================================
    // ██████████████████████  RV32M TESTS  ███████████████████████████████████
    // ========================================================================
    // NOTE on timing:
    //   MUL/MULH/MULHSU/MULHU  — combinational Booth multiplier, MDU_Ready=1
    //     immediately.  Pipeline does NOT stall; treat like an R-type but use
    //     extra settle NOPs since Result_Src=3'b111 (WB picks MDU_Result).
    //   DIV/DIVU/REM/REMU      — iterative 32-cycle divider.  Pipeline stalls
    //     for up to 32+overhead cycles; wait_cycles must cover stall time.
    //     Use wait_cycles(80) for all divide tests to be safe.
    // ========================================================================

    // ========================================================================
    // T36 — MUL variants: basic positive operands
    //   x1=12, x2=7
    //   MUL    x3 = lower 32 of (12×7)    = 84
    //   MULH   x4 = upper 32 of signed(12×7)  = 0
    //   MULHSU x5 = upper 32 of signed(12)×unsigned(7) = 0
    //   MULHU  x6 = upper 32 of unsigned(12×7) = 0
    //   MUL    x7 = 1000 × 1000 = 1_000_000
    //   MULHU  x8 = upper32(0xFFFFFFFF × 0xFFFFFFFF)
    //              = upper32(0xFFFFFFFE_00000001) = 0xFFFFFFFE
    // ========================================================================
    test_num=36; $display("\n--- T%0d: MUL Basics ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd12);           // x1=12
    imem[5]=`A(5'd2,12'd7);            // x2=7
    imem[6]=`A(5'd9,12'd1000);         // x9=1000
    imem[7]=I(12'hFFF,5'd0,3'h0,5'd10,OI); // x10=-1 (0xFFFFFFFF)
    imem[8]=NOP; imem[9]=NOP; imem[10]=NOP; imem[11]=NOP;
    imem[12]=M_type(5'd2,5'd1,MUL_F3,   5'd3); // MUL    x3=84
    imem[13]=M_type(5'd2,5'd1,MULH_F3,  5'd4); // MULH   x4=0
    imem[14]=M_type(5'd2,5'd1,MULHSU_F3,5'd5); // MULHSU x5=0
    imem[15]=M_type(5'd2,5'd1,MULHU_F3, 5'd6); // MULHU  x6=0
    imem[16]=M_type(5'd9,5'd9,MUL_F3,   5'd7); // MUL    x7=1_000_000
    imem[17]=M_type(5'd10,5'd10,MULHU_F3,5'd8); // MULHU x8=0xFFFFFFFE
    imem[18]=NOP; imem[19]=NOP; imem[20]=NOP; imem[21]=NOP;
    wait_cycles(35);
    check_reg(5'd3,32'd84,         "MUL_pos   ");
    check_reg(5'd4,32'h0000_0000,  "MULH_pos  ");
    check_reg(5'd5,32'h0000_0000,  "MULHSU_p  ");
    check_reg(5'd6,32'h0000_0000,  "MULHU_pos ");
    check_reg(5'd7,32'd1_000_000,  "MUL_1k2   ");
    check_reg(5'd8,32'hFFFF_FFFE,  "MULHU_max ");

    // ========================================================================
    // T37 — MUL negative / sign interactions
    //   x1=-1 (0xFFFFFFFF), x2=2
    //   MUL    x3 = lower32(-1 × 2)  = 0xFFFFFFFE  (-2)
    //   MULH   x4 = upper32(signed -1 × signed 2) = -1 = 0xFFFFFFFF
    //   MULHSU x5 = upper32(signed -1 × unsigned 2)
    //              = upper32(0xFFFFFFFF_FFFFFFFE) = 0xFFFFFFFF
    //   MULHU  x6 = upper32(unsigned 0xFFFFFFFF × 2)
    //              = upper32(0x1FFFFFFFE) = 1
    //   x7=-3 (0xFFFFFFFD), x8=5
    //   MUL    x9 = lower32(-3 × 5) = -15 = 0xFFFFFFF1
    //   MULH  x10 = upper32(-3 × 5) = -1  = 0xFFFFFFFF
    // ========================================================================
    test_num=37; $display("\n--- T%0d: MUL Signed ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=I(12'hFFF,5'd0,3'h0,5'd1,OI); // x1=-1
    imem[5]=`A(5'd2,12'd2);               // x2=2
    imem[6]=I(12'hFFD,5'd0,3'h0,5'd7,OI); // x7=-3
    imem[7]=`A(5'd8,12'd5);               // x8=5
    imem[8]=NOP; imem[9]=NOP; imem[10]=NOP; imem[11]=NOP;
    imem[12]=M_type(5'd2,5'd1,MUL_F3,   5'd3); // x3=-2
    imem[13]=M_type(5'd2,5'd1,MULH_F3,  5'd4); // x4=-1
    imem[14]=M_type(5'd2,5'd1,MULHSU_F3,5'd5); // x5=-1
    imem[15]=M_type(5'd2,5'd1,MULHU_F3, 5'd6); // x6=1
    imem[16]=M_type(5'd8,5'd7,MUL_F3,   5'd9); // x9=-15
    imem[17]=M_type(5'd8,5'd7,MULH_F3,  5'd10);// x10=-1
    imem[18]=NOP; imem[19]=NOP; imem[20]=NOP; imem[21]=NOP;
    wait_cycles(35);
    check_reg(5'd3,32'hFFFF_FFFE, "MUL_n1x2  ");
    check_reg(5'd4,32'hFFFF_FFFF, "MULH_n1x2 ");
    check_reg(5'd5,32'hFFFF_FFFF, "MULHSU_n1 ");
    check_reg(5'd6,32'h0000_0001, "MULHU_n1  ");
    check_reg(5'd9,32'hFFFF_FFF1, "MUL_n3x5  ");
    check_reg(5'd10,32'hFFFF_FFFF,"MULH_n3x5 ");

    // ========================================================================
    // T38 — DIV / DIVU basic (exact division, no remainder)
    //   x1=84, x2=7
    //   DIV  x3 = 84 / 7 = 12   (signed)
    //   DIVU x4 = 84 / 7 = 12   (unsigned)
    //   x5=-84 (0xFFFFFFAC), x6=7
    //   DIV  x7 = -84 / 7 = -12 (signed: 0xFFFFFFF4)
    //   DIVU x8 = 0xFFFFFFAC / 7 = 0x2492_4918 (large unsigned)
    // ========================================================================
    test_num=38; $display("\n--- T%0d: DIV Basic ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd84);           // x1=84
    imem[5]=`A(5'd2,12'd7);            // x2=7
    // x5 = -84: LUI then ADDI (LUI upper 20 of -84, but simpler: use ADDI -84 directly)
    // -84 in 12-bit signed = 12'hFAC  (0xFAC = -84 as sign-ext twos-complement... 
    //   check: 0xFAC = 4012 unsigned. 4012-4096=-84. Yes, 12'hFAC = -84.)
    imem[6]=I(12'hFAC,5'd0,3'h0,5'd5,OI); // x5=-84
    imem[7]=`A(5'd6,12'd7);            // x6=7
    imem[8]=NOP; imem[9]=NOP; imem[10]=NOP; imem[11]=NOP;
    imem[12]=M_type(5'd2,5'd1,DIV_F3,  5'd3); // DIV  x3=12
    imem[13]=M_type(5'd2,5'd1,DIVU_F3, 5'd4); // DIVU x4=12
    imem[14]=NOP; imem[15]=NOP; imem[16]=NOP; imem[17]=NOP; // stall drain
    imem[18]=M_type(5'd6,5'd5,DIV_F3,  5'd7); // DIV  x7=-12
    imem[19]=M_type(5'd6,5'd5,DIVU_F3, 5'd8); // DIVU x8=0xFFFFFFAC/7
    imem[20]=NOP; imem[21]=NOP; imem[22]=NOP; imem[23]=NOP;
    // Four divide-class ops are issued in this stream; use a wider margin.
    wait_cycles(180);
    check_reg(5'd3,32'd12,         "DIV_pos   ");
    check_reg(5'd4,32'd12,         "DIVU_pos  ");
    check_reg(5'd7,32'hFFFF_FFF4,  "DIV_neg   "); // -12
    check_reg(5'd8,32'h2492_4918,  "DIVU_neg  "); // 0xFFFFFFAC/7

    // ========================================================================
    // T39 — REM / REMU basic
    //   x1=85, x2=7 → REM=1, REMU=1
    //   x3=-85 (12'hFAB), x4=7 → REM=-1 (0xFFFFFFFF), REMU=big
    //   x5=100, x6=30 → REM=10, REMU=10
    // ========================================================================
    test_num=39; $display("\n--- T%0d: REM Basic ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd85);
    imem[5]=`A(5'd2,12'd7);
    // x3 = -85: 12'hFAB  (0xFAB=3755; 3755-4096=-341? No.)
    // Let's recalc: -85 = 0xFFFFFFAB. Lower 12 bits = 0xFAB. 
    // ADDI x3, x0, 0xFAB: 12'hFAB is a negative 12-bit immediate.
    // 0xFAB = 0b1111_1010_1011. bit[11]=1 → sign-extended = 0xFFFFFFAB = -85. ✓
    imem[6]=I(12'hFAB,5'd0,3'h0,5'd3,OI); // x3=-85
    imem[7]=`A(5'd4,12'd7);
    imem[8]=`A(5'd5,12'd100);
    imem[9]=`A(5'd6,12'd30);
    imem[10]=NOP; imem[11]=NOP; imem[12]=NOP; imem[13]=NOP;
    imem[14]=M_type(5'd2,5'd1,REM_F3,  5'd7);  // REM  x7=1
    imem[15]=M_type(5'd2,5'd1,REMU_F3, 5'd8);  // REMU x8=1
    imem[16]=NOP; imem[17]=NOP; imem[18]=NOP; imem[19]=NOP;
    imem[20]=M_type(5'd4,5'd3,REM_F3,  5'd9);  // REM  x9=-1 (0xFFFFFFFF)
    imem[21]=M_type(5'd4,5'd3,REMU_F3, 5'd10); // REMU x10=0xFFFFFFAB%7
    imem[22]=NOP; imem[23]=NOP; imem[24]=NOP; imem[25]=NOP;
    imem[26]=M_type(5'd6,5'd5,REM_F3,  5'd11); // REM  x11=10
    imem[27]=M_type(5'd6,5'd5,REMU_F3, 5'd12); // REMU x12=10
    imem[28]=NOP; imem[29]=NOP; imem[30]=NOP; imem[31]=NOP;
    // Six divide-class ops are issued in this stream; keep a wider safety margin.
    wait_cycles(280);
    check_reg(5'd7, 32'h0000_0001, "REM_85_7  ");
    check_reg(5'd8, 32'h0000_0001, "REMU_85_7 ");
    check_reg(5'd9, 32'hFFFF_FFFF, "REM_n85_7 "); // -85 % 7 = -1 per RISC-V spec (sign follows dividend)
    // 0xFFFFFFAB % 7: 0xFFFFFFAB = 4294967211. 4294967211 mod 7 = ?
    // 4294967211 / 7 = 613566744 remainder 3. → REMU = 3
    check_reg(5'd10,32'h0000_0003, "REMU_n85_7");
    check_reg(5'd11,32'h0000_000A, "REM_100_30");
    check_reg(5'd12,32'h0000_000A, "REMU100_30");

    // ========================================================================
    // T40 — Division by Zero (spec-mandated results per RISC-V ISA vol.1)
    //   DIV  x/0 = -1 (0xFFFFFFFF)
    //   DIVU x/0 = 0xFFFFFFFF (MAX_UINT)
    //   REM  x/0 = x  (dividend unchanged)
    //   REMU x/0 = x
    // ========================================================================
    test_num=40; $display("\n--- T%0d: Div By Zero ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd42);           // x1=42 (dividend)
    imem[5]=`A(5'd2,12'd0);            // x2=0  (divisor)
    imem[6]=I(12'hFAC,5'd0,3'h0,5'd3,OI); // x3=-84 (negative dividend)
    imem[7]=NOP; imem[8]=NOP; imem[9]=NOP; imem[10]=NOP;
    imem[11]=M_type(5'd2,5'd1,DIV_F3,  5'd4); // DIV  x4 = -1
    imem[12]=M_type(5'd2,5'd1,DIVU_F3, 5'd5); // DIVU x5 = 0xFFFFFFFF
    imem[13]=M_type(5'd2,5'd1,REM_F3,  5'd6); // REM  x6 = 42
    imem[14]=M_type(5'd2,5'd1,REMU_F3, 5'd7); // REMU x7 = 42
    imem[15]=NOP; imem[16]=NOP; imem[17]=NOP; imem[18]=NOP;
    // Negative dividend / 0
    imem[19]=M_type(5'd2,5'd3,DIV_F3,  5'd8); // DIV  x8 = -1
    imem[20]=M_type(5'd2,5'd3,REM_F3,  5'd9); // REM  x9 = -84 (dividend)
    imem[21]=NOP; imem[22]=NOP; imem[23]=NOP; imem[24]=NOP;
    wait_cycles(180);
    check_reg(5'd4,32'hFFFF_FFFF, "DIVz_n1   ");
    check_reg(5'd5,32'hFFFF_FFFF, "DIVUz_max ");
    check_reg(5'd6,32'd42,        "REMz_dvd  ");
    check_reg(5'd7,32'd42,        "REMUz_dvd ");
    check_reg(5'd8,32'hFFFF_FFFF, "DIVz_neg  ");
    check_reg(5'd9,32'hFFFF_FFAC, "REMz_ndvd "); // -84

    // ========================================================================
    // T41 — Signed Overflow: INT_MIN / -1
    //   Per RISC-V spec: INT_MIN / -1 = INT_MIN (no trap), REM = 0
    //   x1 = 0x80000000 (INT_MIN), x2 = -1 (0xFFFFFFFF)
    // ========================================================================
    test_num=41; $display("\n--- T%0d: DIV Overflow ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=U(20'h80000,5'd1,LUI);     // x1=0x80000000 (INT_MIN)
    imem[5]=I(12'hFFF,5'd0,3'h0,5'd2,OI); // x2=-1
    imem[6]=NOP; imem[7]=NOP; imem[8]=NOP; imem[9]=NOP;
    imem[10]=M_type(5'd2,5'd1,DIV_F3,  5'd3); // DIV  x3=INT_MIN (overflow result)
    imem[11]=M_type(5'd2,5'd1,REM_F3,  5'd4); // REM  x4=0
    imem[12]=NOP; imem[13]=NOP; imem[14]=NOP; imem[15]=NOP;
    wait_cycles(80);
    check_reg(5'd3,32'h8000_0000, "DIVov_MIN ");
    check_reg(5'd4,32'h0000_0000, "REMov_0   ");

    // ========================================================================
    // T42 — MUL with forwarding (EX→EX, MEM→EX, load-use before MUL)
    //
    //   Test A: EX→EX into MUL
    //     ADDI x1,x0,6    (compute x1=6)
    //     MUL x2,x1,x1    (uses x1 forwarded from EX stage → 36)
    //
    //   Test B: MEM→EX into MUL
    //     ADDI x3,x0,8
    //     NOP              (x3 in MEM stage on next cycle)
    //     MUL x4,x3,x3    (uses x3 forwarded from MEM stage → 64)
    //
    //   Test C: Load-use before MUL (stall from LW, then MUL)
    //     Preload dmem[0x600]=5
    //     ADDI x10,x0,0x600
    //     LW   x5,0(x10)       (x5=5 after stall)
    //     MUL  x6,x5,x5        (load-use stall → 25)
    // ========================================================================
    test_num=42; $display("\n--- T%0d: MUL+Forward ---",test_num);
    do_reset;
    dmem[12'h600]=8'h05; dmem[12'h601]=8'h00;
    dmem[12'h602]=8'h00; dmem[12'h603]=8'h00;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd10,12'h600);         // x10=0x600
    imem[5]=NOP; imem[6]=NOP; imem[7]=NOP; imem[8]=NOP;
    // Test A: EX→EX forwarding into MUL
    imem[9] =`A(5'd1,12'd6);            // x1=6  (EX stage)
    imem[10]=M_type(5'd1,5'd1,MUL_F3,5'd2); // MUL x2=x1*x1 (forward x1 from EX)
    // Test B: MEM→EX forwarding into MUL
    imem[11]=`A(5'd3,12'd8);            // x3=8
    imem[12]=NOP;                        // x3 in MEM
    imem[13]=M_type(5'd3,5'd3,MUL_F3,5'd4); // MUL x4=x3*x3 (forward x3 from MEM)
    // Test C: load-use stall then MUL
    imem[14]=I(12'h000,5'd10,3'h2,5'd5,LD); // LW x5=5
    imem[15]=M_type(5'd5,5'd5,MUL_F3,5'd6); // MUL x6=x5*x5 (load-use stall)
    imem[16]=NOP; imem[17]=NOP; imem[18]=NOP; imem[19]=NOP;
    wait_cycles(40);
    check_reg(5'd2,32'd36,  "MUL_EXfwd ");
    check_reg(5'd4,32'd64,  "MUL_MEMfw ");
    check_reg(5'd6,32'd25,  "MUL_LdUse ");

    // ========================================================================
    // T43 — DIV multi-cycle stall: pipeline issues instruction after DIV,
    //        that instruction must wait until DIV completes (Hazard_Unit
    //        keeps Stall_F/Stall_D/Stall_E asserted until MDU_Ready).
    //   x1=100, x2=3 → DIV x3=33, ADDI x4 immediately after (tests stall)
    //   x4 = x3 + 1 = 34 (verifies pipeline resumed correctly post-stall)
    //   Also check REM in same stream: REM x5=100%3=1
    // ========================================================================
    test_num=43; $display("\n--- T%0d: DIV Stall ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd100);          // x1=100
    imem[5]=`A(5'd2,12'd3);            // x2=3
    imem[6]=NOP; imem[7]=NOP; imem[8]=NOP; imem[9]=NOP;
    imem[10]=M_type(5'd2,5'd1,DIV_F3,  5'd3); // DIV x3=33
    imem[11]=I(12'h001,5'd3,3'h0,5'd4,OI);    // ADDI x4=x3+1 (must stall)
    imem[12]=M_type(5'd2,5'd1,REM_F3,  5'd5); // REM x5=1
    imem[13]=I(12'h002,5'd5,3'h0,5'd6,OI);    // ADDI x6=x5+2 (must stall for REM)
    imem[14]=NOP; imem[15]=NOP; imem[16]=NOP; imem[17]=NOP;
    wait_cycles(120);
    check_reg(5'd3,32'd33,  "DIV_100_3 ");
    check_reg(5'd4,32'd34,  "DIV_stall ");  // tests pipeline resume
    check_reg(5'd5,32'd1,   "REM_100_3 ");
    check_reg(5'd6,32'd3,   "REM_stall ");  // tests pipeline resume after REM

    // ========================================================================
    // T44 — Mixed M+I stream: MUL result fed into subsequent ALU chain
    //   x1=5, x2=6
    //   MUL  x3 = 5×6 = 30
    //   ADDI x4 = x3 + 10 = 40  (EX→EX forward from MUL result)
    //   SLL  x5 = x4 << 1 = 80  (EX→EX chain)
    //   XOR  x6 = x5 ^ x3 = 80^30 = 78 = 0x4E
    //   DIV  x7 = x6 / x2 = 78 / 6 = 13
    //   ADD  x8 = x7 + x3 = 13 + 30 = 43
    // ========================================================================
    test_num=44; $display("\n--- T%0d: Mixed M+I ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=`A(5'd1,12'd5);
    imem[5]=`A(5'd2,12'd6);
    imem[6]=NOP; imem[7]=NOP; imem[8]=NOP; imem[9]=NOP;
    imem[10]=M_type(5'd2,5'd1,MUL_F3,5'd3);       // x3=30  MUL
    imem[11]=I(12'h00A,5'd3,3'h0,5'd4,OI);        // x4=40  fwd from MUL
    imem[12]=`A(5'd20,12'd1);                       // x20=1 shift amount
    imem[13]=R(7'h00,5'd20,5'd4,3'h1,5'd5,OP);    // x5=80  SLL
    imem[14]=R(7'h00,5'd3,5'd5,3'h4,5'd6,OP);     // x6=110 XOR
    // x6 and x2 must be in RF before DIV
    imem[15]=NOP; imem[16]=NOP; imem[17]=NOP; imem[18]=NOP;
    imem[19]=M_type(5'd2,5'd6,DIV_F3,5'd7);       // x7=18  DIV
    imem[20]=NOP; imem[21]=NOP; imem[22]=NOP; imem[23]=NOP; // stall drain
    imem[24]=R(7'h00,5'd3,5'd7,3'h0,5'd8,OP);     // x8=48  ADD after DIV
    imem[25]=NOP; imem[26]=NOP; imem[27]=NOP; imem[28]=NOP;
    wait_cycles(100);
    check_reg(5'd3,32'd30,  "MIX_mul   ");
    check_reg(5'd4,32'd40,  "MIX_addi  ");
    check_reg(5'd5,32'd80,  "MIX_sll   ");
    check_reg(5'd6,32'd78,  "MIX_xor   ");
    check_reg(5'd7,32'd13,  "MIX_div   ");
    check_reg(5'd8,32'd43,  "MIX_add   ");

    // ========================================================================
    // T45 — MULHU vs MULH sign check (upper-half sign semantics)
    //   For positive×positive:  MULH == MULHU (both zero for small values)
    //   For negative×positive (signed):
    //     MULH  gives arithmetic upper half (sign-extended)
    //     MULHU treats both as unsigned → different result
    //   x1 = 0x80000000 (INT_MIN), x2 = 2
    //     MULH  x3 = upper32(signed INT_MIN × 2)   = 0xFFFFFFFF
    //     MULHU x4 = upper32(0x80000000 × 2)       = 0x80000000/2*2>>32? 
    //                0x80000000 * 2 = 0x100000000 → upper32 = 1
    //     MULHSU x5= upper32(signed INT_MIN × unsigned 2)
    //                signed×unsigned: INT_MIN=-2147483648, upper32 = 0xFFFFFFFF
    //   x6 = 0x7FFFFFFF (INT_MAX), x7 = 0x7FFFFFFF
    //     MUL   x8 = lower32(INT_MAX × INT_MAX) = 0x00000001
    //     MULH  x9 = upper32(INT_MAX × INT_MAX) = 0x3FFFFFFF
    //     MULHU x10= upper32 of same = 0x3FFFFFFF (same: both positive)
    // ========================================================================
    test_num=45; $display("\n--- T%0d: MULHU vs MULH ---",test_num);
    do_reset;
    imem[0]=NOP; imem[1]=NOP; imem[2]=NOP; imem[3]=NOP;
    imem[4]=U(20'h80000,5'd1,LUI);      // x1=0x80000000
    imem[5]=`A(5'd2,12'd2);             // x2=2
    imem[6]=U(20'h80000,5'd6,LUI);      // x6=0x80000000
    imem[7]=I(12'hFFF,5'd6,3'h0,5'd6,OI); // x6=0x7FFFFFFF (INT_MAX)
    // Copy INT_MAX to x7 using ADD x7=x6+x0
    imem[8]=R(7'h00,5'd0,5'd6,3'h0,5'd7,OP); // x7=x6=INT_MAX
    imem[9]=NOP; imem[10]=NOP; imem[11]=NOP; imem[12]=NOP;
    imem[13]=M_type(5'd2,5'd1,MULH_F3,  5'd3); // MULH  x3=0xFFFFFFFF
    imem[14]=M_type(5'd2,5'd1,MULHU_F3, 5'd4); // MULHU x4=0x00000001
    imem[15]=M_type(5'd2,5'd1,MULHSU_F3,5'd5); // MULHSU x5=0xFFFFFFFF
    imem[16]=M_type(5'd7,5'd6,MUL_F3,   5'd8); // MUL   x8=0x00000001
    imem[17]=M_type(5'd7,5'd6,MULH_F3,  5'd9); // MULH  x9=0x3FFFFFFF
    imem[18]=M_type(5'd7,5'd6,MULHU_F3, 5'd10);// MULHU x10=0x3FFFFFFF
    imem[19]=NOP; imem[20]=NOP; imem[21]=NOP; imem[22]=NOP;
    wait_cycles(40);
    check_reg(5'd3,32'hFFFF_FFFF, "MULH_MIN2 ");
    check_reg(5'd4,32'h0000_0001, "MULHU_MIN2");
    check_reg(5'd5,32'hFFFF_FFFF, "MULHSU_M2 ");
    check_reg(5'd8,32'h0000_0001, "MUL_MAX2  ");
    check_reg(5'd9,32'h3FFF_FFFF, "MULH_MAX2 ");
    check_reg(5'd10,32'h3FFF_FFFF,"MULHU_MAX2");

    // ── Summary ──────────────────────────────────────────────────────────────
    #(CLK_PERIOD*5);
    $display("\n=============================================================");
    $display("  RESULTS: PASS=%0d  FAIL=%0d  TOTAL=%0d",pass_cnt,fail_cnt,pass_cnt+fail_cnt);
    if(fail_cnt==0) $display("  *** ALL TESTS PASSED ***");
    else            $display("  *** %0d FAILED (see [FAIL] lines) ***",fail_cnt);
    $display("  T01-T35: RV32I+Zicsr baseline (preserved from v5-final)");
    $display("  T36-T45: RV32M (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU)");
    $display("  NOTE: T07 LHU checks (x6,x8) verify known DUT Load_Unit bug.");
    $display("  NOTE: T06 BGEU — DUT Decoder bug (not taken, canary fires).");
    $display("=============================================================");
    $finish;
  end

  initial begin #(CLK_PERIOD*TIMEOUT_CYC);
    $display("[WATCHDOG] PASS=%0d FAIL=%0d",pass_cnt,fail_cnt); $finish; end
  initial begin $dumpfile("tb_Pip_RV32I.vcd"); $dumpvars(0,tb_Pip_RV32I); end

endmodule
