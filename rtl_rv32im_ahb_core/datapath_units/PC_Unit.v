//! Program Counter Unit
//! Computes and registers the next PC on every rising clock edge.
//!
//! Enhanced from the base RV32I version to support machine-mode traps:
//!   - 4-way PC source mux driven by Machine_Control (PC_Src_In)
//!   - EPC return address input for MRET (PC_SRC_EPC)
//!   - Trap handler address input for trap entry (PC_SRC_TRAP)
//!   - Instruction-address misalignment detection on taken branches
//!
//! PC source encoding (matches Machine_Control PC_SRC_* localparams):
//!   2'b00 — BOOT:      jump to 32'h0 on reset
//!   2'b01 — EPC:       return to mepc on MRET
//!   2'b10 — TRAP:      jump to mtvec trap handler address
//!   2'b11 — NEXT:      normal flow — branch target or PC+4
//!
//! AHB Instruction fetch stall behaviour:
//!   IFetch_Ready_In (AHB HREADY) and Stall_In (pipeline hazard) are
//!   independent stall sources that BOTH independently freeze the PC and
//!   the instruction address register.
//!
//!   Reference design (msrv32_pc) gates i_addr purely on ahb_ready_in
//!   and gates pc_mux_out (registered PC) purely on a pipeline stall.
//!   This design unifies both: either signal alone holds the PC.
//!
//!   Priority (highest first):
//!     1. Rst_In          — synchronous reset to BOOT_ADDRESS
//!     2. Stall_In        — pipeline hazard holds PC (load-use / branch)
//!     3. !IFetch_Ready_In — AHB not ready, hold PC until memory responds
//!     4. Normal          — advance to PC_Mux_Out
//!
//! JALR bit-0 clearing:
//!   Branch targets arrive as Target_PC_In[31:1] with bit 0 forced to 0
//!   by the caller (Imm_Adder clears bit 0 for JALR per the spec).
//!
//! Misaligned instruction detection:
//!   For RV32I (IALIGN=32), any taken-branch target with next_pc[1]=1
//!   is a 2-byte-misaligned 4-byte instruction fetch — flagged immediately.
//!   This feeds Machine_Control which raises the misaligned-instruction trap.

`timescale 1ns/1ps

module PC_Unit (
  input         Clk_In,              //! Clock input
  input         Rst_In,              //! Synchronous reset — PC <- BOOT_ADDRESS

  //! ── Hazard unit stall (5-stage pipeline) ──────────────────
  input         Stall_In,            //! Hold PC when asserted (load-use / branch stall)

  //! ── Trap sequencing (from Machine_Control) ────────────────
  input  [1:0]  PC_Src_In,           //! Next-PC selector: BOOT/EPC/TRAP/NEXT
  input  [31:0] EPC_In,              //! Exception return address (mepc) for MRET
  input  [31:0] Trap_Addr_In,        //! Trap handler address (mtvec) for trap entry

  //! ── Branch / jump target ──────────────────────────────────
  input         Branch_Taken_In,     //! 1 = redirect to Target_PC_In, 0 = PC+4
  input  [31:1] Target_PC_In,        //! Branch/jump target [31:1] — bit 0 forced 0 by caller

  //! ── Registered PC (feeds instruction memory and pipeline) ─
  output reg [31:0] PC_Out,          //! Current program counter (registered)
  output     [31:0] PC_Plus4_Out,    //! PC + 4 for sequential fetch and JAL/JALR link

  //! ── AHB Instruction fetch interface ──────────────────────
  //! IFetch_Ready_In = AHB HREADY from instruction memory bus.
  //!   When LOW: the instruction memory has not yet returned data.
  //!   Both PC_Out and Instr_Addr_Out must be held stable so the
  //!   AHB master re-presents the same address each cycle until
  //!   the slave asserts HREADY. This is independent of Stall_In.
  input         IFetch_Ready_In,     //! AHB HREADY from instruction memory
  output [31:0] Instr_Addr_Out,      //! Instruction fetch address (registered, AHB-stable)

  //! ── Misalignment detection ────────────────────────────────
  output        Misaligned_Instr_Out //! Taken-branch target not 4-byte aligned -> Machine_Control
);

  // ============================================================
  //! Boot Address
  // ============================================================
  localparam BOOT_ADDRESS = 32'h0000_0000;

  // ============================================================
  //! PC Source Selector Encoding
  //! Must match localparams in Machine_Control
  // ============================================================
  localparam PC_SRC_BOOT = 2'b00;
  localparam PC_SRC_EPC  = 2'b01;
  localparam PC_SRC_TRAP = 2'b10;
  localparam PC_SRC_NEXT = 2'b11;

  // ============================================================
  //! PC + 4 — sequential fetch address and JAL/JALR link value
  // ============================================================
  assign PC_Plus4_Out = PC_Out + 32'h4;

  // ============================================================
  //! Next-PC for NEXT mode
  //! Branch taken  -> reconstruct 32-bit target (bit 0 = 0 per spec)
  //! Branch not taken -> PC + 4
  // ============================================================
  wire [31:0] Next_PC;
  assign Next_PC = Branch_Taken_In ? {Target_PC_In, 1'b0} : PC_Plus4_Out;

  // ============================================================
  //! Misalignment detection
  //! next_pc[1]=1 on a taken branch means a 4-byte instruction
  //! would be fetched from a 2-byte-aligned (not 4-byte) address.
  // ============================================================
  assign Misaligned_Instr_Out = Next_PC[1] & Branch_Taken_In;

  // ============================================================
  //! PC Source Mux (combinatorial)
  //! Machine_Control drives PC_Src_In to select among the four
  //! possible next-PC values.
  // ============================================================
  reg [31:0] PC_Mux_Out;  //! Selected next-PC before stall gate

  always @* begin
    case (PC_Src_In)
      PC_SRC_BOOT: PC_Mux_Out = BOOT_ADDRESS;
      PC_SRC_EPC:  PC_Mux_Out = EPC_In;
      PC_SRC_TRAP: PC_Mux_Out = Trap_Addr_In;
      PC_SRC_NEXT: PC_Mux_Out = Next_PC;
      default:     PC_Mux_Out = Next_PC;
    endcase
  end

  // ============================================================
  //! Instruction Address Register (AHB-gated)
  //!
  //! This register drives Instr_Addr_Out which is the AHB HADDR.
  //! AHB-lite requires HADDR to remain stable for the entire
  //! address phase — i.e. it must not change until HREADY=1.
  //!
  //! Gating logic:
  //!   - Reset     : revert to BOOT_ADDRESS
  //!   - Stall_In  : hold current address (pipeline hazard stall)
  //!   - !IFetch_Ready_In : hold current address (AHB wait state)
  //!   - Otherwise : advance to PC_Mux_Out
  //!
  //! Note: Stall_In must gate IAddr_Reg explicitly. During a load-use
  //! stall, PC_Out is held but PC_Mux_Out still evaluates to PC+4 in NEXT
  //! mode; without this gate, HADDR advances and the fetch stream skips
  //! one instruction when the stall clears.
  // ============================================================
  reg [31:0] IAddr_Reg;

  always @(posedge Clk_In) begin
    if (Rst_In)
      IAddr_Reg <= BOOT_ADDRESS;
    else if (Stall_In)
      IAddr_Reg <= IAddr_Reg;
    else if (IFetch_Ready_In)          //! AHB ready: present next address
      IAddr_Reg <= PC_Mux_Out;
    //! AHB not ready: hold IAddr_Reg (address phase extended)
  end

  assign Instr_Addr_Out = IAddr_Reg;

  // ============================================================
  //! PC Register (sequential)
  //!
  //! Stall priority (after reset):
  //!   1. Stall_In=1       — hazard unit holds the pipeline
  //!   2. !IFetch_Ready_In — AHB wait state, instruction not yet
  //!                         returned, keep PC stable so decode
  //!                         stage does not consume a bubble
  //!   3. Normal           — advance to PC_Mux_Out
  //!
  //! Both stall conditions are independent: a load-use stall can
  //! occur at the same time as an AHB wait state, and both must
  //! hold the PC.
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In)
      PC_Out <= BOOT_ADDRESS;
    else if (Stall_In || !IFetch_Ready_In)
      PC_Out <= PC_Out;               //! Freeze: hazard or AHB wait
    else
      PC_Out <= PC_Mux_Out;           //! Advance to selected next PC
  end

endmodule
