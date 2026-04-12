//! Memory → Write-Back Pipeline Register
//! Captures all memory-stage results and control signals on the
//! rising clock edge for consumption in the write-back stage.
//!
//! New fields vs base RV32I:
//!   CSR_WrEn  — CSR file write enable (gated by WrEn_Generator after this register)
//!   CSR_Op    — CSR operation type (passed to CSR_File)
//!   CSR_Addr  — 12-bit CSR address (passed to CSR_File)
//!   CSR_UImm  — 5-bit unsigned immediate (passed to CSR_File)
//!   CSR_Data  — CSR read data (passed to WB_Unit for write-back into rd)
//!   CSR_WrData— CSR write source data (rs1 value, passed to CSR_File)
module Reg_M_W (
  input         Clk_In,            //! Clock input
  input         Rst_In,            //! Synchronous reset
  input         Stall_In,          //! Hold Memory→WB state during data-bus wait

  //! ── Datapath inputs ─────────────────────────────────────────
  input  [31:0] PC_Plus4_In,       //! PC + 4 (JAL/JALR link address)
  input  [31:0] ALU_Result_In,     //! ALU result
  input  [31:0] Loaded_Data_In,    //! Processed load data from Load_Unit
  input  [31:0] Imm_Ext_In,        //! Sign-extended immediate (LUI pass-through)
  input  [31:0] Added_Data_In,     //! Immediate adder output (AUIPC pass-through)
  input  [31:0] MDU_Result_In,     //! RV32M result latched from Execute/Memory path
  input  [4:0]  Des_Addr_In,       //! Destination register address (rd)

  //! ── Control signal inputs ───────────────────────────────────
  input         Reg_WrEn_In,       //! Integer register file write enable (pre-gate)
  input  [2:0]  Result_Src_In,     //! Write-back source selector
  input         CSR_WrEn_In,       //! CSR file write enable (pre-gate)
  input  [2:0]  CSR_Op_In,         //! CSR operation type
  input  [11:0] CSR_Addr_In,       //! CSR address
  input  [4:0]  CSR_UImm_In,       //! CSR unsigned immediate
  input  [31:0] CSR_Data_In,       //! CSR read data → WB_Unit
  input  [31:0] CSR_WrData_In,     //! CSR write data source → CSR_File

  //! ── Datapath outputs ────────────────────────────────────────
  output reg [31:0] PC_Plus4_Out,
  output reg [31:0] ALU_Result_Out,
  output reg [31:0] Loaded_Data_Out,
  output reg [31:0] Imm_Ext_Out,
  output reg [31:0] Added_Data_Out,
  output reg [31:0] MDU_Result_Out,
  output reg [4:0]  Des_Addr_Out,

  //! ── Control signal outputs ──────────────────────────────────
  output reg        Reg_WrEn_Out,      //! → WrEn_Generator (pre-flush-gate)
  output reg [2:0]  Result_Src_Out,    //! → WB_Unit
  output reg        CSR_WrEn_Out,      //! → WrEn_Generator (pre-flush-gate)
  output reg [2:0]  CSR_Op_Out,        //! → CSR_File
  output reg [11:0] CSR_Addr_Out,      //! → CSR_File
  output reg [4:0]  CSR_UImm_Out,      //! → CSR_File
  output reg [31:0] CSR_Data_Out,      //! → WB_Unit (Result_Src=WB_CSR)
  output reg [31:0] CSR_WrData_Out     //! → CSR_File
);

  always @(posedge Clk_In) begin
    if (Rst_In) begin
      PC_Plus4_Out   <= 32'b0;
      ALU_Result_Out <= 32'b0;
      Loaded_Data_Out<= 32'b0;
      Imm_Ext_Out    <= 32'b0;
      Added_Data_Out <= 32'b0;
      MDU_Result_Out <= 32'b0;
      Des_Addr_Out   <= 5'b0;
      Reg_WrEn_Out   <= 1'b0;
      Result_Src_Out <= 3'b0;
      CSR_WrEn_Out   <= 1'b0;
      CSR_Op_Out     <= 3'b0;
      CSR_Addr_Out   <= 12'b0;
      CSR_UImm_Out   <= 5'b0;
      CSR_Data_Out   <= 32'b0;
      CSR_WrData_Out <= 32'b0;
    end
    else if (!Stall_In) begin
      PC_Plus4_Out   <= PC_Plus4_In;
      ALU_Result_Out <= ALU_Result_In;
      Loaded_Data_Out<= Loaded_Data_In;
      Imm_Ext_Out    <= Imm_Ext_In;
      Added_Data_Out <= Added_Data_In;
      MDU_Result_Out <= MDU_Result_In;
      Des_Addr_Out   <= Des_Addr_In;
      Reg_WrEn_Out   <= Reg_WrEn_In;
      Result_Src_Out <= Result_Src_In;
      CSR_WrEn_Out   <= CSR_WrEn_In;
      CSR_Op_Out     <= CSR_Op_In;
      CSR_Addr_Out   <= CSR_Addr_In;
      CSR_UImm_Out   <= CSR_UImm_In;
      CSR_Data_Out   <= CSR_Data_In;
      CSR_WrData_Out <= CSR_WrData_In;
    end
    // else: Stall_In=1, hold all outputs
  end

endmodule
