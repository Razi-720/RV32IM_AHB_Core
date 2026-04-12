//! Hazard Detection Unit for RV32IM Pipeline
//! Detects data hazards, load-use hazards, control hazards,
//! and MDU multi-cycle stalls (RV32M divide instructions).
//!
//! Stall/Flush priority (highest → lowest):
//!   1. MDU stall   — holds F, D, E; does NOT flush anything
//!   2. Load-use    — stalls F, D; flushes E (inserts bubble)
//!   3. Branch taken — flushes D, E
//!
//! MDU stall behaviour:
//!   When a DIV/DIVU/REM/REMU is in the Execute stage, MDU_Ready_In
//!   is deasserted for up to 32 cycles. During this time:
//!     • Fetch and Decode are stalled (Stall_F, Stall_D)
//!     • Execute register is stalled (Stall_E) — NOT flushed
//!   Stalling Execute (not flushing) is essential: Is_Mext_Out and
//!   Des_Addr_Out must remain stable in Reg_D_E for the entire
//!   duration so the pipeline knows where to write the result.
//!   MUL/MULH/MULHSU/MULHU are single-cycle — MDU_Ready_In stays
//!   high for those, so MDU_Stall is never asserted for multiply.

module Hazard_Unit (
  //! ── Decode stage inputs ─────────────────────────────────────
  input  [4:0] Src_Addr1_D_In,      //! Source register 1 address (decode)
  input  [4:0] Src_Addr2_D_In,      //! Source register 2 address (decode)

  //! ── Execute stage inputs ────────────────────────────────────
  input  [4:0] Des_Addr_E_In,        //! Destination register address (execute)
  input        Reg_WrEn_E_In,        //! Register write enable (execute)
  input  [2:0] Result_Src_E_In,      //! Result source selector (execute)
  input  [4:0] Src_Addr1_E_In,       //! Source register 1 address (execute)
  input  [4:0] Src_Addr2_E_In,       //! Source register 2 address (execute)

  //! ── Memory stage inputs ─────────────────────────────────────
  input  [4:0] Des_Addr_M_In,        //! Destination register address (memory)
  input        Reg_WrEn_M_In,        //! Register write enable (memory)

  //! ── Write-back stage inputs ─────────────────────────────────
  input  [4:0] Des_Addr_W_In,        //! Destination register address (write-back)
  input        Reg_WrEn_W_In,        //! Register write enable (write-back)

  //! ── Control hazard input ────────────────────────────────────
  input        Branch_Taken_E_In,    //! Branch taken signal (execute)

  //! ── MDU stall input ─────────────────────────────────────────
  input        MDU_Ready_In,         //! From MDU: LOW while divide is iterating
                                     //! HIGH for multiply (always) and when idle

  //! ── Pipeline stall outputs ──────────────────────────────────
  output       Stall_F_Out,          //! Stall fetch stage
  output       Stall_D_Out,          //! Stall decode stage
  output       Stall_E_Out,          //! Stall execute register (MDU only)

  //! ── Pipeline flush outputs ──────────────────────────────────
  output       Flush_D_Out,          //! Flush decode stage
  output       Flush_E_Out,          //! Flush execute stage

  //! ── Forwarding control outputs ──────────────────────────────
  output [1:0] ForwardA_E_Out,       //! Forward control for ALU source A
  output [1:0] ForwardB_E_Out        //! Forward control for ALU source B
);

  // ============================================================
  //! Internal hazard signals
  // ============================================================
  wire load_use_hazard;
  wire control_hazard;
  wire mdu_stall;

  // ============================================================
  //! Forwarding Logic
  //! Memory stage has higher priority than Write-Back stage.
  //! x0 (address 0) is never forwarded — it is always zero.
  // ============================================================
  assign ForwardA_E_Out =
    (Reg_WrEn_M_In && (Des_Addr_M_In == Src_Addr1_E_In) && (Des_Addr_M_In != 5'b0)) ? 2'b01 :
    (Reg_WrEn_W_In && (Des_Addr_W_In == Src_Addr1_E_In) && (Des_Addr_W_In != 5'b0)) ? 2'b10 :
    2'b00;

  assign ForwardB_E_Out =
    (Reg_WrEn_M_In && (Des_Addr_M_In == Src_Addr2_E_In) && (Des_Addr_M_In != 5'b0)) ? 2'b01 :
    (Reg_WrEn_W_In && (Des_Addr_W_In == Src_Addr2_E_In) && (Des_Addr_W_In != 5'b0)) ? 2'b10 :
    2'b00;

  // ============================================================
  //! Load-Use Hazard Detection
  //! A load (Result_Src == 3'b101) in Execute whose destination
  //! matches either source of the instruction currently in Decode.
  //! Requires one stall cycle so the load data can be forwarded
  //! from the Memory stage on the next cycle.
  // ============================================================
  assign load_use_hazard = (Result_Src_E_In == 3'b101) &&
                            Reg_WrEn_E_In &&
                            (Des_Addr_E_In != 5'b0) &&
                            ((Des_Addr_E_In == Src_Addr1_D_In) ||
                             (Des_Addr_E_In == Src_Addr2_D_In));

  // ============================================================
  //! Control Hazard Detection
  //! Branch outcome is known at end of Execute — the two instructions
  //! that entered the pipeline after the branch must be flushed.
  // ============================================================
  assign control_hazard = Branch_Taken_E_In;

  // ============================================================
  //! MDU Stall Detection
  //! Deasserted (0) when MDU is idle or running a single-cycle MUL.
  //! Asserted (1) during a multi-cycle DIV/REM until Ready fires.
  // ============================================================
  assign mdu_stall = ~MDU_Ready_In;

  // ============================================================
  //! Stall Logic
  //!
  //! Stall_F / Stall_D:
  //!   Both load-use and MDU stalls freeze Fetch and Decode.
  //!   They must not advance while the Execute stage is blocked.
  //!
  //! Stall_E:
  //!   Only MDU stall freezes the Execute register (Reg_D_E).
  //!   Load-use does NOT stall Execute — it flushes it (bubble).
  //!   This keeps Is_Mext_Out and Des_Addr_Out stable in Reg_D_E
  //!   for the entire divide duration.
  // ============================================================
  assign Stall_F_Out = load_use_hazard | mdu_stall;
  assign Stall_D_Out = load_use_hazard | mdu_stall;
  assign Stall_E_Out = mdu_stall;

  // ============================================================
  //! Flush Logic
  //!
  //! Flush_D: branch flushes the instruction that just entered Decode.
  //!   MDU stall must NOT flush Decode — the instruction behind the
  //!   divide is stalled in Fetch/Decode and must not be lost.
  //!
  //! Flush_E: branch and load-use both flush the Execute register.
  //!   MDU stall must NOT flush Execute — see Stall_E comment above.
  //!   Machine_Control's Flush_MC is OR'd in the top module separately
  //!   and is not the Hazard_Unit's responsibility.
  // ============================================================
  assign Flush_D_Out = control_hazard;
  assign Flush_E_Out = control_hazard | load_use_hazard;

endmodule
