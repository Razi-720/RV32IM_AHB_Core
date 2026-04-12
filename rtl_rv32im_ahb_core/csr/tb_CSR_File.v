/* verilator lint_off TIMESCALEMOD */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDPARAM */
`timescale 1ns/1ps

// =============================================================================
// tb_CSR_File — Comprehensive stress testbench for CSR_File (RV32I+Zicsr)
//
// Test groups
//   G0  : Reset state of every CSR
//   G1  : MISA hardwired value
//   G2  : MSCRATCH — CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI
//   G3  : Data_Wr_Mux NOP path (WrEn=0, op mismatch)
//   G4  : MTVEC — write, read, all cause values in vectored mode, exception override
//   G5  : MIE — individual bit isolation, non-implemented bits stay zero
//   G6  : MSTATUS — MIE/MPIE write; MIE_Clear/MIE_Set priority sequence
//   G7  : MEPC — Set_EPC priority over CSR write; word-alignment mask
//   G8  : MCAUSE — Set_Cause hardware path; SW write; Cause_Rem field; full readback
//   G9  : MTVAL — misaligned path; non-misaligned clears; SW write
//   G10 : MIP — all 8 combinations of EIrq/TIrq/SIrq; reset clears
//   G11 : MCOUNTINHIBIT — CY(bit2) / IR(bit0) independent; non-impl bits zero
//   G12 : MCYCLE — free-run; SW write low half; SW write high half; wrap 32→64
//   G13 : MINSTRET — free-run on pulse; IR inhibit; multi-pulse
//   G14 : MTIME shadow — combinational update of RTC; high word
//   G15 : Counter shadows — CYCLE/CYCLEH/INSTRET/INSTRETH == MCYCLE/H/MINSTRET/H
//   G16 : CSR_Data_Out mux — invalid address returns 0
//   G17 : MIE_Clear / MIE_Set interaction with MPIE chaining (MPIE save/restore)
//   G18 : Trap sequence — full enter+return flow
//   G19 : MISA write-ignored (read-only)
//   G20 : MIP read-only from SW (write ignored)
//   G21 : MEPC word-alignment — unaligned PC write
//   G22 : MCAUSE SW write full field (all 32 bits)
//   G23 : MTVEC vectored all 16 causes
//   G24 : MIE non-implemented bits stay zero
//   G25 : Back-to-back trap sequences
//   G26 : MCYCLE SW write then free-run
// =============================================================================

module tb_CSR_File;

  // ---------------------------------------------------------------------------
  // DUT ports
  // ---------------------------------------------------------------------------
  reg         Clk_In;
  reg         Rst_In;
  reg         WrEn_In;
  reg  [11:0] CSR_Addr_In;
  reg  [2:0]  CSR_Op_In;
  reg  [4:0]  CSR_UImm_In;
  reg  [31:0] CSR_Data_In;
  reg  [31:0] PC_In;
  reg  [31:0] Imm_Added_In;
  reg         I_Or_E_In;
  reg         Set_Cause_In;
  reg         Set_EPC_In;
  reg         Instret_Inc_In;
  reg         MIE_Clear_In;
  reg         MIE_Set_In;
  reg         Misaligned_Exc_In;
  reg  [3:0]  Cause_In;
  reg         EIrq_In;
  reg         TIrq_In;
  reg         SIrq_In;
  reg  [63:0] RTC_In;

  wire [31:0] CSR_Data_Out;
  wire        MIE_Out;
  wire [31:0] EPC_Out;
  wire [31:0] Trap_Addr_Out;
  wire        MEIE_Out, MTIE_Out, MSIE_Out;
  wire        MEIP_Out, MTIP_Out, MSIP_Out;

  // ---------------------------------------------------------------------------
  // CSR address constants
  // ---------------------------------------------------------------------------
  localparam MSTATUS     = 12'h300;
  localparam MISA        = 12'h301;
  localparam MIE_A       = 12'h304;
  localparam MTVEC       = 12'h305;
  localparam MCOUNTINHIB = 12'h320;
  localparam MSCRATCH    = 12'h340;
  localparam MEPC_A      = 12'h341;
  localparam MCAUSE_A    = 12'h342;
  localparam MTVAL_A     = 12'h343;
  localparam MIP_A       = 12'h344;
  localparam MCYCLE_A    = 12'hB00;
  localparam MCYCLEH_A   = 12'hB80;
  localparam MINSTRET_A  = 12'hB02;
  localparam MINSTRETH_A = 12'hB82;
  localparam CYCLE_A     = 12'hC00;
  localparam CYCLEH_A    = 12'hC80;
  localparam TIME_A      = 12'hC01;
  localparam TIMEH_A     = 12'hC81;
  localparam INSTRET_A   = 12'hC02;
  localparam INSTRETH_A  = 12'hC82;

  // funct3 CSR operation codes
  localparam CSRRW  = 3'b001;
  localparam CSRRS  = 3'b010;
  localparam CSRRC  = 3'b011;
  localparam CSRRWI = 3'b101;
  localparam CSRRSI = 3'b110;
  localparam CSRRCI = 3'b111;

  // mstatus reset: MPP=11 hardwired, MPIE=1 on reset
  localparam MSTATUS_RST = 32'h0000_1880;

  // ---------------------------------------------------------------------------
  // Score keeping
  // ---------------------------------------------------------------------------
  integer pass_count;
  integer fail_count;
  integer tid;   // running test-id

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  CSR_File dut (
    .Clk_In(Clk_In), .Rst_In(Rst_In), .WrEn_In(WrEn_In),
    .CSR_Addr_In(CSR_Addr_In), .CSR_Op_In(CSR_Op_In),
    .CSR_UImm_In(CSR_UImm_In), .CSR_Data_In(CSR_Data_In),
    .PC_In(PC_In), .Imm_Added_In(Imm_Added_In),
    .I_Or_E_In(I_Or_E_In), .Set_Cause_In(Set_Cause_In),
    .Set_EPC_In(Set_EPC_In), .Instret_Inc_In(Instret_Inc_In),
    .MIE_Clear_In(MIE_Clear_In), .MIE_Set_In(MIE_Set_In),
    .Misaligned_Exc_In(Misaligned_Exc_In), .Cause_In(Cause_In),
    .EIrq_In(EIrq_In), .TIrq_In(TIrq_In), .SIrq_In(SIrq_In),
    .RTC_In(RTC_In),
    .CSR_Data_Out(CSR_Data_Out), .MIE_Out(MIE_Out),
    .EPC_Out(EPC_Out), .Trap_Addr_Out(Trap_Addr_Out),
    .MEIE_Out(MEIE_Out), .MTIE_Out(MTIE_Out), .MSIE_Out(MSIE_Out),
    .MEIP_Out(MEIP_Out), .MTIP_Out(MTIP_Out), .MSIP_Out(MSIP_Out)
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial Clk_In = 0;
  always  #5 Clk_In = ~Clk_In;

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  task idle_inputs;
    begin
      WrEn_In = 0; CSR_Addr_In = 12'h0; CSR_Op_In = 3'b0;
      CSR_UImm_In = 5'b0; CSR_Data_In = 32'b0;
      PC_In = 32'b0; Imm_Added_In = 32'b0;
      I_Or_E_In = 0; Set_Cause_In = 0; Set_EPC_In = 0;
      Instret_Inc_In = 0; MIE_Clear_In = 0; MIE_Set_In = 0;
      Misaligned_Exc_In = 0; Cause_In = 4'b0;
      EIrq_In = 0; TIrq_In = 0; SIrq_In = 0;
      RTC_In = 64'b0;
    end
  endtask

  task do_reset;
    // Holds reset for 2 clocks, deasserts, combinational settle only.
    // Does NOT tick clock after Rst_In=0 — MCYCLE=0 at task exit.
    // Callers needing register pipeline to settle add their own clocks.
    begin
      idle_inputs;
      Rst_In = 1;
      @(posedge Clk_In); #1;
      @(posedge Clk_In); #1;
      Rst_In = 0;
      #1;
    end
  endtask

  // CSRRW — write data, latch on next posedge
  task csr_write;
    input [11:0] addr;
    input [31:0] data;
    begin
      CSR_Addr_In = addr; CSR_Op_In = CSRRW;
      CSR_Data_In = data; WrEn_In = 1;
      @(posedge Clk_In); #1;
      WrEn_In = 0;
    end
  endtask

  // CSRRS with rs1=0 — pure read (combinational)
  task csr_read;
    input [11:0] addr;
    begin
      CSR_Addr_In = addr; CSR_Op_In = CSRRS;
      CSR_Data_In = 32'b0; WrEn_In = 0;
      #1;
    end
  endtask

  // Check 32-bit value
  task check;
    input integer     id;
    input [31:0]      got;
    input [31:0]      exp;
    input [255:0]     lbl;
    begin
      if (got === exp) begin
        $display("PASS [%0d] %s : 0x%08h", id, lbl, got);
        pass_count = pass_count + 1;
      end else begin
        $display("FAIL [%0d] %s : got=0x%08h  exp=0x%08h", id, lbl, got, exp);
        fail_count = fail_count + 1;
      end
      tid = tid + 1;
    end
  endtask

  // ======= Shorthand single-bit checks (zero-extend for 32-bit compare) =======
  task check1;
    input integer  id;
    input          got;
    input          exp;
    input [255:0]  lbl;
    begin
      check(id, {31'b0, got}, {31'b0, exp}, lbl);
    end
  endtask

  // ===========================================================================
  // MAIN TEST
  // ===========================================================================
  initial begin
    pass_count = 0; fail_count = 0; tid = 0;
    idle_inputs; Rst_In = 1;

    // =========================================================================
    // G0: Reset state of every implemented CSR
    // =========================================================================
    $display("\n--- G0: Reset values ---");
    do_reset;

    // Read counters FIRST — they start ticking the moment Rst_In=0.
    // csr_read only takes #1 of simulation time; read before the next
    // rising edge fires (which would increment MCYCLE to 1).
    csr_read(MCYCLE_A);  check(tid, CSR_Data_Out, 32'h0,        "G0 MCYCLE reset         ");
    csr_read(MCYCLEH_A); check(tid, CSR_Data_Out, 32'h0,        "G0 MCYCLEH reset        ");
    csr_read(MINSTRET_A);check(tid, CSR_Data_Out, 32'h0,        "G0 MINSTRET reset       ");
    // Now clock once — all registered CSRs already have reset values;
    // this settles MIP (which samples irq lines on posedge) to 0.
    @(posedge Clk_In); #1;
    csr_read(MSTATUS);   check(tid, CSR_Data_Out, MSTATUS_RST,  "G0 MSTATUS reset        ");
    csr_read(MISA);      check(tid, CSR_Data_Out, 32'h4000_0100,"G0 MISA reset           ");
    csr_read(MIE_A);     check(tid, CSR_Data_Out, 32'h0,        "G0 MIE reset            ");
    csr_read(MTVEC);     check(tid, CSR_Data_Out, 32'h0,        "G0 MTVEC reset          ");
    csr_read(MCOUNTINHIB);check(tid,CSR_Data_Out, 32'h0,        "G0 MCOUNTINHIB reset    ");
    csr_read(MSCRATCH);  check(tid, CSR_Data_Out, 32'h0,        "G0 MSCRATCH reset       ");
    csr_read(MEPC_A);    check(tid, CSR_Data_Out, 32'h0,        "G0 MEPC reset           ");
    csr_read(MCAUSE_A);  check(tid, CSR_Data_Out, 32'h0,        "G0 MCAUSE reset         ");
    csr_read(MTVAL_A);   check(tid, CSR_Data_Out, 32'h0,        "G0 MTVAL reset          ");
    csr_read(MIP_A);     check(tid, CSR_Data_Out, 32'h0,        "G0 MIP reset            ");
    check1(tid, MIE_Out,  1'b0, "G0 MIE_Out=0 after rst  ");
    check1(tid, MEIE_Out, 1'b0, "G0 MEIE_Out=0 after rst ");
    check1(tid, MTIE_Out, 1'b0, "G0 MTIE_Out=0 after rst ");
    check1(tid, MSIE_Out, 1'b0, "G0 MSIE_Out=0 after rst ");
    check1(tid, MEIP_Out, 1'b0, "G0 MEIP_Out=0 after rst ");
    check1(tid, MTIP_Out, 1'b0, "G0 MTIP_Out=0 after rst ");
    check1(tid, MSIP_Out, 1'b0, "G0 MSIP_Out=0 after rst ");

    // =========================================================================
    // G1: MISA — hardwired, writes ignored
    // =========================================================================
    $display("\n--- G1: MISA hardwired / write-ignored ---");
    csr_read(MISA);
    check(tid, CSR_Data_Out[31:30], 2'b01,  "G1 MISA MXL=01          ");
    check(tid, {23'b0, CSR_Data_Out[8]}, 32'h1, "G1 MISA I-ext bit       ");
    check(tid, CSR_Data_Out[7:0],  8'h00,   "G1 MISA no other exts   ");
    // Attempt to write MISA — should be silently ignored
    csr_write(MISA, 32'hFFFF_FFFF);
    csr_read(MISA);
    check(tid, CSR_Data_Out, 32'h4000_0100, "G1 MISA write ignored   ");

    // =========================================================================
    // G2: MSCRATCH — all six CSR operation variants
    // =========================================================================
    $display("\n--- G2: MSCRATCH all CSR ops ---");
    // CSRRW
    csr_write(MSCRATCH, 32'hAAAA_5555);
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hAAAA_5555, "G2 MSCRATCH CSRRW       ");

    // CSRRS — set all odd bits (0x5555_5555)
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRS; CSR_Data_In=32'h5555_5555; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hFFFF_5555, "G2 MSCRATCH CSRRS       ");

    // CSRRC — clear all even bits (0xAAAA_AAAA)
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRC; CSR_Data_In=32'hAAAA_AAAA; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'h5555_5555, "G2 MSCRATCH CSRRC       ");

    // CSRRWI (immediate 5'b11111 = 0x1F)
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRWI; CSR_UImm_In=5'b11111; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'h0000_001F, "G2 MSCRATCH CSRRWI      ");

    // CSRRSI (immediate 5'b00001 = 0x01, set bit0 into 0x1F → 0x1F)
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRSI; CSR_UImm_In=5'b00001; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'h0000_001F, "G2 MSCRATCH CSRRSI      ");

    // CSRRCI (immediate 5'b01010 = 0x0A, clear bits1,3 from 0x1F → 0x15)
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRCI; CSR_UImm_In=5'b01010; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'h0000_0015, "G2 MSCRATCH CSRRCI      ");

    // Full 32-bit pattern
    csr_write(MSCRATCH, 32'hDEAD_BEEF);
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hDEAD_BEEF, "G2 MSCRATCH full 32-bit ");

    // =========================================================================
    // G3: Data_Wr_Mux NOP path — WrEn=0 must not modify register
    // =========================================================================
    $display("\n--- G3: WrEn=0 does not write ---");
    csr_write(MSCRATCH, 32'hCAFE_BABE);
    // Attempt write with WrEn=0
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRW; CSR_Data_In=32'h1234_5678; WrEn_In=0;
    @(posedge Clk_In); #1;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hCAFE_BABE, "G3 WrEn=0 no write      ");

    // Wrong address — write enabled but wrong CSR address
    CSR_Addr_In=MTVEC; CSR_Op_In=CSRRW; CSR_Data_In=32'hFFFF_FFFF; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hCAFE_BABE, "G3 Wrong addr no write  ");

    // =========================================================================
    // G4: MTVEC — write/read; direct/vectored; all 16 cause codes; exception
    // =========================================================================
    $display("\n--- G4: MTVEC ---");
    // Direct mode: base=0x1000_0000, mode=00
    csr_write(MTVEC, 32'h1000_0000);
    csr_read(MTVEC);
    check(tid, CSR_Data_Out, 32'h1000_0000, "G4 MTVEC direct write   ");

    // Trap_Addr_Out: exception (I_Or_E=0) → base regardless of mode
    I_Or_E_In=0; Cause_In=4'd7; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    check(tid, Trap_Addr_Out, 32'h1000_0000, "G4 direct exception addr");

    // Trap_Addr_Out: interrupt in direct mode → still base
    I_Or_E_In=1; Cause_In=4'd11; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    check(tid, Trap_Addr_Out, 32'h1000_0000, "G4 direct int addr      ");

    // Switch to vectored mode: mode=01
    csr_write(MTVEC, 32'h1000_0001);
    // Exception in vectored mode → still base
    I_Or_E_In=0; Cause_In=4'd3; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    check(tid, Trap_Addr_Out, 32'h1000_0000, "G4 vec exception→base   ");

    // All 16 interrupt causes in vectored mode
    begin : mtvec_loop
      integer c;
      reg [31:0] exp_addr;
      for (c=0; c<16; c=c+1) begin
        I_Or_E_In=1; Cause_In=c[3:0]; Set_Cause_In=1;
        @(posedge Clk_In); #1; Set_Cause_In=0;
        exp_addr = 32'h1000_0000 + (c*4);
        if (Trap_Addr_Out === exp_addr) begin
          $display("PASS [%0d] G4 vec cause=%0d addr=0x%08h", tid, c, Trap_Addr_Out);
          pass_count = pass_count + 1;
        end else begin
          $display("FAIL [%0d] G4 vec cause=%0d got=0x%08h exp=0x%08h",
                   tid, c, Trap_Addr_Out, exp_addr);
          fail_count = fail_count + 1;
        end
        tid = tid + 1;
      end
    end

    // =========================================================================
    // G5: MIE — bit isolation, non-implemented bits stay zero
    // =========================================================================
    $display("\n--- G5: MIE ---");
    // MEIE only
    csr_write(MIE_A, 32'h0000_0800);
    csr_read(MIE_A);
    check1(tid, CSR_Data_Out[11], 1'b1, "G5 MEIE only            ");
    check1(tid, CSR_Data_Out[7],  1'b0, "G5 MTIE=0 when MEIE set ");
    check1(tid, CSR_Data_Out[3],  1'b0, "G5 MSIE=0 when MEIE set ");
    check1(tid, MEIE_Out, 1'b1,         "G5 MEIE_Out             ");
    check1(tid, MTIE_Out, 1'b0,         "G5 MTIE_Out=0           ");
    check1(tid, MSIE_Out, 1'b0,         "G5 MSIE_Out=0           ");

    // MTIE only
    csr_write(MIE_A, 32'h0000_0080);
    csr_read(MIE_A);
    check1(tid, CSR_Data_Out[11], 1'b0, "G5 MEIE=0 MTIE only     ");
    check1(tid, CSR_Data_Out[7],  1'b1, "G5 MTIE only            ");
    check1(tid, CSR_Data_Out[3],  1'b0, "G5 MSIE=0 MTIE only     ");

    // MSIE only
    csr_write(MIE_A, 32'h0000_0008);
    csr_read(MIE_A);
    check1(tid, CSR_Data_Out[3],  1'b1, "G5 MSIE only            ");
    check1(tid, MSIE_Out, 1'b1,         "G5 MSIE_Out             ");

    // Writing non-implemented bits (all ones) — only 11,7,3 should stick
    csr_write(MIE_A, 32'hFFFF_FFFF);
    csr_read(MIE_A);
    check(tid, CSR_Data_Out, 32'h0000_0888, "G5 MIE non-impl=0       ");

    // Clear all
    csr_write(MIE_A, 32'h0);
    check1(tid, MEIE_Out, 1'b0, "G5 MEIE cleared         ");
    check1(tid, MTIE_Out, 1'b0, "G5 MTIE cleared         ");
    check1(tid, MSIE_Out, 1'b0, "G5 MSIE cleared         ");

    // =========================================================================
    // G6: MSTATUS — write MIE/MPIE; MIE_Clear/MIE_Set; non-impl bits
    // =========================================================================
    $display("\n--- G6: MSTATUS ---");
    // Set MIE=1, MPIE=1 → 0x88 in data; MPP stays 11 → full read = 0x1888
    csr_write(MSTATUS, 32'h0000_0088);
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out, 32'h0000_1888, "G6 MSTATUS write MIE+MPIE");
    check1(tid, MIE_Out, 1'b1,              "G6 MIE_Out after write  ");

    // MIE_Clear: MPIE←MIE(1), MIE←0
    MIE_Clear_In=1; @(posedge Clk_In); #1; MIE_Clear_In=0;
    csr_read(MSTATUS);
    check1(tid, CSR_Data_Out[3], 1'b0, "G6 MIE=0 after Clear    ");
    check1(tid, CSR_Data_Out[7], 1'b1, "G6 MPIE=1 after Clear   ");
    check1(tid, MIE_Out, 1'b0,         "G6 MIE_Out=0 Clear      ");

    // MIE_Set: MIE←MPIE(1), MPIE←1
    MIE_Set_In=1; @(posedge Clk_In); #1; MIE_Set_In=0;
    csr_read(MSTATUS);
    check1(tid, CSR_Data_Out[3], 1'b1, "G6 MIE=1 after Set      ");
    check1(tid, CSR_Data_Out[7], 1'b1, "G6 MPIE=1 after Set     ");
    check1(tid, MIE_Out, 1'b1,         "G6 MIE_Out=1 Set        ");

    // MIE_Clear then Set with MIE=0 initially (MPIE was 0)
    csr_write(MSTATUS, 32'h0000_0008); // MIE=1, MPIE=0
    MIE_Clear_In=1; @(posedge Clk_In); #1; MIE_Clear_In=0;
    // Now MIE=0, MPIE=1 (saved from MIE=1)
    csr_read(MSTATUS);
    check1(tid, CSR_Data_Out[3], 1'b0, "G6 MIE=0 after 2nd Clear");
    check1(tid, CSR_Data_Out[7], 1'b1, "G6 MPIE=1 saved MIE     ");

    // Non-implemented bits must not stick (write 0xFFFF_FFFF)
    csr_write(MSTATUS, 32'hFFFF_FFFF);
    csr_read(MSTATUS);
    // only bits 3(MIE), 7(MPIE), 12:11(MPP) are implemented
    check(tid, CSR_Data_Out, 32'h0000_1888, "G6 MSTATUS non-impl=0   ");

    // =========================================================================
    // G7: MEPC — Set_EPC priority; word-alignment; CSR write alignment
    // =========================================================================
    $display("\n--- G7: MEPC ---");
    // Set_EPC latches PC (no alignment required on trap)
    PC_In=32'hABCD_1234; Set_EPC_In=1;
    @(posedge Clk_In); #1; Set_EPC_In=0;
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out,  32'hABCD_1234, "G7 MEPC Set_EPC         ");
    check(tid, EPC_Out,       32'hABCD_1234, "G7 EPC_Out wired        ");

    // CSR write aligns to word: bits[1:0] forced to 00
    csr_write(MEPC_A, 32'hDEAD_BEEF);
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'hDEAD_BEEC, "G7 MEPC word-aligned    ");
    check(tid, EPC_Out,      32'hDEAD_BEEC, "G7 EPC_Out aligned      ");

    // Set_EPC has priority over a CSR write on same cycle
    // (Set_EPC fires first per priority order in RTL)
    PC_In=32'h1111_1110; Set_EPC_In=1;
    CSR_Addr_In=MEPC_A; CSR_Op_In=CSRRW; CSR_Data_In=32'h9999_9998; WrEn_In=1;
    @(posedge Clk_In); #1; Set_EPC_In=0; WrEn_In=0;
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h1111_1110, "G7 Set_EPC prio>CSRwrt  ");

    // =========================================================================
    // G8: MCAUSE — all paths and fields
    // =========================================================================
    $display("\n--- G8: MCAUSE ---");
    // Hardware exception (I_Or_E=0)
    I_Or_E_In=0; Cause_In=4'h5; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h0000_0005, "G8 exception cause 5    ");

    // Hardware interrupt (I_Or_E=1), cause=3
    I_Or_E_In=1; Cause_In=4'h3; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h8000_0003, "G8 interrupt cause 3    ");

    // Set_Cause zeros Cause_Rem — write 0x7FFF_FFFF first via SW to populate Rem
    csr_write(MCAUSE_A, 32'h7FFF_FFFF);
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h7FFF_FFFF, "G8 SW write full field  ");
    // Now hardware trap clears Cause_Rem
    I_Or_E_In=0; Cause_In=4'h2; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h0000_0002, "G8 hw trap clears Rem   ");

    // All 16 exception codes
    begin : cause_loop
      integer c;
      for (c=0; c<16; c=c+1) begin
        I_Or_E_In=0; Cause_In=c[3:0]; Set_Cause_In=1;
        @(posedge Clk_In); #1; Set_Cause_In=0;
        csr_read(MCAUSE_A);
        if (CSR_Data_Out === c[31:0]) begin
          $display("PASS [%0d] G8 exc cause=%0d", tid, c);
          pass_count=pass_count+1;
        end else begin
          $display("FAIL [%0d] G8 exc cause=%0d got=0x%08h exp=0x%08h",
                   tid, c, CSR_Data_Out, c[31:0]);
          fail_count=fail_count+1;
        end
        tid=tid+1;
      end
    end

    // =========================================================================
    // G9: MTVAL — all three paths
    // =========================================================================
    $display("\n--- G9: MTVAL ---");
    // Misaligned exc: Set_Cause + Misaligned=1 → stores Imm_Added
    Imm_Added_In=32'hBEEF_CAFE; Misaligned_Exc_In=1;
    I_Or_E_In=0; Cause_In=4'h0; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0; Misaligned_Exc_In=0;
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'hBEEF_CAFE, "G9 MTVAL misaligned     ");

    // Non-misaligned trap: Set_Cause + Misaligned=0 → zeros MTVAL
    Imm_Added_In=32'h1234_5678; Misaligned_Exc_In=0;
    I_Or_E_In=1; Cause_In=4'hB; Set_Cause_In=1;
    @(posedge Clk_In); #1; Set_Cause_In=0;
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'h0000_0000, "G9 MTVAL non-mis=0      ");

    // SW write to MTVAL
    csr_write(MTVAL_A, 32'hDEAD_1234);
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'hDEAD_1234, "G9 MTVAL SW write       ");

    // Another trap clears it (non-misaligned)
    Set_Cause_In=1; @(posedge Clk_In); #1; Set_Cause_In=0;
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'h0, "G9 MTVAL cleared by trap");

    // =========================================================================
    // G10: MIP — all 8 combinations of EIrq/TIrq/SIrq; MIP_Reg readback
    // =========================================================================
    $display("\n--- G10: MIP all irq combinations ---");
    begin : mip_loop
      integer i;
      reg [2:0] irqs;
      reg [31:0] exp_mip;
      for (i=0; i<8; i=i+1) begin
        irqs = i[2:0];
        EIrq_In=irqs[2]; TIrq_In=irqs[1]; SIrq_In=irqs[0];
        @(posedge Clk_In); #1;
        // Expected: MEIP=bit11, MTIP=bit7, MSIP=bit3
        exp_mip = {20'b0, irqs[2], 3'b0, irqs[1], 3'b0, irqs[0], 3'b0};
        csr_read(MIP_A);
        if (CSR_Data_Out === exp_mip) begin
          $display("PASS [%0d] G10 MIP irqs=%03b : 0x%08h", tid, irqs, CSR_Data_Out);
          pass_count=pass_count+1;
        end else begin
          $display("FAIL [%0d] G10 MIP irqs=%03b got=0x%08h exp=0x%08h",
                   tid, irqs, CSR_Data_Out, exp_mip);
          fail_count=fail_count+1;
        end
        tid=tid+1;
      end
    end
    EIrq_In=0; TIrq_In=0; SIrq_In=0;
    // MIP write-ignored
    CSR_Addr_In=MIP_A; CSR_Op_In=CSRRW; CSR_Data_In=32'hFFFF_FFFF; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MIP_A);
    check(tid, CSR_Data_Out, 32'h0, "G10 MIP write ignored   ");
    // Reset clears MIP
    EIrq_In=1; TIrq_In=1; SIrq_In=1;
    @(posedge Clk_In); #1;
    do_reset;
    check1(tid, MEIP_Out, 1'b0, "G10 MEIP=0 after reset  ");
    check1(tid, MTIP_Out, 1'b0, "G10 MTIP=0 after reset  ");
    check1(tid, MSIP_Out, 1'b0, "G10 MSIP=0 after reset  ");

    // =========================================================================
    // G11: MCOUNTINHIBIT — CY(bit2)/IR(bit0) independence; non-impl bits=0
    // =========================================================================
    $display("\n--- G11: MCOUNTINHIBIT ---");
    // Write both set
    csr_write(MCOUNTINHIB, 32'h0000_0005); // CY=bit2=1, IR=bit0=1
    csr_read(MCOUNTINHIB);
    check(tid, CSR_Data_Out, 32'h0000_0005, "G11 CY+IR inhibit       ");

    // Write non-implemented bits — only CY and IR bits should persist
    csr_write(MCOUNTINHIB, 32'hFFFF_FFFF);
    csr_read(MCOUNTINHIB);
    // Only bit2(CY) and bit0(IR) persist per Machine_Counter_Setup
    check(tid, CSR_Data_Out, 32'h0000_0005, "G11 non-impl bits=0     ");

    // CY only: write bit2 of Data_Wr -> CY=1, IR=0
    // Readback: {29'b0, IR=0, 1'b0, CY=1} = 0x1 -> bit[0]=CY=1, bit[2]=IR=0
    csr_write(MCOUNTINHIB, 32'h0000_0004);
    csr_read(MCOUNTINHIB);
    check(tid, CSR_Data_Out[0], 1'b1, "G11 CY rdback bit0=1    ");
    check(tid, CSR_Data_Out[2], 1'b0, "G11 IR rdback bit2=0    ");

    // IR only: write bit0 of Data_Wr -> IR=1, CY=0
    // Readback: {29'b0, IR=1, 1'b0, CY=0} = 0x4 -> bit[2]=IR=1, bit[0]=CY=0
    csr_write(MCOUNTINHIB, 32'h0000_0001);
    csr_read(MCOUNTINHIB);
    check(tid, CSR_Data_Out[0], 1'b0, "G11 CY rdback bit0=0    ");
    check(tid, CSR_Data_Out[2], 1'b1, "G11 IR rdback bit2=1    ");
    csr_write(MCOUNTINHIB, 32'h0); // clear both

    // =========================================================================
    // G12: MCYCLE — free-run; freeze; SW write low/high; inhibit then re-enable
    // =========================================================================
    $display("\n--- G12: MCYCLE ---");
    do_reset;
    // One clock so registers pipeline-settle; MCYCLE becomes 1
    @(posedge Clk_In); #1;

    // Free-run: after 9 more clocks MCYCLE = 1+9 = 10
    repeat(9) @(posedge Clk_In); #1;
    csr_read(MCYCLE_A);
    check(tid, CSR_Data_Out, 32'd10, "G12 MCYCLE free-run=10  ");

    // SW write to MCYCLE low half — counter still increments on write cycle
    // Writing 32'hFFFE: on that clock edge, counter = 0xFFFE + 1 = 0xFFFF
    csr_write(MCYCLE_A, 32'hFFFF_FFFE);
    csr_read(MCYCLE_A);
    check(tid, CSR_Data_Out, 32'hFFFF_FFFF, "G12 MCYCLE SW write+inc ");

    // After one more free-run clock it wraps
    @(posedge Clk_In); #1;
    csr_read(MCYCLE_A);
    check(tid, CSR_Data_Out, 32'h0000_0000, "G12 MCYCLE 32-bit wrap  ");
    csr_read(MCYCLEH_A);
    check(tid, CSR_Data_Out, 32'h0000_0001, "G12 MCYCLEH carry       ");

    // CY inhibit: write 0x4 (bit2)
    csr_write(MCOUNTINHIB, 32'h0000_0004);
    @(posedge Clk_In); #1; // settle
    csr_read(MCYCLE_A);
    begin : cy_inh2
      reg [31:0] snap;
      snap = CSR_Data_Out;
      repeat(4) @(posedge Clk_In); #1;
      csr_read(MCYCLE_A);
      check(tid, CSR_Data_Out, snap, "G12 CY frozen 4 cycles  ");
    end

    // Re-enable
    csr_write(MCOUNTINHIB, 32'h0);
    @(posedge Clk_In); #1;
    csr_read(MCYCLE_A);
    begin : cy_resume
      reg [31:0] snap2;
      snap2 = CSR_Data_Out;
      repeat(3) @(posedge Clk_In); #1;
      csr_read(MCYCLE_A);
      check(tid, CSR_Data_Out, snap2 + 3, "G12 MCYCLE resumes      ");
    end

    // SW write to high half
    csr_write(MCYCLEH_A, 32'hABCD_0000);
    csr_read(MCYCLEH_A);
    check(tid, CSR_Data_Out, 32'hABCD_0000, "G12 MCYCLEH SW write    ");

    // =========================================================================
    // G13: MINSTRET — pulse counting; IR inhibit; multi-pulse
    // =========================================================================
    $display("\n--- G13: MINSTRET ---");
    do_reset;
    csr_read(MINSTRET_A);
    begin : ir_base
      reg [31:0] base_ir;
      base_ir = CSR_Data_Out;

      // Single pulse
      Instret_Inc_In=1; @(posedge Clk_In); #1; Instret_Inc_In=0;
      @(posedge Clk_In); #1;
      csr_read(MINSTRET_A);
      check(tid, CSR_Data_Out, base_ir+1, "G13 MINSTRET 1 pulse    ");

      // 5 consecutive pulses
      repeat(5) begin
        Instret_Inc_In=1; @(posedge Clk_In); #1;
      end
      Instret_Inc_In=0; @(posedge Clk_In); #1;
      csr_read(MINSTRET_A);
      check(tid, CSR_Data_Out, base_ir+6, "G13 MINSTRET 5 pulses   ");

      // IR inhibit — pulses should not count
      csr_write(MCOUNTINHIB, 32'h0000_0001); // IR=bit0
      @(posedge Clk_In); #1;
      csr_read(MINSTRET_A);
      begin : ir_inh
        reg [31:0] snap_ir;
        snap_ir = CSR_Data_Out;
        repeat(3) begin
          Instret_Inc_In=1; @(posedge Clk_In); #1;
        end
        Instret_Inc_In=0; @(posedge Clk_In); #1;
        csr_read(MINSTRET_A);
        check(tid, CSR_Data_Out, snap_ir, "G13 IR inhibit no count ");
      end
      csr_write(MCOUNTINHIB, 32'h0);
    end

    // =========================================================================
    // G14: MTIME shadow — immediate update, high word, full 64-bit
    // =========================================================================
    $display("\n--- G14: MTIME ---");
    RTC_In = 64'h0000_0001_0000_0000;
    @(posedge Clk_In); #1;
    csr_read(TIME_A);   check(tid, CSR_Data_Out, 32'h0000_0000, "G14 TIME low=0          ");
    csr_read(TIMEH_A);  check(tid, CSR_Data_Out, 32'h0000_0001, "G14 TIME high=1         ");

    RTC_In = 64'hFFFF_FFFF_FFFF_FFFF;
    @(posedge Clk_In); #1;
    csr_read(TIME_A);   check(tid, CSR_Data_Out, 32'hFFFF_FFFF, "G14 TIME low=FFFFFFFF   ");
    csr_read(TIMEH_A);  check(tid, CSR_Data_Out, 32'hFFFF_FFFF, "G14 TIME high=FFFFFFFF  ");

    RTC_In = 64'h0;
    @(posedge Clk_In); #1;
    csr_read(TIME_A);   check(tid, CSR_Data_Out, 32'h0, "G14 TIME cleared        ");

    // =========================================================================
    // G15: Counter shadows — CYCLE/H == MCYCLE/H; INSTRET/H == MINSTRET/H
    // =========================================================================
    $display("\n--- G15: Unprivileged counter shadows ---");
    csr_read(MCYCLE_A);
    begin : shad_cyc
      reg [31:0] mc; mc = CSR_Data_Out;
      csr_read(CYCLE_A);
      check(tid, CSR_Data_Out, mc, "G15 CYCLE==MCYCLE       ");
    end
    csr_read(MCYCLEH_A);
    begin : shad_cych
      reg [31:0] mch; mch = CSR_Data_Out;
      csr_read(CYCLEH_A);
      check(tid, CSR_Data_Out, mch, "G15 CYCLEH==MCYCLEH     ");
    end
    csr_read(MINSTRET_A);
    begin : shad_ir
      reg [31:0] mi; mi = CSR_Data_Out;
      csr_read(INSTRET_A);
      check(tid, CSR_Data_Out, mi, "G15 INSTRET==MINSTRET   ");
    end
    csr_read(MINSTRETH_A);
    begin : shad_irh
      reg [31:0] mih; mih = CSR_Data_Out;
      csr_read(INSTRETH_A);
      check(tid, CSR_Data_Out, mih, "G15 INSTRETH==MINSTRETH ");
    end

    // =========================================================================
    // G16: CSR_Data_Out mux — invalid address returns 0
    // =========================================================================
    $display("\n--- G16: Invalid CSR address → 0 ---");
    csr_read(12'hFFF);
    check(tid, CSR_Data_Out, 32'h0, "G16 addr=FFF → 0        ");
    csr_read(12'h000);
    check(tid, CSR_Data_Out, 32'h0, "G16 addr=000 → 0        ");
    csr_read(12'h302); // medeleg — not implemented
    check(tid, CSR_Data_Out, 32'h0, "G16 MEDELEG(unimpl)→0   ");

    // =========================================================================
    // G17: MPIE chaining — double-nested trap simulation
    // =========================================================================
    $display("\n--- G17: MPIE save/restore chaining ---");
    do_reset;
    // Start with MIE=1, MPIE=0
    csr_write(MSTATUS, 32'h0000_0008); // MIE=1 MPIE=0
    // First trap entry: MIE_Clear → MPIE=1, MIE=0
    MIE_Clear_In=1; @(posedge Clk_In); #1; MIE_Clear_In=0;
    csr_read(MSTATUS);
    check1(tid, CSR_Data_Out[3], 1'b0, "G17 MIE=0 1st trap      ");
    check1(tid, CSR_Data_Out[7], 1'b1, "G17 MPIE=1 saved MIE    ");
    // MRET: MIE←MPIE(1), MPIE←1
    MIE_Set_In=1; @(posedge Clk_In); #1; MIE_Set_In=0;
    csr_read(MSTATUS);
    check1(tid, CSR_Data_Out[3], 1'b1, "G17 MIE=1 after MRET    ");
    check1(tid, CSR_Data_Out[7], 1'b1, "G17 MPIE=1 after MRET   ");
    // Second MRET from MPIE=1 again works
    MIE_Set_In=1; @(posedge Clk_In); #1; MIE_Set_In=0;
    csr_read(MSTATUS);
    check1(tid, CSR_Data_Out[3], 1'b1, "G17 MIE=1 2nd MRET      ");

    // =========================================================================
    // G18: Full trap sequence
    // =========================================================================
    $display("\n--- G18: Full trap sequence ---");
    do_reset;
    // Setup
    csr_write(MTVEC,   32'h8000_0000); // direct mode
    csr_write(MIE_A,   32'h0000_0888); // all enables
    csr_write(MSTATUS, 32'h0000_0008); // MIE=1

    // Trap entry
    PC_In=32'h0000_1000; Set_EPC_In=1;
    I_Or_E_In=0; Cause_In=4'd8; Set_Cause_In=1; // ecall from M-mode
    Imm_Added_In=32'h0; Misaligned_Exc_In=0;
    MIE_Clear_In=1;
    @(posedge Clk_In); #1;
    Set_EPC_In=0; Set_Cause_In=0; MIE_Clear_In=0;

    // Verify trap state
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h0000_1000, "G18 MEPC on trap entry  ");
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h0000_0008, "G18 MCAUSE ecall        ");
    check(tid, Trap_Addr_Out, 32'h8000_0000, "G18 Trap_Addr direct    ");
    check1(tid, MIE_Out, 1'b0,               "G18 MIE=0 during trap   ");

    // MRET
    MIE_Set_In=1; @(posedge Clk_In); #1; MIE_Set_In=0;
    check1(tid, MIE_Out, 1'b1, "G18 MIE=1 after MRET    ");
    check(tid, EPC_Out, 32'h0000_1000, "G18 EPC intact after ret");

    // =========================================================================
    // G19: MEPC CSR write alignment — various unaligned values
    // =========================================================================
    $display("\n--- G19: MEPC word-alignment mask ---");
    csr_write(MEPC_A, 32'hFFFF_FFFF);
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'hFFFF_FFFC, "G19 MEPC bits[1:0]=0    ");
    csr_write(MEPC_A, 32'h0000_0001);
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h0000_0000, "G19 MEPC aligned 1→0    ");
    csr_write(MEPC_A, 32'h0000_0002);
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h0000_0000, "G19 MEPC aligned 2→0    ");
    csr_write(MEPC_A, 32'h0000_0003);
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h0000_0000, "G19 MEPC aligned 3→0    ");

    // =========================================================================
    // G20: MCYCLE and MINSTRET both CY+IR inhibited simultaneously
    // =========================================================================
    $display("\n--- G20: Simultaneous CY+IR inhibit ---");
    do_reset;
    csr_write(MCOUNTINHIB, 32'h0000_0005); // CY+IR
    @(posedge Clk_In); #1;
    csr_read(MCYCLE_A);
    begin : simul_inh
      reg [31:0] snap_cy, snap_ir;
      snap_cy = CSR_Data_Out;
      csr_read(MINSTRET_A); snap_ir = CSR_Data_Out;
      // pulse instret and wait cycles
      repeat(5) begin Instret_Inc_In=1; @(posedge Clk_In); #1; end
      Instret_Inc_In=0;
      repeat(5) @(posedge Clk_In); #1;
      csr_read(MCYCLE_A);
      check(tid, CSR_Data_Out, snap_cy, "G20 CY frozen simul     ");
      csr_read(MINSTRET_A);
      check(tid, CSR_Data_Out, snap_ir, "G20 IR frozen simul     ");
    end
    csr_write(MCOUNTINHIB, 32'h0);

    // =========================================================================
    // G21: CSRRS/CSRRC with all-zeros mask — NOP, CSR unchanged
    // =========================================================================
    $display("\n--- G21: CSRRS/CSRRC zero-mask NOP ---");
    csr_write(MSCRATCH, 32'hA5A5_5A5A);
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRS; CSR_Data_In=32'h0; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hA5A5_5A5A, "G21 CSRRS zero-mask NOP ");
    CSR_Addr_In=MSCRATCH; CSR_Op_In=CSRRC; CSR_Data_In=32'h0; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MSCRATCH);
    check(tid, CSR_Data_Out, 32'hA5A5_5A5A, "G21 CSRRC zero-mask NOP ");

    // =========================================================================
    // G22: Back-to-back resets — counter zeroed each time
    // =========================================================================
    $display("\n--- G22: Back-to-back resets ---");
    // Let counter run
    repeat(20) @(posedge Clk_In); #1;
    csr_read(MCYCLE_A);
    check(tid, (CSR_Data_Out > 0) ? 32'h1 : 32'h0, 32'h1, "G22 cycle>0 pre-reset   ");
    do_reset;
    csr_read(MCYCLE_A);
    check(tid, CSR_Data_Out, 32'h0, "G22 cycle=0 after reset ");
    do_reset;
    // Tick one clock so MSTATUS register settles after reset
    @(posedge Clk_In); #1;
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out, MSTATUS_RST, "G22 MSTATUS OK 2nd rst  ");

    // =========================================================================
    // G23: MTVEC CSRRS / CSRRC on mode bits
    // =========================================================================
    $display("\n--- G23: MTVEC CSRRS/CSRRC ---");
    csr_write(MTVEC, 32'h2000_0000); // direct mode base
    // Set mode bit0 via CSRRS
    CSR_Addr_In=MTVEC; CSR_Op_In=CSRRS; CSR_Data_In=32'h0000_0001; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MTVEC);
    check(tid, CSR_Data_Out, 32'h2000_0001, "G23 MTVEC CSRRS mode=1  ");
    // Clear mode via CSRRC
    CSR_Addr_In=MTVEC; CSR_Op_In=CSRRC; CSR_Data_In=32'h0000_0001; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    csr_read(MTVEC);
    check(tid, CSR_Data_Out, 32'h2000_0000, "G23 MTVEC CSRRC mode=0  ");

    // =========================================================================
    // G24: MIE CSRRS / CSRRC individual bits
    // =========================================================================
    $display("\n--- G24: MIE CSRRS/CSRRC ---");
    csr_write(MIE_A, 32'h0);
    // Set MEIE via CSRRS
    CSR_Addr_In=MIE_A; CSR_Op_In=CSRRS; CSR_Data_In=32'h0000_0800; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    check1(tid, MEIE_Out, 1'b1, "G24 CSRRS MEIE set      ");
    // Set MTIE via CSRRS
    CSR_Addr_In=MIE_A; CSR_Op_In=CSRRS; CSR_Data_In=32'h0000_0080; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    check1(tid, MTIE_Out, 1'b1, "G24 CSRRS MTIE set      ");
    // Clear MEIE via CSRRC
    CSR_Addr_In=MIE_A; CSR_Op_In=CSRRC; CSR_Data_In=32'h0000_0800; WrEn_In=1;
    @(posedge Clk_In); #1; WrEn_In=0;
    check1(tid, MEIE_Out, 1'b0, "G24 CSRRC MEIE cleared  ");
    check1(tid, MTIE_Out, 1'b1, "G24 MTIE intact         ");

    // =========================================================================
    // G25: Interrupt pending + enable = readback consistency
    // =========================================================================
    $display("\n--- G25: MIP readback consistency ---");
    EIrq_In=1; TIrq_In=1; SIrq_In=1;
    @(posedge Clk_In); #1;
    csr_read(MIP_A);
    check(tid, CSR_Data_Out, 32'h0000_0888, "G25 MIP all pending     ");
    check1(tid, MEIP_Out, 1'b1, "G25 MEIP_Out            ");
    check1(tid, MTIP_Out, 1'b1, "G25 MTIP_Out            ");
    check1(tid, MSIP_Out, 1'b1, "G25 MSIP_Out            ");
    EIrq_In=0; TIrq_In=0; SIrq_In=0;
    @(posedge Clk_In); #1;
    csr_read(MIP_A);
    check(tid, CSR_Data_Out, 32'h0, "G25 MIP all clear       ");

    // =========================================================================
    // G26: MCYCLE SW write then free-run — verify continuity
    // =========================================================================
    $display("\n--- G26: MCYCLE SW write then free-run ---");
    do_reset;
    csr_write(MCYCLE_A, 32'h0000_0064); // seed = 100, +1 on write = 101
    @(posedge Clk_In); #1;              // 102
    @(posedge Clk_In); #1;              // 103
    csr_read(MCYCLE_A);
    check(tid, CSR_Data_Out, 32'd103, "G26 MCYCLE seed+run     ");


    // =========================================================================
    // G27: MINSTRETH SW write while counter running
    //      Both MINSTRET/H halves must be independently writable.
    //      RTL: writing MINSTRETH replaces upper 32 bits; lower stays.
    //      Writing MINSTRET replaces lower 32 bits; upper stays.
    // =========================================================================
    $display("\n--- G27: MINSTRETH SW write ---");
    do_reset;
    // Freeze CY only, let instret count freely
    csr_write(MCOUNTINHIB, 32'h0000_0004);
    @(posedge Clk_In); #1; // inhibit settles

    // Retire 5 instructions to get MINSTRET > 0
    begin : g27_pulse
      integer p;
      for (p = 0; p < 5; p = p + 1) begin
        Instret_Inc_In = 1; @(posedge Clk_In); #1; Instret_Inc_In = 0;
      end
    end
    @(posedge Clk_In); #1;
    csr_read(MINSTRET_A);
    check(tid, CSR_Data_Out, 32'h5, "G27 MINSTRET=5 baseline ");

    // Write MINSTRETH to a known value while counter is running
    // IR not inhibited -> write = written_value + Instret_Inc (=0) = value
    csr_write(MINSTRETH_A, 32'hABCD_0000);
    csr_read(MINSTRETH_A);
    check(tid, CSR_Data_Out, 32'hABCD_0000, "G27 MINSTRETH SW write  ");

    // Lower half must be unaffected by upper write
    csr_read(MINSTRET_A);
    check(tid, (CSR_Data_Out >= 32'h5) ? 32'h1 : 32'h0, 32'h1,
          "G27 MINSTRET low intact ");

    // Write MINSTRET lower half with IR not inhibited (Inc=0): value exact
    csr_write(MINSTRET_A, 32'h0000_1234);
    csr_read(MINSTRET_A);
    check(tid, CSR_Data_Out, 32'h0000_1234, "G27 MINSTRET low SW wr  ");

    // Upper half must still be ABCD_0000
    csr_read(MINSTRETH_A);
    check(tid, CSR_Data_Out, 32'hABCD_0000, "G27 MINSTRETH preserved ");

    // Now retire one more instruction — lower half should increment
    Instret_Inc_In = 1; @(posedge Clk_In); #1; Instret_Inc_In = 0;
    @(posedge Clk_In); #1;
    csr_read(MINSTRET_A);
    check(tid, CSR_Data_Out, 32'h0000_1235, "G27 MINSTRET inc after  ");

    csr_write(MCOUNTINHIB, 32'h0); // re-enable all

    // =========================================================================
    // G28: MIE_Clear when MIE is already 0
    //      MPIE must save the old MIE value (0), MIE must stay 0.
    //      This models a nested trap into an already-disabled state.
    // =========================================================================
    $display("\n--- G28: MIE_Clear when MIE=0 ---");
    do_reset;

    // After reset: MIE=0, MPIE=1 (per MStatus_Reg reset)
    // Write MSTATUS so MIE=0, MPIE=0 explicitly
    csr_write(MSTATUS, 32'h0000_0000); // MIE=0, MPIE=0
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0, "G28 MIE=0 before clear  ");
    check(tid, CSR_Data_Out[7], 1'b0, "G28 MPIE=0 before clear ");

    // MIE_Clear: MPIE <= MIE (=0), MIE <= 0 (already 0)
    MIE_Clear_In = 1; @(posedge Clk_In); #1; MIE_Clear_In = 0;
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0, "G28 MIE=0 after clear   ");
    check(tid, CSR_Data_Out[7], 1'b0, "G28 MPIE=0 saved MIE=0  ");
    check1(tid, MIE_Out, 1'b0,        "G28 MIE_Out=0           ");

    // MIE_Set now: MIE <= MPIE (=0), MPIE <= 1
    MIE_Set_In = 1; @(posedge Clk_In); #1; MIE_Set_In = 0;
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0, "G28 MIE=0 after MRET    ");
    check(tid, CSR_Data_Out[7], 1'b1, "G28 MPIE=1 after MRET   ");
    check1(tid, MIE_Out, 1'b0,        "G28 MIE_Out=0 after MRET");

    // Second MIE_Clear with MPIE=1 now: MPIE<=MIE(0), MIE<=0
    MIE_Clear_In = 1; @(posedge Clk_In); #1; MIE_Clear_In = 0;
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0, "G28 MIE=0 2nd clear     ");
    check(tid, CSR_Data_Out[7], 1'b0, "G28 MPIE=0 saved MIE=0  ");

    // Now set MIE=1 via CSR write, then clear -> MPIE should save 1
    csr_write(MSTATUS, 32'h0000_0088); // MIE=1, MPIE=1
    MIE_Clear_In = 1; @(posedge Clk_In); #1; MIE_Clear_In = 0;
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0, "G28 MIE=0 clear from 1  ");
    check(tid, CSR_Data_Out[7], 1'b1, "G28 MPIE=1 saved MIE=1  ");

    // =========================================================================
    // G29: Trap signal deassert — Set_EPC/Set_Cause/MIE_Clear all drop
    //      simultaneously. No phantom latching on next cycle.
    //      Verifies that the RTL only latches on the rising-edge where
    //      signals are asserted, not on subsequent cycles.
    // =========================================================================
    $display("\n--- G29: Trap signals deassert cleanly ---");
    do_reset;
    @(posedge Clk_In); #1;

    csr_write(MTVEC, 32'h4000_0000); // direct mode base
    csr_write(MSTATUS, 32'h0000_0088); // MIE=1

    // --- Trap 1: assert all trap signals for exactly one cycle ---
    PC_In        = 32'hAAAA_0000;
    I_Or_E_In    = 0;
    Cause_In     = 4'h5;
    Imm_Added_In = 32'hBBBB_0000;
    Misaligned_Exc_In = 1;
    Set_EPC_In   = 1;
    Set_Cause_In = 1;
    MIE_Clear_In = 1;
    @(posedge Clk_In); #1;
    // Deassert ALL trap signals simultaneously
    Set_EPC_In   = 0;
    Set_Cause_In = 0;
    MIE_Clear_In = 0;
    Misaligned_Exc_In = 0;

    // Verify trap was latched correctly
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'hAAAA_0000, "G29 MEPC latched trap1  ");
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h0000_0005, "G29 MCAUSE latched trap1");
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'hBBBB_0000, "G29 MTVAL latched trap1 ");
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0,       "G29 MIE=0 after trap1   ");

    // --- Clock several idle cycles with different PC/Cause on inputs
    //     but all trap signals deasserted — nothing should change ---
    PC_In     = 32'hDEAD_BEEF; // different PC on input
    Cause_In  = 4'hF;          // different cause on input
    Imm_Added_In = 32'hFFFF_FFFF;
    Misaligned_Exc_In = 1;     // misaligned asserted but Set_Cause=0
    @(posedge Clk_In); #1;
    @(posedge Clk_In); #1;
    @(posedge Clk_In); #1;
    Misaligned_Exc_In = 0;

    // Verify MEPC/MCAUSE/MTVAL are unchanged (no phantom latch)
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'hAAAA_0000, "G29 MEPC unchanged idle ");
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h0000_0005, "G29 MCAUSE unchanged    ");
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'hBBBB_0000, "G29 MTVAL unchanged     ");
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[3], 1'b0,       "G29 MIE still 0 idle    ");

    // --- Trap 2: assert again with completely different values ---
    PC_In        = 32'h1234_5678;
    I_Or_E_In    = 1;           // interrupt this time
    Cause_In     = 4'hB;        // cause 11 = external interrupt
    Misaligned_Exc_In = 0;      // not misaligned — MTVAL should be zeroed
    Set_EPC_In   = 1;
    Set_Cause_In = 1;
    MIE_Clear_In = 1;
    @(posedge Clk_In); #1;
    Set_EPC_In = 0; Set_Cause_In = 0; MIE_Clear_In = 0;

    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h1234_5678, "G29 MEPC latched trap2  ");
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h8000_000B, "G29 MCAUSE int trap2    ");
    csr_read(MTVAL_A);
    check(tid, CSR_Data_Out, 32'h0000_0000, "G29 MTVAL zeroed trap2  ");

    // --- Deassert and idle — still no phantom latch ---
    PC_In    = 32'hDEAD_0000;
    Cause_In = 4'h0;
    @(posedge Clk_In); #1;
    @(posedge Clk_In); #1;
    csr_read(MEPC_A);
    check(tid, CSR_Data_Out, 32'h1234_5678, "G29 MEPC stable idle2   ");
    csr_read(MCAUSE_A);
    check(tid, CSR_Data_Out, 32'h8000_000B, "G29 MCAUSE stable idle2 ");

    // --- Verify MIE state after two nested MIE_Clear pulses ---
    // State trace:
    //   csr_write(MSTATUS,0x88) -> MIE=1, MPIE=1
    //   Trap1 MIE_Clear         -> MPIE=1 (saved MIE=1), MIE=0
    //   Trap2 MIE_Clear         -> MPIE=0 (saved MIE=0), MIE=0
    // So at this point: MIE=0, MPIE=0.
    // MIE_Set (MRET): MIE<=MPIE(0)=0, MPIE<=1
    // MIE after MRET = 0 — this is correct RTL behavior for nested trap.
    MIE_Set_In = 1; @(posedge Clk_In); #1; MIE_Set_In = 0;
    check1(tid, MIE_Out, 1'b0,             "G29 MIE=0 MRET nested   ");
    csr_read(MSTATUS);
    check(tid, CSR_Data_Out[7], 1'b1,      "G29 MPIE=1 after MRET   ");

    // Idle clocks — MIE must stay 0 (no phantom set from deasserted MIE_Set)
    @(posedge Clk_In); #1;
    @(posedge Clk_In); #1;
    check1(tid, MIE_Out, 1'b0,             "G29 MIE stable no phset ");

    // Now use CSR write to force MIE=1, then verify MIE_Clear works once
    csr_write(MSTATUS, 32'h0000_0088); // MIE=1, MPIE=1
    check1(tid, MIE_Out, 1'b1,             "G29 MIE=1 via CSR write ");

    // MIE_Clear (single pulse): MPIE<=MIE(1), MIE<=0
    MIE_Clear_In = 1; @(posedge Clk_In); #1; MIE_Clear_In = 0;
    check1(tid, MIE_Out, 1'b0,             "G29 MIE=0 after clear   ");
    // Idle — MIE_Clear deasserted, MIE must stay 0 (no phantom clear)
    @(posedge Clk_In); #1;
    @(posedge Clk_In); #1;
    check1(tid, MIE_Out, 1'b0,             "G29 MIE stable no clear ");

    // MIE_Set (single pulse): MIE<=MPIE(1)=1, MPIE<=1
    MIE_Set_In = 1; @(posedge Clk_In); #1; MIE_Set_In = 0;
    check1(tid, MIE_Out, 1'b1,             "G29 MIE=1 after MRET    ");
    // Idle — MIE_Set deasserted, MIE must stay 1 (no phantom set)
    @(posedge Clk_In); #1;
    @(posedge Clk_In); #1;
    check1(tid, MIE_Out, 1'b1,             "G29 MIE stable no phclr ");

    // Reset all inputs
    PC_In = 32'h0; Cause_In = 4'h0; I_Or_E_In = 0;
    Imm_Added_In = 32'h0; Misaligned_Exc_In = 0;

    // =========================================================================
    // Summary
    // =========================================================================
    $display("\n==============================");
    $display(" TOTAL CHECKS : %0d", pass_count + fail_count);
    $display(" PASSED       : %0d", pass_count);
    $display(" FAILED       : %0d", fail_count);
    $display("==============================");
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule
/* verilator lint_on TIMESCALEMOD */
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on UNUSEDPARAM */
