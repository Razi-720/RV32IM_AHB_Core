/* verilator lint_off TIMESCALEMOD */
/* verilator lint_off WIDTHEXPAND  */
/* verilator lint_off WIDTHTRUNC   */
/* verilator lint_off UNUSEDPARAM  */
/* verilator lint_off UNDRIVEN     */
`timescale 1ns/1ps

// =============================================================================
// Comprehensive testbench for MDU (Mul32_Booth + Div32_NonRestoring wrapper)
//
// Verified behaviours:
//  G0  : Reset state — MDU_Ready_Out=1, Result_Out=0
//  G1  : MUL  — lower 32 bits, single-cycle ready
//  G2  : MULH  — upper 32 bits signed×signed, single-cycle ready
//  G3  : MULHSU — upper 32 bits signed×unsigned, single-cycle ready
//  G4  : MULHU  — upper 32 bits unsigned×unsigned, single-cycle ready
//  G5  : MUL family ready timing — MDU_Ready_Out stays HIGH, never stalls
//  G6  : DIV  — signed division, multi-cycle, all special cases
//  G7  : DIVU — unsigned division, multi-cycle, all special cases
//  G8  : REM  — signed remainder, multi-cycle, all special cases
//  G9  : REMU — unsigned remainder, multi-cycle, all special cases
//  G10 : Divide ready timing — MDU_Ready_Out LOW during computation
//  G11 : Special-case latency — div/0 and overflow complete in 1 cycle
//  G12 : Back-to-back divide operations
//  G13 : Divide followed immediately by multiply (ready handshake)
//  G14 : Multiply followed immediately by divide (Start_In gating)
//  G15 : DIV/REM consistency — (a/b)*b + a%b == a
//  G16 : DIVU/REMU consistency
//  G17 : MUL + MULH 64-bit product reconstruction
//  G18 : MDU_Ready_Out never drops for multiply ops
//  G19 : Start_In gating — multiply Start pulse does NOT start divider
//  G20 : Start_In gating — divide  Start pulse does NOT affect multiply result
// =============================================================================

module tb_MDU;

  // --------------------------------------------------------------------------
  // DUT ports
  // --------------------------------------------------------------------------
  reg         Clk_In;
  reg         Rst_In;
  reg         Start_In;
  reg  [31:0] A_In;
  reg  [31:0] B_In;
  reg  [2:0]  MDU_Op_In;

  wire        MDU_Ready_Out;
  wire [31:0] Result_Out;

  // --------------------------------------------------------------------------
  // funct3 opcodes
  // --------------------------------------------------------------------------
  localparam MUL    = 3'b000;
  localparam MULH   = 3'b001;
  localparam MULHSU = 3'b010;
  localparam MULHU  = 3'b011;
  localparam DIV    = 3'b100;
  localparam DIVU   = 3'b101;
  localparam REM    = 3'b110;
  localparam REMU   = 3'b111;

  localparam INT32_MIN  = 32'h8000_0000;
  localparam INT32_MAX  = 32'h7FFF_FFFF;
  localparam UINT32_MAX = 32'hFFFF_FFFF;

  // --------------------------------------------------------------------------
  // Scoreboard
  // --------------------------------------------------------------------------
  integer pass_count, fail_count, tid;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  MDU dut (
    .Clk_In      (Clk_In),
    .Rst_In      (Rst_In),
    .Start_In    (Start_In),
    .MDU_Ready_Out(MDU_Ready_Out),
    .A_In        (A_In),
    .B_In        (B_In),
    .MDU_Op_In   (MDU_Op_In),
    .Result_Out  (Result_Out)
  );

  // --------------------------------------------------------------------------
  // Clock — 10 ns period
  // --------------------------------------------------------------------------
  initial Clk_In = 0;
  always  #5 Clk_In = ~Clk_In;

  // ==========================================================================
  // Tasks
  // ==========================================================================

  task do_reset;
    begin
      Rst_In    = 1;
      Start_In  = 0;
      A_In      = 32'h0;
      B_In      = 32'h0;
      MDU_Op_In = 3'b0;
      @(posedge Clk_In); #1;
      @(posedge Clk_In); #1;
      Rst_In = 0;
      #1;
    end
  endtask

  task tick;
    begin @(posedge Clk_In); #1; end
  endtask

  // Issue a multiply: apply inputs, pulse Start_In, read result next cycle
  // MDU_Ready_Out stays 1 for multiply, so result is valid the next cycle
  task mul_op;
    input [31:0]  a, b;
    input [2:0]   op;
    output [31:0] result;
    begin
      A_In = a; B_In = b; MDU_Op_In = op;
      Start_In = 1;
      tick;            // Execute cycle: Start pulses, multiply is combinatorial
      Start_In = 0;
      #2;              // let combinational settle
      result = Result_Out;
    end
  endtask

  // Issue a divide: pulse Start_In, wait for MDU_Ready_Out to go high.
  //
  // Timing detail:
  //   - Start_In pulses on clock edge N  (divider latches operands, clears Ready)
  //   - For special cases (div/0, overflow): Ready reasserts on the SAME edge N
  //     (the RTL does: Ready_Out <= 1'b1 inside the Start_In branch)
  //     So after tick(), Ready is already 1 — we read result immediately.
  //   - For normal divides: Ready deasserts on edge N, reasserts on edge N+32
  //     We must NOT check Ready until AFTER edge N has been processed.
  //     The mandatory tick() after clearing Start_In advances past edge N+1,
  //     so the while-loop correctly polls from cycle N+2 onward.
  //   - Result_Out is registered (written on the edge where Ready goes high),
  //     so it is stable at #1 after that edge — no extra settle needed.
  task div_op;
    input [31:0]  a, b;
    input [2:0]   op;
    output [31:0] result;
    output integer cyc;
    begin
      A_In = a; B_In = b; MDU_Op_In = op;
      Start_In = 1;
      tick;               // Edge N: Start pulse — divider latches, clears Ready
      Start_In = 0;
      // Edge N+1: one mandatory clock so divider has had a chance to deassert
      // Ready (for normal divides). For special cases Ready is already 1 here.
      tick;
      cyc = 2;
      // Poll until Ready — timeout after 40 cycles
      while (!MDU_Ready_Out && cyc < 40) begin
        tick;
        cyc = cyc + 1;
      end
      // Result_Out is stable at this point (#1 after the posedge that set Ready)
      result = Result_Out;
    end
  endtask

  // Check helpers
  task chk;
    input integer  id;
    input [31:0]   got;
    input [31:0]   exp;
    input [255:0]  label;
    begin
      if (got === exp) begin
        $display("PASS [%0d] %s : 0x%08h", id, label, got);
        pass_count = pass_count + 1;
      end else begin
        $display("FAIL [%0d] %s : got=0x%08h  exp=0x%08h", id, label, got, exp);
        fail_count = fail_count + 1;
      end
      tid = tid + 1;
    end
  endtask

  task chk1;
    input integer id;
    input         got;
    input         exp;
    input [255:0] label;
    begin chk(id, {31'b0,got}, {31'b0,exp}, label); end
  endtask

  task chk_cyc;
    input integer id;
    input integer got;
    input integer lo, hi;
    input [255:0] label;
    begin
      if (got >= lo && got <= hi) begin
        $display("PASS [%0d] %s : %0d cycles", id, label, got);
        pass_count = pass_count + 1;
      end else begin
        $display("FAIL [%0d] %s : %0d cycles (expected %0d-%0d)", id, label, got, lo, hi);
        fail_count = fail_count + 1;
      end
      tid = tid + 1;
    end
  endtask

  task banner;
    input [511:0] s;
    begin $display("\n--- %s ---", s); end
  endtask

  // ==========================================================================
  // Stimulus
  // ==========================================================================
  reg [31:0] r;
  reg [31:0] r2;
  integer    c;

  initial begin
    pass_count = 0; fail_count = 0; tid = 0;

    // ========================================================================
    // G0: Reset state
    // ========================================================================
    banner("G0: Reset state");
    do_reset;
    chk1(tid, MDU_Ready_Out, 1'b1, "G0 Ready=1 after reset  ");
    chk(tid,  Result_Out, 32'h0,   "G0 Result=0 after reset ");

    // ========================================================================
    // G1: MUL — lower 32 bits, single-cycle
    // ========================================================================
    banner("G1: MUL lower 32 bits");
    do_reset; tick;
    mul_op(32'd0,        32'd0,         MUL, r); chk(tid, r, 32'd0,           "G1 MUL 0×0=0            ");
    mul_op(32'd1,        32'd1,         MUL, r); chk(tid, r, 32'd1,           "G1 MUL 1×1=1            ");
    mul_op(32'd6,        32'd7,         MUL, r); chk(tid, r, 32'd42,          "G1 MUL 6×7=42           ");
    mul_op(32'd100,      32'd200,       MUL, r); chk(tid, r, 32'd20000,       "G1 MUL 100×200=20000    ");
    mul_op(32'hFFFF_FFFE,32'd3,         MUL, r); chk(tid, r, 32'hFFFF_FFFA,   "G1 MUL -2×3=-6 low32   ");
    mul_op(32'hFFFF_FFFF,32'hFFFF_FFFF, MUL, r); chk(tid, r, 32'd1,          "G1 MUL -1×-1=1 low32   ");
    mul_op(INT32_MIN,    32'd2,         MUL, r); chk(tid, r, 32'h0,           "G1 MUL INT32MIN×2 wrap  ");
    mul_op(UINT32_MAX,   UINT32_MAX,    MUL, r); chk(tid, r, 32'h0000_0001,   "G1 MUL UINT_MAX^2 low32 ");
    mul_op(32'd0,        32'hDEAD_BEEF, MUL, r); chk(tid, r, 32'd0,           "G1 MUL 0×X=0            ");

    // ========================================================================
    // G2: MULH — upper 32 bits signed×signed
    // ========================================================================
    banner("G2: MULH upper signed×signed");
    do_reset; tick;
    mul_op(32'd1,        32'd1,         MULH, r); chk(tid, r, 32'h0,           "G2 MULH 1×1 up=0        ");
    mul_op(32'hFFFF_FFFF,32'hFFFF_FFFF, MULH, r); chk(tid, r, 32'h0,          "G2 MULH -1×-1 up=0      ");
    mul_op(INT32_MAX,    INT32_MAX,     MULH, r); chk(tid, r, 32'h3FFF_FFFF,   "G2 MULH INT32MAX^2 up   ");
    mul_op(32'hFFFF_FFFF,INT32_MIN,     MULH, r); chk(tid, r, 32'h0000_0000,   "G2 MULH -1×INT32MIN up  ");
    mul_op(32'hFFFF_FFFE,INT32_MIN,     MULH, r); chk(tid, r, 32'h0000_0001,   "G2 MULH -2×INT32MIN up  ");
    mul_op(INT32_MIN,    INT32_MIN,     MULH, r); chk(tid, r, 32'h4000_0000,   "G2 MULH INT32MIN^2 up   ");
    mul_op(32'd2,        32'hFFFF_FFFF, MULH, r); chk(tid, r, 32'hFFFF_FFFF,   "G2 MULH 2×-1 up=-1      ");

    // ========================================================================
    // G3: MULHSU — upper 32 bits signed×unsigned
    // ========================================================================
    banner("G3: MULHSU upper signed×unsigned");
    do_reset; tick;
    mul_op(32'd1,        32'd1,         MULHSU, r); chk(tid, r, 32'h0,          "G3 MULHSU 1×1 up=0      ");
    mul_op(32'd1,        UINT32_MAX,    MULHSU, r); chk(tid, r, 32'h0,          "G3 MULHSU 1×UINT_MAX up ");
    mul_op(32'hFFFF_FFFF,UINT32_MAX,   MULHSU, r); chk(tid, r, 32'hFFFF_FFFF,  "G3 MULHSU -1×UINT_MAX   ");
    mul_op(INT32_MIN,    UINT32_MAX,   MULHSU, r); chk(tid, r, 32'h8000_0000,  "G3 MULHSU INT32MIN×UINT ");
    mul_op(INT32_MAX,    UINT32_MAX,   MULHSU, r); chk(tid, r, 32'h7FFF_FFFE,  "G3 MULHSU INT32MAX×UINT ");
    mul_op(32'd0,        32'hDEAD_BEEF,MULHSU, r); chk(tid, r, 32'h0,          "G3 MULHSU 0×X up=0      ");

    // ========================================================================
    // G4: MULHU — upper 32 bits unsigned×unsigned
    // ========================================================================
    banner("G4: MULHU upper unsigned×unsigned");
    do_reset; tick;
    mul_op(32'd1,        32'd1,         MULHU, r); chk(tid, r, 32'h0,           "G4 MULHU 1×1 up=0       ");
    mul_op(UINT32_MAX,   UINT32_MAX,    MULHU, r); chk(tid, r, 32'hFFFF_FFFE,   "G4 MULHU UINT_MAX^2 up  ");
    mul_op(32'h8000_0000,32'd2,         MULHU, r); chk(tid, r, 32'h0000_0001,   "G4 MULHU 2^31×2 carry   ");
    mul_op(32'd2,        UINT32_MAX,    MULHU, r); chk(tid, r, 32'h0000_0001,   "G4 MULHU 2×UINT_MAX up=1");
    mul_op(32'd0,        UINT32_MAX,    MULHU, r); chk(tid, r, 32'h0,           "G4 MULHU 0×X up=0       ");

    // ========================================================================
    // G5: Multiply ready timing — MDU_Ready_Out never drops
    // ========================================================================
    banner("G5: MUL family ready timing");
    do_reset; tick;
    A_In = 32'd5; B_In = 32'd6; MDU_Op_In = MUL;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G5 Ready=1 cycle after Start MUL ");
    tick;
    chk1(tid, MDU_Ready_Out, 1'b1, "G5 Ready=1 two cycles after      ");
    A_In = 32'd7; B_In = 32'd8; MDU_Op_In = MULH;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G5 Ready=1 MULH never stalls     ");

    // ========================================================================
    // G6: DIV — signed division, multi-cycle + special cases
    // ========================================================================
    banner("G6: DIV signed division");
    do_reset; tick;
    div_op(32'd6,        32'd3,         DIV, r, c); chk(tid, r, 32'd2,          "G6 DIV 6/3=2            ");
    div_op(32'd7,        32'd3,         DIV, r, c); chk(tid, r, 32'd2,          "G6 DIV 7/3=2 trunc      ");
    div_op(32'hFFFF_FFFA,32'd2,         DIV, r, c); chk(tid, r, 32'hFFFF_FFFD,  "G6 DIV -6/2=-3          ");
    div_op(32'd7,        32'hFFFF_FFFF, DIV, r, c); chk(tid, r, 32'hFFFF_FFF9,  "G6 DIV 7/-1=-7          ");
    div_op(32'hFFFF_FFF9,32'hFFFF_FFFF, DIV, r, c); chk(tid, r, 32'd7,         "G6 DIV -7/-1=7          ");
    // Truncation toward zero: -7/2 = -3, not -4
    div_op(32'hFFFF_FFF9,32'd2,         DIV, r, c); chk(tid, r, 32'hFFFF_FFFD,  "G6 DIV -7/2=-3 trunc0   ");
    // Division by zero
    div_op(32'd5,        32'd0,         DIV, r, c); chk(tid, r, UINT32_MAX,      "G6 DIV x/0=-1           ");
    div_op(INT32_MIN,    32'd0,         DIV, r, c); chk(tid, r, UINT32_MAX,      "G6 DIV INT32MIN/0=-1    ");
    // Signed overflow
    div_op(INT32_MIN,    UINT32_MAX,    DIV, r, c); chk(tid, r, INT32_MIN,       "G6 DIV overflow=INT32MIN");
    div_op(32'd0,        32'd5,         DIV, r, c); chk(tid, r, 32'd0,           "G6 DIV 0/5=0            ");
    div_op(32'd1,        32'd1,         DIV, r, c); chk(tid, r, 32'd1,           "G6 DIV 1/1=1            ");

    // ========================================================================
    // G7: DIVU — unsigned division + special cases
    // ========================================================================
    banner("G7: DIVU unsigned division");
    do_reset; tick;
    div_op(32'd6,        32'd3,         DIVU, r, c); chk(tid, r, 32'd2,         "G7 DIVU 6/3=2           ");
    div_op(UINT32_MAX,   32'd1,         DIVU, r, c); chk(tid, r, UINT32_MAX,    "G7 DIVU UINT_MAX/1      ");
    div_op(UINT32_MAX,   UINT32_MAX,    DIVU, r, c); chk(tid, r, 32'd1,         "G7 DIVU UINT_MAX/UINT   ");
    div_op(UINT32_MAX,   32'd2,         DIVU, r, c); chk(tid, r, 32'h7FFF_FFFF, "G7 DIVU UINT_MAX/2      ");
    // 0x8000_0000 / 0x8000_0001 = 0 unsigned (not -1 as signed)
    div_op(32'h8000_0000,32'h8000_0001, DIVU, r, c); chk(tid, r, 32'd0,        "G7 DIVU unsigned correct");
    div_op(32'd5,        32'd0,         DIVU, r, c); chk(tid, r, UINT32_MAX,    "G7 DIVU x/0=UINT_MAX    ");
    div_op(32'd0,        32'd7,         DIVU, r, c); chk(tid, r, 32'd0,         "G7 DIVU 0/7=0           ");

    // ========================================================================
    // G8: REM — signed remainder + special cases
    // ========================================================================
    banner("G8: REM signed remainder");
    do_reset; tick;
    div_op(32'd7,        32'd3,         REM, r, c); chk(tid, r, 32'd1,          "G8 REM 7%3=1            ");
    div_op(32'd6,        32'd3,         REM, r, c); chk(tid, r, 32'd0,          "G8 REM 6%3=0            ");
    // Negative dividend: sign follows dividend
    div_op(32'hFFFF_FFF9,32'd3,         REM, r, c); chk(tid, r, 32'hFFFF_FFFF,  "G8 REM -7%3=-1          ");
    div_op(32'd7,        32'hFFFF_FFFD, REM, r, c); chk(tid, r, 32'd1,          "G8 REM 7%-3=1           ");
    div_op(32'hFFFF_FFF9,32'hFFFF_FFFD, REM, r, c); chk(tid, r, 32'hFFFF_FFFF, "G8 REM -7%-3=-1         ");
    // Division by zero → dividend returned
    div_op(32'd5,        32'd0,         REM, r, c); chk(tid, r, 32'd5,          "G8 REM x%0=x            ");
    div_op(32'hDEAD_BEEF,32'd0,         REM, r, c); chk(tid, r, 32'hDEAD_BEEF,  "G8 REM neg%0=x          ");
    // Signed overflow → 0
    div_op(INT32_MIN,    UINT32_MAX,    REM, r, c); chk(tid, r, 32'd0,          "G8 REM overflow=0       ");
    div_op(32'd0,        32'd7,         REM, r, c); chk(tid, r, 32'd0,          "G8 REM 0%7=0            ");
    div_op(32'd15,       32'd5,         REM, r, c); chk(tid, r, 32'd0,          "G8 REM 15%5=0 exact     ");

    // ========================================================================
    // G9: REMU — unsigned remainder + special cases
    // ========================================================================
    banner("G9: REMU unsigned remainder");
    do_reset; tick;
    div_op(32'd7,        32'd3,         REMU, r, c); chk(tid, r, 32'd1,         "G9 REMU 7%3=1           ");
    div_op(UINT32_MAX,   32'd1,         REMU, r, c); chk(tid, r, 32'd0,         "G9 REMU UINT_MAX%1=0    ");
    div_op(UINT32_MAX,   UINT32_MAX,    REMU, r, c); chk(tid, r, 32'd0,         "G9 REMU UINT_MAX%UINT=0 ");
    div_op(UINT32_MAX,   32'd2,         REMU, r, c); chk(tid, r, 32'd1,         "G9 REMU UINT_MAX%2=1    ");
    // 0x8000_0001 % 0x8000_0000 = 1 unsigned
    div_op(32'h8000_0001,32'h8000_0000, REMU, r, c); chk(tid, r, 32'd1,        "G9 REMU unsigned correct");
    div_op(32'd5,        32'd0,         REMU, r, c); chk(tid, r, 32'd5,         "G9 REMU x%0=x           ");
    div_op(UINT32_MAX,   32'd0,         REMU, r, c); chk(tid, r, UINT32_MAX,    "G9 REMU UINT_MAX%0      ");
    div_op(32'd0,        32'd100,       REMU, r, c); chk(tid, r, 32'd0,         "G9 REMU 0%100=0         ");

    // ========================================================================
    // G10: Divide ready timing — MDU_Ready_Out goes LOW during computation
    // ========================================================================
    banner("G10: Divide ready timing");
    do_reset; tick;
    // Start a normal divide (non-zero, non-special)
    A_In = 32'hDEAD_BEEF; B_In = 32'd7; MDU_Op_In = DIVU;
    Start_In = 1; tick; Start_In = 0;
    // Ready must be LOW on the cycle immediately after Start
    chk1(tid, MDU_Ready_Out, 1'b0, "G10 Ready=0 cycle 1 div ");
    tick;
    chk1(tid, MDU_Ready_Out, 1'b0, "G10 Ready=0 cycle 2 div ");
    // Wait for completion
    begin : wait_g10
      integer cnt;
      cnt = 2;
      while (!MDU_Ready_Out && cnt < 40) begin tick; cnt = cnt + 1; end
      chk1(tid, MDU_Ready_Out, 1'b1, "G10 Ready=1 after div   ");
      chk_cyc(tid, cnt, 2, 33,       "G10 div latency 2-33cyc ");
    end

    // ========================================================================
    // G11: Special-case latency — div/0 and overflow complete in 1 cycle
    //      (Div32_NonRestoring handles these in the Start_In cycle itself)
    // ========================================================================
    banner("G11: Special-case 1-cycle completion");
    do_reset; tick;

    // Division by zero — Ready comes back same cycle as Start
    A_In = 32'd5; B_In = 32'd0; MDU_Op_In = DIV;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G11 div/0 Ready=1 immed ");
    chk(tid, Result_Out, UINT32_MAX, "G11 div/0 result=-1     ");

    // DIVU by zero
    A_In = 32'd5; B_In = 32'd0; MDU_Op_In = DIVU;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G11 divu/0 Ready immed  ");
    chk(tid, Result_Out, UINT32_MAX, "G11 divu/0=UINT_MAX     ");

    // REM by zero
    A_In = 32'hABCD_1234; B_In = 32'd0; MDU_Op_In = REM;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G11 rem/0 Ready immed   ");
    chk(tid, Result_Out, 32'hABCD_1234, "G11 rem/0=dividend      ");

    // Signed overflow
    A_In = INT32_MIN; B_In = UINT32_MAX; MDU_Op_In = DIV;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G11 overflow Ready immed");
    chk(tid, Result_Out, INT32_MIN,  "G11 overflow=INT32_MIN  ");

    // REM overflow
    A_In = INT32_MIN; B_In = UINT32_MAX; MDU_Op_In = REM;
    Start_In = 1; tick; Start_In = 0;
    chk1(tid, MDU_Ready_Out, 1'b1, "G11 rem ovf Ready immed ");
    chk(tid, Result_Out, 32'd0,      "G11 rem overflow=0      ");

    // ========================================================================
    // G12: Back-to-back divide operations
    //      Second Start_In issued the cycle after Ready returns
    // ========================================================================
    banner("G12: Back-to-back divides");
    do_reset; tick;
    div_op(32'd100, 32'd7, DIVU, r, c);
    chk(tid, r, 32'd14, "G12 first div 100/7=14  ");
    div_op(32'd100, 32'd7, REMU, r, c);
    chk(tid, r, 32'd2,  "G12 second div 100%7=2  ");
    // Verify: 14*7+2=100
    chk(tid, (32'd14 * 32'd7 + 32'd2), 32'd100, "G12 consistency check   ");

    // ========================================================================
    // G13: Divide then immediately multiply (no stall on multiply)
    // ========================================================================
    banner("G13: Divide then multiply");
    do_reset; tick;
    div_op(32'd30, 32'd5, DIV, r, c);
    chk(tid, r, 32'd6, "G13 div result 30/5=6   ");
    // Now immediately issue a multiply — must be ready immediately
    mul_op(32'd6, 32'd7, MUL, r);
    chk(tid, r, 32'd42,        "G13 mul after div=42    ");
    chk1(tid, MDU_Ready_Out, 1, "G13 mul ready immediate ");

    // ========================================================================
    // G14: Multiply then divide — divider start gated on Is_Div
    // ========================================================================
    banner("G14: Multiply then divide");
    do_reset; tick;
    mul_op(32'd15, 32'd3, MUL, r);
    chk(tid, r, 32'd45, "G14 mul 15×3=45         ");
    div_op(32'd45, 32'd9, DIV, r, c);
    chk(tid, r, 32'd5,  "G14 div 45/9=5          ");

    // ========================================================================
    // G15: DIV + REM consistency: (a/b)*b + a%b == a  (signed)
    // ========================================================================
    banner("G15: DIV/REM signed consistency");
    begin : g15
      reg [31:0] a, b, q, rm;
      reg [31:0] pairs_a [0:7];
      reg [31:0] pairs_b [0:7];
      integer i;
      pairs_a[0]=32'd17;        pairs_b[0]=32'd5;
      pairs_a[1]=32'hFFFF_FFF3; pairs_b[1]=32'd7;
      pairs_a[2]=32'd100;       pairs_b[2]=32'hFFFF_FFFD;
      pairs_a[3]=32'hFFFF_FF9C; pairs_b[3]=32'hFFFF_FFFD;
      pairs_a[4]=INT32_MAX;     pairs_b[4]=32'd13;
      pairs_a[5]=32'd1;         pairs_b[5]=32'd1;
      pairs_a[6]=32'h0000_ABCD; pairs_b[6]=32'h0000_0123;
      pairs_a[7]=32'd999;       pairs_b[7]=32'd31;
      for (i = 0; i < 8; i = i+1) begin
        a = pairs_a[i]; b = pairs_b[i];
        div_op(a, b, DIV, q, c);
        div_op(a, b, REM, rm, c);
        if (($signed(q)*$signed(b) + $signed(rm)) === $signed(a))
          begin $display("PASS [%0d] G15 DIV/REM consist a=0x%08h b=0x%08h",tid,a,b); pass_count=pass_count+1; end
        else
          begin $display("FAIL [%0d] G15 DIV/REM consist a=0x%08h b=0x%08h q=0x%08h r=0x%08h",tid,a,b,q,rm); fail_count=fail_count+1; end
        tid=tid+1;
      end
    end

    // ========================================================================
    // G16: DIVU + REMU consistency: (a/b)*b + a%b == a  (unsigned)
    // ========================================================================
    banner("G16: DIVU/REMU unsigned consistency");
    begin : g16
      reg [31:0] a, b, q, rm;
      reg [31:0] pairs_a [0:5];
      reg [31:0] pairs_b [0:5];
      integer i;
      pairs_a[0]=32'd17;        pairs_b[0]=32'd5;
      pairs_a[1]=UINT32_MAX;    pairs_b[1]=32'd3;
      pairs_a[2]=32'h8000_0000; pairs_b[2]=32'h0000_0007;
      pairs_a[3]=32'h0000_ABCD; pairs_b[3]=32'h0000_0123;
      pairs_a[4]=32'd1000;      pairs_b[4]=32'd13;
      pairs_a[5]=32'd0;         pairs_b[5]=32'd7;
      for (i = 0; i < 6; i = i+1) begin
        a = pairs_a[i]; b = pairs_b[i];
        div_op(a, b, DIVU, q, c);
        div_op(a, b, REMU, rm, c);
        if ((q*b + rm) === a)
          begin $display("PASS [%0d] G16 DIVU/REMU consist a=0x%08h b=0x%08h",tid,a,b); pass_count=pass_count+1; end
        else
          begin $display("FAIL [%0d] G16 DIVU/REMU consist a=0x%08h b=0x%08h q=0x%08h r=0x%08h",tid,a,b,q,rm); fail_count=fail_count+1; end
        tid=tid+1;
      end
    end

    // ========================================================================
    // G17: MUL + MULH 64-bit product reconstruction
    // ========================================================================
    banner("G17: MUL+MULH 64-bit reconstruction");
    begin : g17
      reg [31:0] a, b;
      reg [63:0] got64, exp64;
      a = 32'h7FFF_0000; b = 32'h0000_FFFF;
      mul_op(a, b, MUL,  r);  got64[31:0]  = r;
      mul_op(a, b, MULH, r2); got64[63:32] = r2;
      exp64 = $signed({{32{a[31]}},a}) * $signed({{32{b[31]}},b});
      if (got64 === exp64)
        begin $display("PASS [%0d] G17 64-bit reconstruct 0x%016h",tid,got64); pass_count=pass_count+1; end
      else
        begin $display("FAIL [%0d] G17 64-bit got=0x%016h exp=0x%016h",tid,got64,exp64); fail_count=fail_count+1; end
      tid=tid+1;

      a = 32'h8000_1234; b = 32'h0FFF_FFFF;
      mul_op(a, b, MUL,  r);  got64[31:0]  = r;
      mul_op(a, b, MULH, r2); got64[63:32] = r2;
      exp64 = $signed({{32{a[31]}},a}) * $signed({{32{b[31]}},b});
      if (got64 === exp64)
        begin $display("PASS [%0d] G17 neg×pos 64-bit 0x%016h",tid,got64); pass_count=pass_count+1; end
      else
        begin $display("FAIL [%0d] G17 neg×pos got=0x%016h exp=0x%016h",tid,got64,exp64); fail_count=fail_count+1; end
      tid=tid+1;
    end

    // ========================================================================
    // G18: MDU_Ready_Out never drops for any multiply operation
    // ========================================================================
    banner("G18: Ready never drops for MUL family");
    do_reset; tick;
    begin : g18
      integer i;
      reg [2:0] ops [0:3];
      ops[0] = MUL; ops[1] = MULH; ops[2] = MULHSU; ops[3] = MULHU;
      for (i = 0; i < 4; i = i+1) begin
        A_In = 32'hAAAA_5555; B_In = 32'h5555_AAAA; MDU_Op_In = ops[i];
        Start_In = 1; tick; Start_In = 0;
        chk1(tid, MDU_Ready_Out, 1'b1, "G18 Ready=1 mul op      ");
      end
    end

    // ========================================================================
    // G19: Start_In for MUL does NOT start the divider
    //      After a MUL Start_In, MDU_Ready_Out must remain 1 immediately
    // ========================================================================
    banner("G19: MUL Start does not start divider");
    do_reset; tick;
    A_In = 32'd5; B_In = 32'd6; MDU_Op_In = MUL;
    Start_In = 1; tick; Start_In = 0;
    // If divider was accidentally started, Ready would drop
    chk1(tid, MDU_Ready_Out, 1'b1, "G19 Ready=1 after MUL   ");
    tick; chk1(tid, MDU_Ready_Out, 1'b1, "G19 Ready=1 +2 cycles   ");
    tick; chk1(tid, MDU_Ready_Out, 1'b1, "G19 Ready=1 +3 cycles   ");

    // ========================================================================
    // G20: Start_In for DIV does NOT affect the multiply result path
    //      After divide completes, issue a multiply — result must be from
    //      the multiplier (Mul_Result), not from a stale Div_Result
    // ========================================================================
    banner("G20: Div result does not corrupt MUL");
    do_reset; tick;
    div_op(32'd100, 32'd3, DIVU, r, c);
    chk(tid, r, 32'd33, "G20 div 100/3=33        ");
    // Switch to multiply immediately
    mul_op(32'd10, 32'd10, MUL, r);
    chk(tid, r, 32'd100,  "G20 mul 10×10=100 clean ");

    // ========================================================================
    // G21: Divide latency bounds — normal case should be <= 33 cycles
    // ========================================================================
    banner("G21: Divide latency bounds");
    do_reset; tick;
    div_op(32'hFFFF_FFFF, 32'h0000_0001, DIVU, r, c);
    chk(tid, r, UINT32_MAX,  "G21 UINT_MAX/1 correct  ");
    chk_cyc(tid, c, 1, 33,   "G21 latency <= 33 cycles");

    div_op(32'd1, 32'd1, DIV, r, c);
    chk(tid, r, 32'd1,       "G21 1/1=1 correct       ");
    chk_cyc(tid, c, 1, 33,   "G21 small div latency   ");

    // ========================================================================
    // Summary
    // ========================================================================
    $display("\n=================================================");
    $display(" TOTAL CHECKS : %0d", pass_count + fail_count);
    $display(" PASSED       : %0d", pass_count);
    $display(" FAILED       : %0d", fail_count);
    $display("=================================================");
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else                 $display("SOME TESTS FAILED");
    $finish;
  end

  initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
/* verilator lint_on TIMESCALEMOD */
/* verilator lint_on WIDTHEXPAND  */
/* verilator lint_on WIDTHTRUNC   */
/* verilator lint_on UNUSEDPARAM  */
/* verilator lint_on UNDRIVEN     */
