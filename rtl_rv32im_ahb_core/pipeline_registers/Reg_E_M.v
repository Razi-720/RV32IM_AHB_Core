//! Execute → Memory Pipeline Register
//! Captures all execute-stage results and control signals on the
//! rising clock edge for use in the memory and write-back stages.
//!
//! RV32M note:
//!   MDU_Result_In is latched into this register so the M-extension result
//!   travels with its owning instruction through M and W stages. This avoids
//!   sampling a "live" MDU output from a different in-flight instruction.
//!
//! New fields vs base RV32I:
//!   PC_In/Out      — PC of instruction (for mepc on trap entry)
//!   CSR_WrEn       — CSR file write enable
//!   CSR_Op         — CSR operation type
//!   CSR_Addr       — 12-bit CSR address
//!   CSR_UImm       — 5-bit unsigned immediate
//!   CSR_Data       — CSR read data captured at execute
//!   CSR_WrData     — CSR write source data (rs1 after forwarding)
module Reg_E_M (
  input         Clk_In,
  input         Rst_In,
  input         Stall_In,

  //! ── Datapath inputs ─────────────────────────────────────────
  input  [31:0] PC_Plus4_In,
  input  [31:0] PC_In,
  input  [31:0] ALU_Result_In,
  input  [31:0] Read_Data2_In,
  input  [31:0] Imm_Ext_In,
  input  [31:0] Added_Data_In,
  input  [31:0] MDU_Result_In,
  input  [4:0]  Des_Addr_In,

  //! ── Control signal inputs ───────────────────────────────────
  input  [1:0]  Func3_In,
  input         Reg_WrEn_In,
  input  [2:0]  Result_Src_In,     //! Carries 3'b111 for RV32M writeback
  input         DM_WrEn_In,
  input  [1:0]  Load_Size_In,
  input         Load_Unsigned_In,
  input         CSR_WrEn_In,
  input  [2:0]  CSR_Op_In,
  input  [11:0] CSR_Addr_In,
  input  [4:0]  CSR_UImm_In,
  input  [31:0] CSR_Data_In,
  input  [31:0] CSR_WrData_In,

  //! ── Datapath outputs ────────────────────────────────────────
  output reg [31:0] PC_Plus4_Out,
  output reg [31:0] PC_Out,
  output reg [31:0] ALU_Result_Out,
  output reg [31:0] Read_Data2_Out,
  output reg [31:0] Imm_Ext_Out,
  output reg [31:0] Added_Data_Out,
  output reg [31:0] MDU_Result_Out,
  output reg [4:0]  Des_Addr_Out,

  //! ── Control signal outputs ──────────────────────────────────
  output reg [1:0]  Func3_Out,
  output reg        Reg_WrEn_Out,
  output reg [2:0]  Result_Src_Out,
  output reg        DM_WrEn_Out,
  output reg [1:0]  Load_Size_Out,
  output reg        Load_Unsigned_Out,
  output reg        CSR_WrEn_Out,
  output reg [2:0]  CSR_Op_Out,
  output reg [11:0] CSR_Addr_Out,
  output reg [4:0]  CSR_UImm_Out,
  output reg [31:0] CSR_Data_Out,
  output reg [31:0] CSR_WrData_Out
);

  always @(posedge Clk_In) begin
    if (Rst_In) begin
      PC_Plus4_Out     <= 32'b0;
      PC_Out           <= 32'b0;
      ALU_Result_Out   <= 32'b0;
      Read_Data2_Out   <= 32'b0;
      Imm_Ext_Out      <= 32'b0;
      Added_Data_Out   <= 32'b0;
      MDU_Result_Out   <= 32'b0;
      Des_Addr_Out     <= 5'b0;
      Func3_Out        <= 2'b0;
      Reg_WrEn_Out     <= 1'b0;
      Result_Src_Out   <= 3'b0;
      DM_WrEn_Out      <= 1'b0;
      Load_Size_Out    <= 2'b0;
      Load_Unsigned_Out<= 1'b0;
      CSR_WrEn_Out     <= 1'b0;
      CSR_Op_Out       <= 3'b0;
      CSR_Addr_Out     <= 12'b0;
      CSR_UImm_Out     <= 5'b0;
      CSR_Data_Out     <= 32'b0;
      CSR_WrData_Out   <= 32'b0;
    end
    else if (!Stall_In) begin
      PC_Plus4_Out     <= PC_Plus4_In;
      PC_Out           <= PC_In;
      ALU_Result_Out   <= ALU_Result_In;
      Read_Data2_Out   <= Read_Data2_In;
      Imm_Ext_Out      <= Imm_Ext_In;
      Added_Data_Out   <= Added_Data_In;
      MDU_Result_Out   <= MDU_Result_In;
      Des_Addr_Out     <= Des_Addr_In;
      Func3_Out        <= Func3_In;
      Reg_WrEn_Out     <= Reg_WrEn_In;
      Result_Src_Out   <= Result_Src_In;
      DM_WrEn_Out      <= DM_WrEn_In;
      Load_Size_Out    <= Load_Size_In;
      Load_Unsigned_Out<= Load_Unsigned_In;
      CSR_WrEn_Out     <= CSR_WrEn_In;
      CSR_Op_Out       <= CSR_Op_In;
      CSR_Addr_Out     <= CSR_Addr_In;
      CSR_UImm_Out     <= CSR_UImm_In;
      CSR_Data_Out     <= CSR_Data_In;
      CSR_WrData_Out   <= CSR_WrData_In;
    end
    // else: Stall_In=1, hold all outputs
  end

endmodule
