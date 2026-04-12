/* verilator lint_off TIMESCALEMOD */
/* verilator lint_off WIDTHEXPAND  */
/* verilator lint_off WIDTHTRUNC   */
/* verilator lint_off UNUSEDPARAM  */
`timescale 1ns/1ps

// =============================================================================
// Comprehensive testbench for Machine_Control (4-state Moore FSM trap controller)
//
// FSM states: RESET(0001) → OPERATING(0010) ↔ TRAP_TAKEN(0100) ↔ TRAP_RETURN(1000)
//
// Test groups:
//  G0  : Reset — state, all outputs in RESET state
//  G1  : RESET→OPERATING transition, output changes
//  G2  : OPERATING — normal execution outputs (Instret_Inc, PC_SRC_NEXT, no flush)
//  G3  : MRET decode — opcode/func7/func3/rs1/rs2/rd field all-correct vs corrupted
//  G4  : ECALL decode — correct and near-miss fields
//  G5  : EBREAK decode — correct and near-miss fields
//  G6  : OPERATING→TRAP_TAKEN on external interrupt (EIP, MIE=1, MEIE=1)
//  G7  : OPERATING→TRAP_TAKEN on software interrupt (SIP)
//  G8  : OPERATING→TRAP_TAKEN on timer interrupt (TIP)
//  G9  : Interrupt priority: EIP > SIP > TIP
//  G10 : Interrupts blocked when MIE=0
//  G11 : Interrupts blocked when individual enable (MEIE/MTIE/MSIE)=0
//  G12 : TRAP_TAKEN outputs — Set_EPC, Set_Cause, MIE_Clear, Flush, PC_SRC_TRAP
//  G13 : TRAP_TAKEN→OPERATING (one-cycle trap entry, then back)
//  G14 : Cause/I_Or_E for all 9 trap types (registered in OPERATING)
//  G15 : OPERATING→TRAP_RETURN on MRET
//  G16 : TRAP_RETURN outputs — MIE_Set, Flush, PC_SRC_EPC, no Set_EPC/Cause
//  G17 : TRAP_RETURN→OPERATING (one-cycle return, then back)
//  G18 : Trap_Taken_Out combinatorial (exceptions don't need MIE)
//  G19 : Trap_Taken_Out blocked for interrupts when MIE=0
//  G20 : EIP uses both EIrq_In (direct) and MEIP_In (registered) inputs
//  G21 : TIP uses both TIrq_In and MTIP_In
//  G22 : SIP uses both SIrq_In and MSIP_In
//  G23 : Misaligned_Exc_Out registered one cycle ahead of Set_Cause_Out
//  G24 : Cause_Out/I_Or_E_Out held stable during TRAP_TAKEN (not re-computed)
//  G25 : Exception causes (all 4 exception types, no MIE needed)
//  G26 : MRET during OPERATING when no trap (TRAP_RETURN path)
//  G27 : Simultaneous MRET + exception — exception wins (Trap_Taken > MRET)
//  G28 : Back-to-back traps (trap fires immediately after TRAP_TAKEN→OPERATING)
//  G29 : Instret_Inc_Out only in OPERATING, not in RESET/TRAP_TAKEN/TRAP_RETURN
//  G30 : Flush_Out in RESET, TRAP_TAKEN, TRAP_RETURN; not in OPERATING
// =============================================================================

module tb_Machine_Control;

  // --------------------------------------------------------------------------
  // DUT ports
  // --------------------------------------------------------------------------
  reg         Clk_In;
  reg         Rst_In;
  reg         Illegal_Instr_In;
  reg         Misaligned_Instr_In;
  reg         Load_Access_Fault_In;
  reg         Misaligned_Load_In;
  reg         Misaligned_Store_In;
  reg  [4:0]  Opcode_6to2_In;
  reg  [2:0]  Func3_In;
  reg  [6:0]  Func7_In;
  reg  [4:0]  Src_Addr1_In;
  reg  [4:0]  Src_Addr2_In;
  reg  [4:0]  Des_Addr_In;
  reg         EIrq_In;
  reg         TIrq_In;
  reg         SIrq_In;
  reg         MIE_In;
  reg         MEIE_In;
  reg         MTIE_In;
  reg         MSIE_In;
  reg         MEIP_In;
  reg         MTIP_In;
  reg         MSIP_In;

  wire        I_Or_E_Out;
  wire        Set_EPC_Out;
  wire        Set_Cause_Out;
  wire [3:0]  Cause_Out;
  wire        Instret_Inc_Out;
  wire        MIE_Clear_Out;
  wire        MIE_Set_Out;
  wire        Misaligned_Exc_Out;
  wire [1:0]  PC_Src_Out;
  wire        Flush_Out;
  wire        Trap_Taken_Out;

  // --------------------------------------------------------------------------
  // PC source encoding constants
  // --------------------------------------------------------------------------
  localparam PC_SRC_BOOT = 2'b00;
  localparam PC_SRC_EPC  = 2'b01;
  localparam PC_SRC_TRAP = 2'b10;
  localparam PC_SRC_NEXT = 2'b11;

  // Instruction encoding for SYSTEM instructions
  localparam OPCODE_SYSTEM = 5'b11100; // opcode[6:2]
  localparam FUNC3_ZERO    = 3'b000;
  localparam FUNC7_ZERO    = 7'b0000000;
  localparam FUNC7_MRET    = 7'b0011000;
  localparam RS2_ZERO      = 5'b00000;
  localparam RS2_MRET      = 5'b00010;
  localparam RS2_EBREAK    = 5'b00001;
  localparam RS1_ZERO      = 5'b00000;
  localparam RD_ZERO       = 5'b00000;

  // Cause codes
  localparam CAUSE_EXT_INT  = 4'b1011; // external interrupt
  localparam CAUSE_SW_INT   = 4'b0011; // software interrupt
  localparam CAUSE_TIM_INT  = 4'b0111; // timer interrupt
  localparam CAUSE_ILL_INS  = 4'b0010; // illegal instruction
  localparam CAUSE_MISAL_I  = 4'b0000; // misaligned instruction
  localparam CAUSE_ECALL    = 4'b1011; // ecall from M-mode
  localparam CAUSE_EBREAK   = 4'b0011; // breakpoint
  localparam CAUSE_MISAL_S  = 4'b0110; // misaligned store
  localparam CAUSE_MISAL_L  = 4'b0100; // misaligned load

  // --------------------------------------------------------------------------
  // Scoreboard
  // --------------------------------------------------------------------------
  integer pass_count;
  integer fail_count;
  integer tid;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  Machine_Control dut (
    .Clk_In              (Clk_In),
    .Rst_In              (Rst_In),
    .Illegal_Instr_In    (Illegal_Instr_In),
    .Misaligned_Instr_In (Misaligned_Instr_In),
    .Load_Access_Fault_In(Load_Access_Fault_In),
    .Misaligned_Load_In  (Misaligned_Load_In),
    .Misaligned_Store_In (Misaligned_Store_In),
    .Opcode_6to2_In      (Opcode_6to2_In),
    .Func3_In            (Func3_In),
    .Func7_In            (Func7_In),
    .Src_Addr1_In        (Src_Addr1_In),
    .Src_Addr2_In        (Src_Addr2_In),
    .Des_Addr_In         (Des_Addr_In),
    .EIrq_In             (EIrq_In),
    .TIrq_In             (TIrq_In),
    .SIrq_In             (SIrq_In),
    .MIE_In              (MIE_In),
    .MEIE_In             (MEIE_In),
    .MTIE_In             (MTIE_In),
    .MSIE_In             (MSIE_In),
    .MEIP_In             (MEIP_In),
    .MTIP_In             (MTIP_In),
    .MSIP_In             (MSIP_In),
    .I_Or_E_Out          (I_Or_E_Out),
    .Set_EPC_Out         (Set_EPC_Out),
    .Set_Cause_Out       (Set_Cause_Out),
    .Cause_Out           (Cause_Out),
    .Instret_Inc_Out     (Instret_Inc_Out),
    .MIE_Clear_Out       (MIE_Clear_Out),
    .MIE_Set_Out         (MIE_Set_Out),
    .Misaligned_Exc_Out  (Misaligned_Exc_Out),
    .PC_Src_Out          (PC_Src_Out),
    .Flush_Out           (Flush_Out),
    .Trap_Taken_Out      (Trap_Taken_Out)
  );

  // --------------------------------------------------------------------------
  // Clock — 10 ns period
  // --------------------------------------------------------------------------
  initial Clk_In = 0;
  always  #5 Clk_In = ~Clk_In;

  // ==========================================================================
  // Tasks
  // ==========================================================================

  // Set all inputs to safe idle (no trap, no instruction, no irq)
  task idle_inputs;
    begin
      Illegal_Instr_In    = 0;
      Misaligned_Instr_In = 0;
      Load_Access_Fault_In= 0;
      Misaligned_Load_In  = 0;
      Misaligned_Store_In = 0;
      Opcode_6to2_In      = 5'b0;
      Func3_In            = 3'b0;
      Func7_In            = 7'b0;
      Src_Addr1_In        = 5'b0;
      Src_Addr2_In        = 5'b0;
      Des_Addr_In         = 5'b0;
      EIrq_In  = 0; TIrq_In  = 0; SIrq_In  = 0;
      MIE_In   = 0;
      MEIE_In  = 0; MTIE_In  = 0; MSIE_In  = 0;
      MEIP_In  = 0; MTIP_In  = 0; MSIP_In  = 0;
    end
  endtask

  // Apply MRET instruction encoding
  task set_mret;
    begin
      Opcode_6to2_In = OPCODE_SYSTEM;
      Func7_In       = FUNC7_MRET;
      Src_Addr2_In   = RS2_MRET;
      Src_Addr1_In   = RS1_ZERO;
      Func3_In       = FUNC3_ZERO;
      Des_Addr_In    = RD_ZERO;
    end
  endtask

  // Apply ECALL instruction encoding
  task set_ecall;
    begin
      Opcode_6to2_In = OPCODE_SYSTEM;
      Func7_In       = FUNC7_ZERO;
      Src_Addr2_In   = RS2_ZERO;
      Src_Addr1_In   = RS1_ZERO;
      Func3_In       = FUNC3_ZERO;
      Des_Addr_In    = RD_ZERO;
    end
  endtask

  // Apply EBREAK instruction encoding
  task set_ebreak;
    begin
      Opcode_6to2_In = OPCODE_SYSTEM;
      Func7_In       = FUNC7_ZERO;
      Src_Addr2_In   = RS2_EBREAK;
      Src_Addr1_In   = RS1_ZERO;
      Func3_In       = FUNC3_ZERO;
      Des_Addr_In    = RD_ZERO;
    end
  endtask

  // Full synchronous reset
  task do_reset;
    begin
      idle_inputs;
      Rst_In = 1;
      @(posedge Clk_In); #1;
      @(posedge Clk_In); #1;
      Rst_In = 0;
      #1;
    end
  endtask

  // Advance one clock and settle
  task tick;
    begin
      @(posedge Clk_In); #1;
    end
  endtask

  // Reach OPERATING state from reset (1 tick after rst deasserts)
  task goto_operating;
    begin
      do_reset;
      tick; // RESET → OPERATING
    end
  endtask

  // Check 32-bit value
  task chk;
    input integer  id;
    input [31:0]   got;
    input [31:0]   exp;
    input [255:0]  label;
    begin
      if (got === exp) begin
        $display("PASS [%0d] %s : 0x%0h", id, label, got);
        pass_count = pass_count + 1;
      end else begin
        $display("FAIL [%0d] %s : got=0x%0h  exp=0x%0h", id, label, got, exp);
        fail_count = fail_count + 1;
      end
      tid = tid + 1;
    end
  endtask

  // Check single bit (zero-extended to 32)
  task chk1;
    input integer  id;
    input          got;
    input          exp;
    input [255:0]  label;
    begin
      chk(id, {31'b0, got}, {31'b0, exp}, label);
    end
  endtask

  task banner;
    input [511:0] s;
    begin $display("\n--- %s ---", s); end
  endtask

  // ==========================================================================
  // STIMULUS
  // ==========================================================================
  initial begin
    pass_count = 0; fail_count = 0; tid = 0;

    // ========================================================================
    // G0: Reset — outputs during RESET state (first cycle after rst deasserts)
    // ========================================================================
    banner("G0: Reset state outputs");
    idle_inputs;
    Rst_In = 1;
    @(posedge Clk_In); #1;
    // Still in reset: Curr_State=RESET on next rising edge
    // After first posedge with Rst=1, state=RESET
    // RESET outputs: PC_SRC_BOOT, Flush=1, Instret=0, all strobes=0
    Rst_In = 0; #1;
    // Now Curr_State=RESET (registered on last reset edge)
    chk1(tid, Flush_Out,       1'b1,        "G0 Flush=1 in RESET     ");
    chk(tid,  PC_Src_Out,      PC_SRC_BOOT, "G0 PC_SRC_BOOT RESET    ");
    chk1(tid, Instret_Inc_Out, 1'b0,        "G0 Instret=0 RESET      ");
    chk1(tid, Set_EPC_Out,     1'b0,        "G0 Set_EPC=0 RESET      ");
    chk1(tid, Set_Cause_Out,   1'b0,        "G0 Set_Cause=0 RESET    ");
    chk1(tid, MIE_Clear_Out,   1'b0,        "G0 MIE_Clear=0 RESET    ");
    chk1(tid, MIE_Set_Out,     1'b0,        "G0 MIE_Set=0 RESET      ");
    chk1(tid, Trap_Taken_Out,  1'b0,        "G0 Trap_Taken=0 RESET   ");

    // ========================================================================
    // G1: RESET→OPERATING transition
    // ========================================================================
    banner("G1: RESET to OPERATING transition");
    // Already in RESET state (Rst_In=0, state=RESET)
    tick; // state becomes OPERATING
    chk1(tid, Flush_Out,       1'b0,        "G1 Flush=0 OPERATING    ");
    chk(tid,  PC_Src_Out,      PC_SRC_NEXT, "G1 PC_SRC_NEXT OPERAT   ");
    chk1(tid, Instret_Inc_Out, 1'b1,        "G1 Instret=1 OPERATING  ");
    chk1(tid, Set_EPC_Out,     1'b0,        "G1 Set_EPC=0 OPERAT     ");
    chk1(tid, Set_Cause_Out,   1'b0,        "G1 Set_Cause=0 OPERAT   ");
    chk1(tid, MIE_Clear_Out,   1'b0,        "G1 MIE_Clear=0 OPERAT   ");
    chk1(tid, MIE_Set_Out,     1'b0,        "G1 MIE_Set=0 OPERAT     ");

    // ========================================================================
    // G2: OPERATING — steady state, Instret pulses every cycle
    // ========================================================================
    banner("G2: OPERATING steady state");
    // Already in OPERATING; idle for several cycles and check outputs stay stable
    tick;
    chk1(tid, Instret_Inc_Out, 1'b1,        "G2 Instret=1 cycle 1    ");
    chk1(tid, Flush_Out,       1'b0,        "G2 Flush=0 cycle 1      ");
    chk(tid,  PC_Src_Out,      PC_SRC_NEXT, "G2 PC_SRC_NEXT cycle 1  ");
    tick;
    chk1(tid, Instret_Inc_Out, 1'b1,        "G2 Instret=1 cycle 2    ");
    tick;
    chk1(tid, Instret_Inc_Out, 1'b1,        "G2 Instret=1 cycle 3    ");

    // ========================================================================
    // G3: MRET decode — correct and corrupted field variants
    // ========================================================================
    banner("G3: MRET instruction decode");
    goto_operating;

    // Correct MRET: all fields match
    set_mret;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b0, "G3 Trap=0 on MRET       ");
    // MRET alone doesn't assert Trap_Taken — it drives TRAP_RETURN
    tick; // OPERATING → TRAP_RETURN (MRET seen)
    chk(tid, PC_Src_Out, PC_SRC_EPC, "G3 PC_SRC_EPC TRAP_RET  ");
    chk1(tid, MIE_Set_Out, 1'b1,     "G3 MIE_Set=1 TRAP_RET   ");
    chk1(tid, Flush_Out,   1'b1,     "G3 Flush=1 TRAP_RET     ");
    tick; // TRAP_RETURN → OPERATING
    idle_inputs;

    // MRET with wrong func7 (0000000 instead of 0011000) → not decoded as MRET
    goto_operating;
    Opcode_6to2_In = OPCODE_SYSTEM; Func7_In = FUNC7_ZERO;
    Src_Addr2_In = RS2_MRET; Src_Addr1_In = RS1_ZERO;
    Func3_In = FUNC3_ZERO; Des_Addr_In = RD_ZERO;
    #1;
    tick; // should stay in OPERATING (not MRET)
    chk(tid, PC_Src_Out, PC_SRC_NEXT, "G3 wrong func7 no MRET  ");
    chk1(tid, MIE_Set_Out, 1'b0,      "G3 MIE_Set=0 no MRET    ");
    idle_inputs;

    // MRET with wrong rs2 (00001 instead of 00010) → EBREAK instead
    goto_operating;
    Opcode_6to2_In = OPCODE_SYSTEM; Func7_In = FUNC7_MRET;
    Src_Addr2_In = RS2_EBREAK; // wrong rs2
    Src_Addr1_In = RS1_ZERO; Func3_In = FUNC3_ZERO; Des_Addr_In = RD_ZERO;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b0, "G3 wrong rs2 not MRET   ");
    idle_inputs;

    // MRET with non-zero rd → not MRET
    goto_operating;
    set_mret; Des_Addr_In = 5'b00001; // rd!=x0
    #1;
    tick;
    chk(tid, PC_Src_Out, PC_SRC_NEXT, "G3 rd!=0 no MRET        ");
    idle_inputs;

    // MRET with non-zero rs1 → not MRET
    goto_operating;
    set_mret; Src_Addr1_In = 5'b00001;
    #1;
    tick;
    chk(tid, PC_Src_Out, PC_SRC_NEXT, "G3 rs1!=0 no MRET       ");
    idle_inputs;

    // MRET with non-zero func3 → not MRET
    goto_operating;
    set_mret; Func3_In = 3'b001;
    #1;
    tick;
    chk(tid, PC_Src_Out, PC_SRC_NEXT, "G3 func3!=0 no MRET     ");
    idle_inputs;

    // ========================================================================
    // G4: ECALL decode
    // ========================================================================
    banner("G4: ECALL decode");
    goto_operating;

    // Correct ECALL
    set_ecall; #1;
    chk1(tid, Trap_Taken_Out, 1'b1,     "G4 Trap_Taken ECALL     ");
    tick; // OPERATING → TRAP_TAKEN
    chk(tid, PC_Src_Out, PC_SRC_TRAP,   "G4 PC_SRC_TRAP ECALL    ");
    chk1(tid, Set_EPC_Out,   1'b1,      "G4 Set_EPC ECALL        ");
    chk1(tid, Set_Cause_Out, 1'b1,      "G4 Set_Cause ECALL      ");
    tick; // TRAP_TAKEN → OPERATING
    idle_inputs;

    // ECALL with wrong opcode → no trap
    goto_operating;
    set_ecall; Opcode_6to2_In = 5'b00000; // wrong opcode
    #1;
    chk1(tid, Trap_Taken_Out, 1'b0,     "G4 wrong opcode no ECALL");
    idle_inputs;

    // ECALL with non-zero rs2 → becomes EBREAK (rs2=1) or nothing (rs2=2+)
    goto_operating;
    set_ecall; Src_Addr2_In = 5'b00010; // rs2!=0 → neither ECALL nor EBREAK
    #1;
    chk1(tid, Trap_Taken_Out, 1'b0,     "G4 rs2!=0 no ECALL      ");
    idle_inputs;

    // ========================================================================
    // G5: EBREAK decode
    // ========================================================================
    banner("G5: EBREAK decode");
    goto_operating;

    // Correct EBREAK
    set_ebreak; #1;
    chk1(tid, Trap_Taken_Out, 1'b1,     "G5 Trap_Taken EBREAK    ");
    tick;
    chk(tid, PC_Src_Out, PC_SRC_TRAP,   "G5 PC_SRC_TRAP EBREAK   ");
    tick; idle_inputs;

    // EBREAK with wrong func7 (FUNC7_MRET) → not EBREAK
    goto_operating;
    set_ebreak; Func7_In = FUNC7_MRET;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b0,     "G5 wrong func7 no EBRK  ");
    idle_inputs;

    // ========================================================================
    // G6: External interrupt → TRAP_TAKEN (EIrq direct line)
    // ========================================================================
    banner("G6: External interrupt EIrq");
    goto_operating;
    MIE_In = 1; MEIE_In = 1; EIrq_In = 1;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b1,     "G6 Trap_Taken EIrq      ");
    tick; // TRAP_TAKEN
    chk(tid, PC_Src_Out, PC_SRC_TRAP,   "G6 PC_SRC_TRAP EIrq     ");
    chk1(tid, MIE_Clear_Out, 1'b1,      "G6 MIE_Clear EIrq       ");
    chk1(tid, Set_EPC_Out,   1'b1,      "G6 Set_EPC EIrq         ");
    chk1(tid, Set_Cause_Out, 1'b1,      "G6 Set_Cause EIrq       ");
    chk1(tid, Flush_Out,     1'b1,      "G6 Flush EIrq           ");
    chk1(tid, Instret_Inc_Out, 1'b0,    "G6 Instret=0 TRAP_TAKEN ");
    tick; // back to OPERATING
    MIE_In = 0; MEIE_In = 0; EIrq_In = 0;

    // ========================================================================
    // G7: Software interrupt → TRAP_TAKEN
    // ========================================================================
    banner("G7: Software interrupt SIrq");
    goto_operating;
    MIE_In = 1; MSIE_In = 1; SIrq_In = 1;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b1,     "G7 Trap_Taken SIrq      ");
    tick;
    chk(tid, PC_Src_Out, PC_SRC_TRAP,   "G7 PC_SRC_TRAP SIrq     ");
    chk1(tid, MIE_Clear_Out, 1'b1,      "G7 MIE_Clear SIrq       ");
    tick; MIE_In = 0; MSIE_In = 0; SIrq_In = 0;

    // ========================================================================
    // G8: Timer interrupt → TRAP_TAKEN
    // ========================================================================
    banner("G8: Timer interrupt TIrq");
    goto_operating;
    MIE_In = 1; MTIE_In = 1; TIrq_In = 1;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b1,     "G8 Trap_Taken TIrq      ");
    tick;
    chk(tid, PC_Src_Out, PC_SRC_TRAP,   "G8 PC_SRC_TRAP TIrq     ");
    tick; MIE_In = 0; MTIE_In = 0; TIrq_In = 0;

    // ========================================================================
    // G9: Interrupt priority EIP > SIP > TIP
    // ========================================================================
    banner("G9: Interrupt priority");
    // EIP + SIP + TIP all asserted → EIP wins (cause=1011)
    goto_operating;
    MIE_In = 1; MEIE_In = 1; MSIE_In = 1; MTIE_In = 1;
    EIrq_In = 1; SIrq_In = 1; TIrq_In = 1;
    tick; // OPERATING→TRAP_TAKEN; cause registered on OPERATING clock
    // On this OPERATING cycle, EIP wins → Cause=1011, I_Or_E=1
    tick; // now in OPERATING again (TRAP_TAKEN→OPERATING)
    // Check cause that was registered
    chk(tid, Cause_Out,    CAUSE_EXT_INT, "G9 EIP wins cause=1011  ");
    chk1(tid, I_Or_E_Out,  1'b1,          "G9 EIP I_Or_E=1         ");
    EIrq_In = 0; // drop EIP, keep SIP+TIP

    // Wait one OPERATING cycle for SIP to be registered as cause
    tick; // OPERATING — SIP now highest, registers cause=0011
    // Now trigger trap
    tick; // TRAP_TAKEN
    tick; // back to OPERATING
    chk(tid, Cause_Out,    CAUSE_SW_INT,  "G9 SIP wins cause=0011  ");
    chk1(tid, I_Or_E_Out,  1'b1,          "G9 SIP I_Or_E=1         ");
    SIrq_In = 0; // drop SIP, keep TIP only

    tick; // OPERATING — TIP now highest, registers cause=0111
    tick; // TRAP_TAKEN
    tick; // back to OPERATING
    chk(tid, Cause_Out,    CAUSE_TIM_INT, "G9 TIP wins cause=0111  ");
    chk1(tid, I_Or_E_Out,  1'b1,          "G9 TIP I_Or_E=1         ");
    MIE_In = 0; MEIE_In = 0; MSIE_In = 0; MTIE_In = 0;
    TIrq_In = 0;

    // ========================================================================
    // G10: Interrupts blocked when MIE=0
    // ========================================================================
    banner("G10: MIE=0 blocks all interrupts");
    goto_operating;
    MIE_In = 0; MEIE_In = 1; MSIE_In = 1; MTIE_In = 1;
    EIrq_In = 1; SIrq_In = 1; TIrq_In = 1;
    #1;
    chk1(tid, Trap_Taken_Out, 1'b0,      "G10 Trap=0 MIE=0 EIrq   ");
    tick;
    chk(tid, PC_Src_Out, PC_SRC_NEXT,    "G10 PC_NEXT MIE=0 irqs  ");
    chk1(tid, Instret_Inc_Out, 1'b1,     "G10 Instret=1 no trap   ");
    EIrq_In = 0; SIrq_In = 0; TIrq_In = 0; MIE_In = 0;

    // ========================================================================
    // G11: Individual enable bits gate each interrupt
    // ========================================================================
    banner("G11: Individual interrupt enables");
    goto_operating;
    MIE_In = 1;

    // MEIE=0 blocks EIrq even with MIE=1
    MEIE_In = 0; EIrq_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b0,  "G11 MEIE=0 blocks EIrq  ");
    EIrq_In = 0;

    // MSIE=0 blocks SIrq
    MSIE_In = 0; SIrq_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b0,  "G11 MSIE=0 blocks SIrq  ");
    SIrq_In = 0;

    // MTIE=0 blocks TIrq
    MTIE_In = 0; TIrq_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b0,  "G11 MTIE=0 blocks TIrq  ");
    TIrq_In = 0; MIE_In = 0;

    // ========================================================================
    // G12: TRAP_TAKEN state — verify all outputs
    // ========================================================================
    banner("G12: TRAP_TAKEN outputs");
    goto_operating;
    MIE_In = 1; MEIE_In = 1; EIrq_In = 1;
    tick; // TRAP_TAKEN
    chk(tid,  PC_Src_Out,      PC_SRC_TRAP, "G12 PC_SRC_TRAP         ");
    chk1(tid, Flush_Out,       1'b1,        "G12 Flush=1             ");
    chk1(tid, Instret_Inc_Out, 1'b0,        "G12 Instret=0           ");
    chk1(tid, Set_EPC_Out,     1'b1,        "G12 Set_EPC=1           ");
    chk1(tid, Set_Cause_Out,   1'b1,        "G12 Set_Cause=1         ");
    chk1(tid, MIE_Clear_Out,   1'b1,        "G12 MIE_Clear=1         ");
    chk1(tid, MIE_Set_Out,     1'b0,        "G12 MIE_Set=0           ");
    chk1(tid, Set_EPC_Out,     1'b1,        "G12 Set_EPC=1 (2nd chk) ");
    tick; MIE_In = 0; MEIE_In = 0; EIrq_In = 0;

    // ========================================================================
    // G13: TRAP_TAKEN is exactly one cycle → returns to OPERATING
    // ========================================================================
    banner("G13: TRAP_TAKEN one-cycle duration");
    goto_operating;
    MIE_In = 1; MEIE_In = 1; EIrq_In = 1;
    tick; // TRAP_TAKEN
    chk(tid, PC_Src_Out, PC_SRC_TRAP, "G13 in TRAP_TAKEN       ");
    // Drop interrupt so no re-trap
    EIrq_In = 0; MIE_In = 0;
    tick; // TRAP_TAKEN → OPERATING
    chk(tid, PC_Src_Out, PC_SRC_NEXT, "G13 back to OPERATING   ");
    chk1(tid, Instret_Inc_Out, 1'b1,  "G13 Instret=1 OPERATING ");
    chk1(tid, Set_EPC_Out,     1'b0,  "G13 Set_EPC=0 after trap");
    chk1(tid, MIE_Clear_Out,   1'b0,  "G13 MIE_Clr=0 after trap");

    // ========================================================================
    // G14: Cause_Out / I_Or_E_Out registered for all 9 trap types
    //      These are registered in OPERATING one cycle before TRAP_TAKEN.
    // ========================================================================
    banner("G14: All cause codes registered");

    // External interrupt (cause=1011, I_Or_E=1)
    goto_operating;
    MIE_In=1; MEIE_In=1; EIrq_In=1;
    // In OPERATING right now — cause is being registered this cycle
    tick; // TRAP_TAKEN — cause was latched on previous OPERATING edge
    tick; // back to OPERATING
    chk(tid, Cause_Out,   CAUSE_EXT_INT, "G14 ext int cause=1011  ");
    chk1(tid, I_Or_E_Out, 1'b1,          "G14 ext int I_Or_E=1    ");
    MIE_In=0; MEIE_In=0; EIrq_In=0;

    // Software interrupt (cause=0011, I_Or_E=1)
    goto_operating;
    MIE_In=1; MSIE_In=1; SIrq_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_SW_INT,  "G14 sw int cause=0011   ");
    chk1(tid, I_Or_E_Out, 1'b1,          "G14 sw int I_Or_E=1     ");
    MIE_In=0; MSIE_In=0; SIrq_In=0;

    // Timer interrupt (cause=0111, I_Or_E=1)
    goto_operating;
    MIE_In=1; MTIE_In=1; TIrq_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_TIM_INT, "G14 tim int cause=0111  ");
    chk1(tid, I_Or_E_Out, 1'b1,          "G14 tim int I_Or_E=1    ");
    MIE_In=0; MTIE_In=0; TIrq_In=0;

    // Illegal instruction (cause=0010, I_Or_E=0)
    goto_operating;
    Illegal_Instr_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_ILL_INS, "G14 ill instr cause=0010");
    chk1(tid, I_Or_E_Out, 1'b0,          "G14 ill instr I_Or_E=0  ");
    Illegal_Instr_In=0;

    // Misaligned instruction (cause=0000, I_Or_E=0)
    goto_operating;
    Misaligned_Instr_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_MISAL_I, "G14 mis instr cause=0000");
    chk1(tid, I_Or_E_Out, 1'b0,          "G14 mis instr I_Or_E=0  ");
    Misaligned_Instr_In=0;

    // ECALL (cause=1011, I_Or_E=0) — note same code as ext int but I_Or_E=0
    goto_operating;
    set_ecall;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_ECALL,   "G14 ecall cause=1011    ");
    chk1(tid, I_Or_E_Out, 1'b0,          "G14 ecall I_Or_E=0      ");
    idle_inputs;

    // EBREAK (cause=0011, I_Or_E=0)
    goto_operating;
    set_ebreak;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_EBREAK,  "G14 ebreak cause=0011   ");
    chk1(tid, I_Or_E_Out, 1'b0,          "G14 ebreak I_Or_E=0     ");
    idle_inputs;

    // Misaligned store (cause=0110, I_Or_E=0)
    goto_operating;
    Misaligned_Store_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_MISAL_S, "G14 mis store cause=0110");
    chk1(tid, I_Or_E_Out, 1'b0,          "G14 mis store I_Or_E=0  ");
    Misaligned_Store_In=0;

    // Misaligned load (cause=0100, I_Or_E=0) — lowest priority exception
    goto_operating;
    Misaligned_Load_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_MISAL_L, "G14 mis load cause=0100 ");
    chk1(tid, I_Or_E_Out, 1'b0,          "G14 mis load I_Or_E=0   ");
    Misaligned_Load_In=0;

    // ========================================================================
    // G15: MRET → TRAP_RETURN state
    // ========================================================================
    banner("G15: MRET goes to TRAP_RETURN");
    goto_operating;
    set_mret; #1;
    chk1(tid, Trap_Taken_Out, 1'b0,      "G15 Trap=0 for MRET     ");
    tick; // TRAP_RETURN
    chk(tid,  PC_Src_Out,  PC_SRC_EPC,   "G15 PC_SRC_EPC MRET     ");
    chk1(tid, MIE_Set_Out,    1'b1,      "G15 MIE_Set=1 MRET      ");
    chk1(tid, Flush_Out,      1'b1,      "G15 Flush=1 MRET        ");
    chk1(tid, MIE_Clear_Out,  1'b0,      "G15 MIE_Clr=0 MRET      ");
    chk1(tid, Set_EPC_Out,    1'b0,      "G15 Set_EPC=0 MRET      ");
    chk1(tid, Set_Cause_Out,  1'b0,      "G15 Set_Cause=0 MRET    ");
    chk1(tid, Instret_Inc_Out,1'b0,      "G15 Instret=0 MRET      ");
    tick; idle_inputs; // back to OPERATING

    // ========================================================================
    // G16: TRAP_RETURN is exactly one cycle → returns to OPERATING
    // ========================================================================
    banner("G16: TRAP_RETURN one-cycle duration");
    goto_operating;
    set_mret;
    tick; // TRAP_RETURN
    chk(tid, PC_Src_Out, PC_SRC_EPC,    "G16 in TRAP_RETURN      ");
    idle_inputs; // clear MRET before next clock
    tick; // TRAP_RETURN → OPERATING
    chk(tid, PC_Src_Out, PC_SRC_NEXT,   "G16 back to OPERATING   ");
    chk1(tid, MIE_Set_Out, 1'b0,        "G16 MIE_Set=0 after ret ");

    // ========================================================================
    // G17: Trap_Taken_Out combinatorial — exceptions don't need MIE
    // ========================================================================
    banner("G17: Trap_Taken_Out combinatorial");
    goto_operating;
    MIE_In = 0; // MIE off

    // Illegal instruction fires regardless of MIE
    Illegal_Instr_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 ill_instr no MIE    ");
    Illegal_Instr_In = 0;

    // Misaligned instruction
    Misaligned_Instr_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 mis_instr no MIE    ");
    Misaligned_Instr_In = 0;

    // Misaligned load
    Misaligned_Load_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 mis_load no MIE     ");
    Misaligned_Load_In = 0;

    // Misaligned store
    Misaligned_Store_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 mis_store no MIE    ");
    Misaligned_Store_In = 0;

    // ECALL
    set_ecall;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 ecall no MIE        ");
    idle_inputs;

    // EBREAK
    set_ebreak;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 ebreak no MIE       ");
    idle_inputs;

    // Interrupt with MIE=0 → Trap_Taken=0
    MIE_In = 0; MEIE_In = 1; EIrq_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b0, "G17 irq MIE=0 no trap   ");
    EIrq_In = 0; MEIE_In = 0;

    // Interrupt with MIE=1 → Trap_Taken=1
    MIE_In = 1; MEIE_In = 1; EIrq_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G17 irq MIE=1 trap      ");
    MIE_In = 0; MEIE_In = 0; EIrq_In = 0;

    // ========================================================================
    // G18: EIP uses both EIrq_In (direct) and MEIP_In (registered MIP)
    // ========================================================================
    banner("G18: EIP = EIrq_In OR MEIP_In");
    goto_operating;
    MIE_In = 1; MEIE_In = 1;

    // EIrq_In alone
    EIrq_In = 1; MEIP_In = 0;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G18 EIrq alone→trap     ");

    // MEIP_In alone
    EIrq_In = 0; MEIP_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G18 MEIP alone→trap     ");

    // Both
    EIrq_In = 1; MEIP_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G18 both EIrq+MEIP→trap ");

    // Neither
    EIrq_In = 0; MEIP_In = 0;
    #1; chk1(tid, Trap_Taken_Out, 1'b0, "G18 neither→no trap     ");
    MIE_In = 0; MEIE_In = 0;

    // ========================================================================
    // G19: TIP = TIrq_In OR MTIP_In
    // ========================================================================
    banner("G19: TIP = TIrq_In OR MTIP_In");
    goto_operating;
    MIE_In = 1; MTIE_In = 1;
    TIrq_In = 1; MTIP_In = 0;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G19 TIrq alone→trap     ");
    TIrq_In = 0; MTIP_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G19 MTIP alone→trap     ");
    TIrq_In = 0; MTIP_In = 0;
    #1; chk1(tid, Trap_Taken_Out, 1'b0, "G19 neither TIrq MTIP   ");
    MIE_In = 0; MTIE_In = 0;

    // ========================================================================
    // G20: SIP = SIrq_In OR MSIP_In
    // ========================================================================
    banner("G20: SIP = SIrq_In OR MSIP_In");
    goto_operating;
    MIE_In = 1; MSIE_In = 1;
    SIrq_In = 1; MSIP_In = 0;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G20 SIrq alone→trap     ");
    SIrq_In = 0; MSIP_In = 1;
    #1; chk1(tid, Trap_Taken_Out, 1'b1, "G20 MSIP alone→trap     ");
    SIrq_In = 0; MSIP_In = 0;
    #1; chk1(tid, Trap_Taken_Out, 1'b0, "G20 neither SIrq MSIP   ");
    MIE_In = 0; MSIE_In = 0;

    // ========================================================================
    // G21: Misaligned_Exc_Out registered one cycle ahead of Set_Cause_Out
    //      When misaligned trap occurs: Misaligned_Exc_Out is registered
    //      in OPERATING (same cycle as cause), Set_Cause asserted in TRAP_TAKEN
    // ========================================================================
    banner("G21: Misaligned_Exc_Out timing");
    goto_operating;
    // Assert misaligned store — should register Misaligned_Exc_Out on this clock
    Misaligned_Store_In = 1;
    tick; // TRAP_TAKEN — Set_Cause_Out=1, Misaligned_Exc_Out was registered
    chk1(tid, Set_Cause_Out,      1'b1, "G21 Set_Cause in TT     ");
    chk1(tid, Misaligned_Exc_Out, 1'b1, "G21 Mis_Exc=1 with store");
    tick; // back to OPERATING
    Misaligned_Store_In = 0;

    // Non-misaligned trap: Misaligned_Exc_Out=0
    goto_operating;
    Illegal_Instr_In = 1;
    tick; // TRAP_TAKEN
    chk1(tid, Misaligned_Exc_Out, 1'b0, "G21 Mis_Exc=0 ill instr ");
    tick; Illegal_Instr_In = 0;

    // Misaligned load also sets Misaligned_Exc_Out
    goto_operating;
    Misaligned_Load_In = 1;
    tick;
    chk1(tid, Misaligned_Exc_Out, 1'b1, "G21 Mis_Exc=1 mis load  ");
    tick; Misaligned_Load_In = 0;

    // Misaligned instruction also sets Misaligned_Exc_Out
    goto_operating;
    Misaligned_Instr_In = 1;
    tick;
    chk1(tid, Misaligned_Exc_Out, 1'b1, "G21 Mis_Exc=1 mis instr ");
    tick; Misaligned_Instr_In = 0;

    // ========================================================================
    // G22: Cause_Out/I_Or_E_Out held stable during TRAP_TAKEN
    //      (RTL fix: cause not re-computed in TRAP_TAKEN/TRAP_RETURN)
    // ========================================================================
    banner("G22: Cause stable during TRAP_TAKEN");
    goto_operating;
    // Set up an illegal instruction trap
    Illegal_Instr_In = 1;
    // On this OPERATING clock: cause=CAUSE_ILL_INS gets registered
    tick; // TRAP_TAKEN — cause from previous cycle
    // Now change the input to something different mid-trap
    Illegal_Instr_In = 0;
    Misaligned_Load_In = 1; // different cause
    // Cause_Out must NOT change in TRAP_TAKEN
    chk(tid, Cause_Out,   CAUSE_ILL_INS, "G22 cause stable TT     ");
    chk1(tid, I_Or_E_Out, 1'b0,          "G22 I_Or_E stable TT    ");
    tick; // back to OPERATING
    Misaligned_Load_In = 0;

    // ========================================================================
    // G23: Simultaneous MRET + exception — exception (Trap_Taken) wins
    //      Trap_Taken_Out is OR of exceptions/ECALL/EBREAK/interrupts.
    //      FSM: if Trap_Taken → TRAP_TAKEN, elif MRET → TRAP_RETURN.
    //      So exception overrides MRET.
    // ========================================================================
    banner("G23: Simultaneous MRET + exception");
    goto_operating;
    set_mret;
    Illegal_Instr_In = 1; // exception simultaneously
    #1;
    chk1(tid, Trap_Taken_Out, 1'b1,      "G23 Trap_Taken wins     ");
    tick; // should go to TRAP_TAKEN (not TRAP_RETURN)
    chk(tid, PC_Src_Out, PC_SRC_TRAP,    "G23 PC_SRC_TRAP not EPC ");
    chk1(tid, Set_EPC_Out,  1'b1,        "G23 Set_EPC (exception) ");
    chk1(tid, MIE_Set_Out,  1'b0,        "G23 MIE_Set=0 not MRET  ");
    tick; idle_inputs;

    // ========================================================================
    // G24: Back-to-back traps (trap immediately after TRAP_TAKEN→OPERATING)
    // ========================================================================
    banner("G24: Back-to-back traps");
    goto_operating;
    // Trap 1: illegal instruction
    Illegal_Instr_In = 1;
    tick; // TRAP_TAKEN (trap 1)
    chk(tid, PC_Src_Out, PC_SRC_TRAP, "G24 trap1 TRAP_TAKEN    ");
    // Keep exception asserted — immediately re-traps on return to OPERATING
    tick; // OPERATING — trap 2 fires immediately
    chk(tid, PC_Src_Out, PC_SRC_NEXT, "G24 brief OPERATING     ");
    tick; // TRAP_TAKEN again (trap 2)
    chk(tid, PC_Src_Out, PC_SRC_TRAP, "G24 trap2 TRAP_TAKEN    ");
    tick; // back to OPERATING
    Illegal_Instr_In = 0;

    // ========================================================================
    // G25: Instret_Inc_Out only in OPERATING
    // ========================================================================
    banner("G25: Instret_Inc_Out state gating");
    // Already know OPERATING=1 from G2. Check TRAP_TAKEN and TRAP_RETURN.
    goto_operating;
    MIE_In = 1; MEIE_In = 1; EIrq_In = 1;
    tick; // TRAP_TAKEN
    chk1(tid, Instret_Inc_Out, 1'b0, "G25 Instret=0 TRAP_TAKEN");
    EIrq_In = 0;
    tick; // OPERATING
    chk1(tid, Instret_Inc_Out, 1'b1, "G25 Instret=1 OPERATING ");
    MIE_In = 0; MEIE_In = 0;

    // Check TRAP_RETURN
    goto_operating;
    set_mret;
    tick; // TRAP_RETURN
    chk1(tid, Instret_Inc_Out, 1'b0, "G25 Instret=0 TRAP_RET  ");
    idle_inputs;
    tick;
    chk1(tid, Instret_Inc_Out, 1'b1, "G25 Instret=1 back OPER ");

    // ========================================================================
    // G26: Flush_Out in correct states only
    // ========================================================================
    banner("G26: Flush_Out state gating");
    // RESET: Flush=1 (checked in G0)
    // OPERATING: Flush=0 (checked in G1/G2)
    // TRAP_TAKEN: Flush=1 (checked in G12)
    // TRAP_RETURN: Flush=1 (checked in G15)
    // Extra verification: Flush drops as soon as OPERATING resumed
    goto_operating;
    MIE_In = 1; MEIE_In = 1; EIrq_In = 1;
    tick; // TRAP_TAKEN → Flush=1
    chk1(tid, Flush_Out, 1'b1,       "G26 Flush=1 TRAP_TAKEN  ");
    EIrq_In = 0; MIE_In = 0; MEIE_In = 0;
    tick; // OPERATING → Flush=0
    chk1(tid, Flush_Out, 1'b0,       "G26 Flush=0 OPERATING   ");

    goto_operating;
    set_mret;
    tick; // TRAP_RETURN → Flush=1
    chk1(tid, Flush_Out, 1'b1,       "G26 Flush=1 TRAP_RETURN ");
    idle_inputs;
    tick; // OPERATING → Flush=0
    chk1(tid, Flush_Out, 1'b0,       "G26 Flush=0 after MRET  ");

    // ========================================================================
    // G27: Exception priority within exceptions
    //      ill_instr > mis_instr > ecall > ebreak > mis_store > mis_load
    // ========================================================================
    banner("G27: Exception cause priority chain");

    // ill_instr + mis_load: ill_instr wins
    goto_operating;
    Illegal_Instr_In = 1; Misaligned_Load_In = 1;
    tick; tick;
    chk(tid, Cause_Out, CAUSE_ILL_INS,  "G27 ill>load cause=0010 ");
    Illegal_Instr_In = 0; Misaligned_Load_In = 0;

    // mis_instr + mis_store: mis_instr wins
    goto_operating;
    Misaligned_Instr_In = 1; Misaligned_Store_In = 1;
    tick; tick;
    chk(tid, Cause_Out, CAUSE_MISAL_I,  "G27 misinstr>store =0000");
    Misaligned_Instr_In = 0; Misaligned_Store_In = 0;

    // mis_store alone > mis_load
    goto_operating;
    Misaligned_Store_In = 1; Misaligned_Load_In = 1;
    tick; tick;
    chk(tid, Cause_Out, CAUSE_MISAL_S,  "G27 store>load cause=0110");
    Misaligned_Store_In = 0; Misaligned_Load_In = 0;

    // interrupt + exception: exception fires via Trap_Taken (both set it),
    // but interrupt takes priority in cause if MIE=1 and EIP — actually
    // Trap_Taken_Out is combinatorial OR, FSM goes to TRAP_TAKEN.
    // Cause is determined by priority chain in OPERATING.
    // With MIE=1, EIP active AND illegal instr: EIP wins cause (higher priority).
    goto_operating;
    MIE_In=1; MEIE_In=1; EIrq_In=1; Illegal_Instr_In=1;
    tick; tick;
    chk(tid, Cause_Out,   CAUSE_EXT_INT, "G27 EIP>ill cause=1011  ");
    chk1(tid, I_Or_E_Out, 1'b1,          "G27 EIP wins I_Or_E=1   ");
    MIE_In=0; MEIE_In=0; EIrq_In=0; Illegal_Instr_In=0;

    // ========================================================================
    // G28: No spurious trap when all inputs idle
    // ========================================================================
    banner("G28: No spurious trap at idle");
    goto_operating;
    idle_inputs;
    tick; chk1(tid, Trap_Taken_Out, 1'b0, "G28 no trap idle        ");
    chk(tid, PC_Src_Out, PC_SRC_NEXT,     "G28 PC_NEXT idle        ");
    tick; chk1(tid, Trap_Taken_Out, 1'b0, "G28 no trap idle 2      ");
    tick; chk1(tid, Trap_Taken_Out, 1'b0, "G28 no trap idle 3      ");

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

  // Watchdog
  initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
/* verilator lint_on TIMESCALEMOD */
/* verilator lint_on WIDTHEXPAND  */
/* verilator lint_on WIDTHTRUNC   */
/* verilator lint_on UNUSEDPARAM  */
