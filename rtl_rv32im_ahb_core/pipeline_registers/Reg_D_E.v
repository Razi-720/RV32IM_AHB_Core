//! Decode → Execute Pipeline Register
//! Captures all decode-stage control signals and datapath values on
//! the rising clock edge.
//!
//! Flush behaviour:
//!   On Flush_In (branch or trap): all control signals zeroed → pipeline bubble.
//!   Is_Mext_Out and MDU_Op_Out are also zeroed on flush so a flushed M-ext
//!   instruction cannot spuriously trigger MDU.Start_In.
//!
//! Stall behaviour (MDU stall):
//!   On Stall_In=1 with no flush: all registers hold their current value.
//!   Is_Mext_Out MUST hold during a DIV stall so the pipeline register
//!   continues to identify the in-flight divide instruction. This is why
//!   a dedicated Stall_In port is added (not present in the base RV32I design).
//!
//! New fields vs base RV32I+Zicsr:
//!   Stall_In  — hold all registers during MDU multi-cycle stall
//!   Is_Mext   — flags an RV32M instruction to the Execute stage
//!   MDU_Op    — funct3 forwarded to MDU (selects MUL/MULH/DIV/REM variant)
module Reg_D_E (
  input         Clk_In,            //! Clock input
  input         Rst_In,            //! Synchronous reset
  input         Flush_In,          //! Flush: zero all control outputs (trap or branch)
  input         Stall_In,          //! Stall: hold all registers (MDU multi-cycle)

  //! ── Datapath inputs ─────────────────────────────────────────
  input  [31:0] PC_In,
  input  [31:0] PC_Plus4_In,
  input  [31:0] Imm_Ext_In,
  input  [1:0]  Func3_In,          //! funct3[1:0] — store/load/branch width
  input  [7:0]  Branch_Cond_In,
  input  [4:0]  Des_Addr_In,
  input  [4:0]  Src_Addr1_In,
  input  [4:0]  Src_Addr2_In,

  //! ── Control signal inputs ───────────────────────────────────
  input         Reg_WrEn_In,
  input  [2:0]  Result_Src_In,
  input         Iadder_Src_In,
  input         ALU_Src_In,
  input  [3:0]  ALU_Control_In,
  input         DM_WrEn_In,
  input  [1:0]  Load_Size_In,
  input         Load_Unsigned_In,
  input         CSR_WrEn_In,
  input  [2:0]  CSR_Op_In,

  //! ── RV32M extension inputs ──────────────────────────────────
  input         Is_Mext_In,        //! 1 = this is an RV32M instruction
  input  [2:0]  MDU_Op_In,         //! funct3 → MDU operation selector

  //! ── Datapath outputs ────────────────────────────────────────
  output reg [31:0] PC_Out,
  output reg [31:0] PC_Plus4_Out,
  output reg [31:0] Imm_Ext_Out,
  output reg [1:0]  Func3_Out,
  output reg [7:0]  Branch_Cond_Out,
  output reg [4:0]  Des_Addr_Out,
  output reg [4:0]  Src_Addr1_Out,
  output reg [4:0]  Src_Addr2_Out,

  //! ── Control signal outputs ──────────────────────────────────
  output reg        Reg_WrEn_Out,
  output reg [2:0]  Result_Src_Out,
  output reg        Iadder_Src_Out,
  output reg        ALU_Src_Out,
  output reg [3:0]  ALU_Control_Out,
  output reg        DM_WrEn_Out,
  output reg [1:0]  Load_Size_Out,
  output reg        Load_Unsigned_Out,
  output reg        CSR_WrEn_Out,
  output reg [2:0]  CSR_Op_Out,

  //! ── RV32M extension outputs ─────────────────────────────────
  output reg        Is_Mext_Out,   //! RV32M instruction flag → MDU / Hazard_Unit
  output reg [2:0]  MDU_Op_Out     //! MDU operation selector → MDU
);

  always @(posedge Clk_In) begin
    if (Rst_In || Flush_In) begin
      //! Zero all control signals — creates a pipeline bubble.
      //! Is_Mext / MDU_Op also zeroed: a flushed M-ext instr must not
      //! retrigger MDU.Start_In on the following cycle.
      Reg_WrEn_Out     <= 1'b0;
      Result_Src_Out   <= 3'b0;
      Iadder_Src_Out   <= 1'b0;
      ALU_Src_Out      <= 1'b0;
      ALU_Control_Out  <= 4'b0;
      DM_WrEn_Out      <= 1'b0;
      Load_Size_Out    <= 2'b0;
      Load_Unsigned_Out<= 1'b0;
      CSR_WrEn_Out     <= 1'b0;
      CSR_Op_Out       <= 3'b0;
      Is_Mext_Out      <= 1'b0;
      MDU_Op_Out       <= 3'b0;
      PC_Out           <= 32'b0;
      PC_Plus4_Out     <= 32'b0;
      Imm_Ext_Out      <= 32'b0;
      Func3_Out        <= 2'b0;
      Branch_Cond_Out  <= 8'b0;
      Des_Addr_Out     <= 5'b0;
      Src_Addr1_Out    <= 5'b0;
      Src_Addr2_Out    <= 5'b0;
    end
    else if (!Stall_In) begin
      //! Normal advance — capture new decode-stage values.
      //! When Stall_In=1 (and no flush): registers implicitly hold,
      //! preserving Is_Mext_Out=1 and Des_Addr_Out for the duration
      //! of a multi-cycle divide.
      Reg_WrEn_Out     <= Reg_WrEn_In;
      Result_Src_Out   <= Result_Src_In;
      Iadder_Src_Out   <= Iadder_Src_In;
      ALU_Src_Out      <= ALU_Src_In;
      ALU_Control_Out  <= ALU_Control_In;
      DM_WrEn_Out      <= DM_WrEn_In;
      Load_Size_Out    <= Load_Size_In;
      Load_Unsigned_Out<= Load_Unsigned_In;
      CSR_WrEn_Out     <= CSR_WrEn_In;
      CSR_Op_Out       <= CSR_Op_In;
      Is_Mext_Out      <= Is_Mext_In;
      MDU_Op_Out       <= MDU_Op_In;
      PC_Out           <= PC_In;
      PC_Plus4_Out     <= PC_Plus4_In;
      Imm_Ext_Out      <= Imm_Ext_In;
      Func3_Out        <= Func3_In;
      Branch_Cond_Out  <= Branch_Cond_In;
      Des_Addr_Out     <= Des_Addr_In;
      Src_Addr1_Out    <= Src_Addr1_In;
      Src_Addr2_Out    <= Src_Addr2_In;
    end
    //! else: Stall_In=1, no flush → all regs hold (Verilog implicit)
  end

endmodule
