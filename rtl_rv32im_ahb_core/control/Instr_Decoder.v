//! Instruction Field Decoder
//! Splits the raw 32-bit instruction word into named fields consumed
//! by the rest of the decode stage. Also implements flush-to-NOP:
//! when Flush_In is asserted the instruction is replaced with
//! ADDI x0, x0, 0 (32'h0000_0013) before field extraction, so all
//! downstream units see a harmless no-operation.
//!
//! NOP encoding (ADDI x0, x0, 0):
//!   [31:20] = 000000000000  imm = 0
//!   [19:15] = 00000         rs1 = x0
//!   [14:12] = 000           funct3 = ADD
//!   [11:7]  = 00000         rd  = x0
//!   [6:0]   = 0010011       opcode = OP-IMM
//!
//! M-extension note:
//!   Func7_Full_Out exposes all 7 bits of funct7 so the Decoder can
//!   distinguish RV32M instructions (funct7 = 7'b0000001) from
//!   RV32I R-type instructions (funct7 = 7'b0000000 or 7'b0100000).
//!   Func7_Out (bit 30 only) is retained for backward compatibility
//!   with the existing Decoder port.
module Instr_Decoder (
  input         Flush_In,           //! Flush: replace instruction with NOP when asserted
  input  [31:0] Instruction_In,     //! Raw 32-bit instruction word from pipeline register

  output [6:0]  Opcode_Out,         //! Opcode field          [6:0]
  output [2:0]  Func3_Out,          //! funct3 field          [14:12]
  output        Func7_Out,          //! funct7 bit 30 only    [30]  (SUB/SRA/SRAI)
  output [6:0]  Func7_Full_Out,     //! funct7 full field     [31:25] (M-ext detect)
  output [4:0]  Src_Addr1_Out,      //! RS1 register address  [19:15]
  output [4:0]  Src_Addr2_Out,      //! RS2 register address  [24:20]
  output [4:0]  Des_Addr_Out,       //! RD  register address  [11:7]
  output [11:0] CSR_Addr_Out,       //! CSR address           [31:20]
  output [24:0] Instr_31to7_Out     //! Immediate source bits [31:7] → Extend_Unit
);

  // ============================================================
  //! NOP Instruction Constant
  //! ADDI x0, x0, 0 — writes nothing, reads nothing, no memory access
  // ============================================================
  localparam NOP = 32'h0000_0013;

  // ============================================================
  //! Flush Mux
  //! Substitutes a NOP before field extraction so every downstream
  //! unit (Decoder, Extend_Unit, Register_File read) sees safe values.
  // ============================================================
  wire [31:0] Instr_Mux;
  assign Instr_Mux = Flush_In ? NOP : Instruction_In;

  // ============================================================
  //! Field Extraction
  // ============================================================
  assign Opcode_Out      = Instr_Mux[6:0];
  assign Func3_Out       = Instr_Mux[14:12];
  assign Func7_Out       = Instr_Mux[30];        //! bit 30 only — Decoder legacy port
  assign Func7_Full_Out  = Instr_Mux[31:25];     //! all 7 bits  — M-ext detection
  assign Src_Addr1_Out   = Instr_Mux[19:15];
  assign Src_Addr2_Out   = Instr_Mux[24:20];
  assign Des_Addr_Out    = Instr_Mux[11:7];
  assign CSR_Addr_Out    = Instr_Mux[31:20];
  assign Instr_31to7_Out = Instr_Mux[31:7];

endmodule
