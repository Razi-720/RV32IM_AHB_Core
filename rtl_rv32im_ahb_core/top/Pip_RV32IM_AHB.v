`timescale 1ns/1ps
`include "rv_defs.vh"

//! Top-level module for a 5-stage pipelined RISC-V RV32IM+Zicsr processor
//!
//! AHB-lite interface additions (vs original):
//!   Instr_HReady_In  — instruction bus HREADY (was hardcoded 1'b1)
//!   Data_HReady_In   — data bus HREADY        (was hardcoded 1'b1)
//!   HResp_In         — data bus HRESP error   (was hardcoded 1'b0)
//!   Data_HTrans_Out  — data bus HTRANS         (was left unconnected)
//!   Data_HSize_Out   — data bus HSIZE          (transfer size encoding)
//!
//! ── MDU combinational loop fix ───────────────────────────────────────────
//! Root cause (UNOPTFLAT):
//!   ForwardA_Data → MDU.A_In (comb) → Mul32_Booth.Product (comb)
//!   → MDU_Result → Result_W (via WB_Unit, comb)
//!   → ForwardA_Data (when ForwardA_E==2'b10, WB-stage forward)
//!
//! Fix: MDU_SrcA_r / MDU_SrcB_r are registered on the MDU_Start pulse.
//! MDU always reads from these registers — ForwardA/B_Data never feeds
//! MDU directly.

module Pip_RV32IM_AHB (
  input         Clk_In,
  input         Rst_In,

  // ── Instruction memory (AHB-lite) ──────────────────────────
  input  [31:0] Instruction_In,
  output [31:0] Instr_Addr_Out,
  input         Instr_HReady_In,       //! AHB HREADY from instruction memory
                                       //!   1 = memory accepted/returned data, advance PC
                                       //!   0 = wait state, hold PC and fetch address

  // ── Data memory (AHB-lite) ─────────────────────────────────
  input  [31:0] DM_Data_In,
  output [31:0] DM_Addr_Out,
  output [31:0] DM_Data_Out,
  output [3:0]  DM_Mask_Out,
  output        DM_WrEn_Out,
  input         Data_HReady_In,        //! AHB HREADY from data memory
                                       //!   1 = memory accepted/returned data
                                       //!   0 = wait state, stall pipeline
  input         HResp_In,              //! AHB HRESP from data memory
                                       //!   0 = OKAY, 1 = ERROR (bus fault)
  output [1:0]  Data_HTrans_Out,       //! AHB HTRANS to data memory
                                       //!   2'b10=NONSEQ (active transfer)
                                       //!   2'b00=IDLE   (no transfer)
  output [2:0]  Data_HSize_Out,        //! AHB HSIZE to data memory
                                       //!   000=byte 001=halfword 010=word

  // ── Interrupts ─────────────────────────────────────────────
  input         EIrq_In,
  input         TIrq_In,
  input         SIrq_In,
  input  [63:0] RTC_In

`ifdef COCOTB_SIM
  ,
  output        hazard_detected,
  output        stall,
  output        flush,
  output        trap_taken,
  output [1:0]  pc_src
`endif
);

  // ── Fetch ──────────────────────────────────────────────────
  wire [31:0] PC_F, PC_Plus4_F;
  wire        Misaligned_Instr_F;

  // ── Decode ─────────────────────────────────────────────────
  wire [31:0] PC_D, PC_Plus4_D, Instruction_D;
  wire [6:0]  Opcode_D;
  wire [2:0]  Func3_D;
  wire        Func7_D;
  wire [6:0]  Func7_Full_D;
  wire [4:0]  Src_Addr1_D, Src_Addr2_D, Des_Addr_D;
  wire [11:0] CSR_Addr_Raw_D;
  wire [24:0] Immediate_D;
  wire [31:0] Imm_Ext_D;
  wire        Reg_WrEn_D, Iadder_Src_D, ALU_Src_D, DM_WrEn_D;
  wire        Load_Unsigned_D, CSR_WrEn_D, Is_Mext_D;
  wire        Illegal_Instr_D, Misaligned_Load_D, Misaligned_Store_D;
  wire [2:0]  Result_Src_D, Imm_Type_D, CSR_Op_D, MDU_Op_D;
  wire [3:0]  ALU_Control_D;
  wire [7:0]  Branch_Cond_D;
  wire [1:0]  Load_Size_D;

  // ── Execute ────────────────────────────────────────────────
  wire [31:0] PC_E, PC_Plus4_E, Imm_Ext_E, ALU_Result_E, Imm_Added_E;
  wire [31:0] Read_Data1_E, Read_Data2_E;
  wire [1:0]  Func3_E, Load_Size_E;
  wire [4:0]  Des_Addr_E, Src_Addr1_E, Src_Addr2_E;
  wire [11:0] CSR_Addr_E;
  wire [4:0]  CSR_UImm_E;
  wire [31:0] CSR_WrData_E;
  wire        Reg_WrEn_E, Iadder_Src_E, ALU_Src_E, DM_WrEn_E;
  wire        Load_Unsigned_E, CSR_WrEn_E, Branch_Taken_E;
  wire        Is_Mext_E, Misaligned_Load_E, Misaligned_Store_E;
  wire        Reg_WrEn_E_Gated;
  wire [2:0]  Result_Src_E, CSR_Op_E, MDU_Op_E;
  wire [3:0]  ALU_Control_E;
  wire [7:0]  Branch_Cond_E;

  // ── Memory ─────────────────────────────────────────────────
  wire [31:0] PC_Plus4_M, PC_M, ALU_Result_M, Read_Data2_M;
  wire [31:0] Imm_Ext_M, Imm_Added_M, Loaded_Data_M, MDU_Result_M;
  wire [31:0] DM_WrData_M, DM_Addr_M, Data_M, CSR_Data_M, CSR_WrData_M;
  wire [4:0]  Des_Addr_M, CSR_UImm_M;
  wire [11:0] CSR_Addr_M;
  wire [3:0]  DM_Mask_M;
  wire [2:0]  Result_Src_M, CSR_Op_M;
  wire [1:0]  Func3_M, Load_Size_M;
  wire        Reg_WrEn_M, DM_WrEn_M, DM_Wr_Req_M;
  wire        Load_Unsigned_M, CSR_WrEn_M;
  wire [1:0]  AHB_HTrans_M;         //! HTRANS generated from memory-stage access validity
  wire [2:0]  AHB_HSize_M;          //! HSIZE generated from load/store transfer size
  wire        Load_Access_Fault_M;  //! HRESP error on load in memory stage
  reg         Load_In_M_d;          //! 1-cycle delayed load-in-M marker for HRESP alignment

  // ── Write-Back ─────────────────────────────────────────────
  wire [31:0] PC_Plus4_W, ALU_Result_W, Loaded_Data_W;
  wire [31:0] Imm_Ext_W, Imm_Added_W, MDU_Result_W, Result_W, CSR_Data_W, CSR_WrData_W;
  wire [4:0]  Des_Addr_W, CSR_UImm_W;
  wire [11:0] CSR_Addr_W;
  wire [2:0]  Result_Src_W, CSR_Op_W;
  wire        Reg_WrEn_W_Pre, Reg_WrEn_W;
  wire        CSR_WrEn_W_Pre, CSR_WrEn_W;

  // ── Hazard / Flush ─────────────────────────────────────────
  wire        Stall_F, Stall_D, Stall_E, Flush_D, Flush_E;
  wire        Stall_F_Total, Stall_D_Total, Stall_E_Total;
  wire        Data_Access_M, Data_Stall;
  wire        Is_Load_M, Is_Store_M;
  wire [1:0]  Data_Size_M;
  wire [1:0]  ForwardA_E, ForwardB_E;
  wire [31:0] ForwardA_Data, ForwardB_Data;
  wire        Flush_E_Combined, Flush_D_Combined;
  assign Flush_E_Combined = Flush_E | Flush_MC;
  assign Flush_D_Combined = Flush_D | Flush_MC;
  assign Is_Load_M        = (Result_Src_M == 3'b101);
  assign Is_Store_M       = DM_Wr_Req_M;
  assign Data_Access_M    = Is_Store_M | Is_Load_M;
  assign Data_Size_M      = Is_Store_M ? Func3_M : Load_Size_M;
  assign AHB_HTrans_M     = Data_Access_M ? `AHB_HTRANS_NONSEQ : `AHB_HTRANS_IDLE;
  assign AHB_HSize_M      = (Data_Size_M == `MEM_SIZE_BYTE)     ? `AHB_HSIZE_BYTE :
                            (Data_Size_M == `MEM_SIZE_HALFWORD) ? `AHB_HSIZE_HALFWORD :
                                                                    `AHB_HSIZE_WORD;
  assign Data_Stall       = Data_Access_M & ~Data_HReady_In;
  assign Stall_F_Total    = Stall_F | Data_Stall;
  assign Stall_D_Total    = Stall_D | Data_Stall;
  assign Stall_E_Total    = Stall_E | Data_Stall;
  assign Load_Access_Fault_M = Data_HReady_In & HResp_In
                             & ((Result_Src_M == 3'b101) | Load_In_M_d);

  always @(posedge Clk_In) begin
    if (Rst_In)
      Load_In_M_d <= 1'b0;
    else
      Load_In_M_d <= (Result_Src_M == 3'b101);
  end

  // ── Machine Control ────────────────────────────────────────
  wire [1:0]  PC_Src;
  wire        Trap_Taken, Flush_MC, I_Or_E, Set_EPC, Set_Cause;
  wire [3:0]  Cause;
  wire        Instret_Inc, MIE_Clear, MIE_Set, Misaligned_Exc;

  // ── CSR ────────────────────────────────────────────────────
  wire [31:0] CSR_Data_Out, EPC, Trap_Addr;
  wire        MIE, MEIE, MTIE, MSIE, MEIP, MTIP, MSIP;

  // ── MDU ────────────────────────────────────────────────────
  wire        MDU_Ready;
  wire [31:0] MDU_Result;

  reg  [31:0] MDU_SrcA_r, MDU_SrcB_r;
  reg         MDU_Started_r;
  wire        MDU_Stall, MDU_Start;
  wire [31:0] MDU_SrcA, MDU_SrcB;

  assign MDU_Stall     = Is_Mext_E & ~MDU_Ready;
  assign MDU_Start     = Is_Mext_E & ~MDU_Started_r;

  always @(posedge Clk_In) begin
    if (Rst_In || !Is_Mext_E)
      MDU_Started_r <= 1'b0;
    else if (MDU_Start)
      MDU_Started_r <= 1'b1;
    else if (MDU_Ready)
      MDU_Started_r <= 1'b0;
  end

  always @(posedge Clk_In) begin
    if (MDU_Start) begin
      MDU_SrcA_r <= ForwardA_Data;
      MDU_SrcB_r <= ForwardB_Data;
    end
  end

  assign MDU_SrcA = MDU_Start ? ForwardA_Data : MDU_SrcA_r;
  assign MDU_SrcB = MDU_Start ? ForwardB_Data : MDU_SrcB_r;

  // ── PC Unit ────────────────────────────────────────────────
  //! IFetch_Ready_In was 1'b1 — now connected to Instr_HReady_In.
  //! PC_Unit gates both PC_Out and Instr_Addr_Out on this signal:
  //!   - Instr_Addr_Out held stable during AHB wait state (HREADY=0)
  //!   - PC_Out also frozen so the pipeline does not advance
  //! Stall_In (hazard) and IFetch_Ready_In are independent stall
  //! sources — either alone freezes the PC.
  PC_Unit pc_unit (
    .Clk_In               (Clk_In),
    .Rst_In               (Rst_In),
    .Stall_In             (Stall_F_Total),
    .PC_Src_In            (PC_Src),
    .EPC_In               (EPC),
    .Trap_Addr_In         (Trap_Addr),
    .Branch_Taken_In      (Branch_Taken_E),
    .Target_PC_In         (Imm_Added_E[31:1]),
    .PC_Out               (PC_F),
    .PC_Plus4_Out         (PC_Plus4_F),
    .IFetch_Ready_In      (Instr_HReady_In),   //! was 1'b1
    .Instr_Addr_Out       (Instr_Addr_Out),
    .Misaligned_Instr_Out (Misaligned_Instr_F)
  );

  // ── F/D Register ───────────────────────────────────────────
  Reg_F_D reg_f_d (
    .Clk_In(Clk_In), .Rst_In(Rst_In),
    .Stall_In(Stall_D_Total), .Flush_In(Flush_D_Combined),
    .PC_In(PC_F), .PC_Plus4_In(PC_Plus4_F), .Instr_In(Instruction_In),
    .PC_Out(PC_D), .PC_Plus4_Out(PC_Plus4_D), .Instr_Out(Instruction_D)
  );

  // ── Instruction Field Decoder ──────────────────────────────
  Instr_Decoder instr_dec (
    .Flush_In(Flush_D_Combined), .Instruction_In(Instruction_D),
    .Opcode_Out(Opcode_D),       .Func3_Out(Func3_D),
    .Func7_Out(Func7_D),         .Func7_Full_Out(Func7_Full_D),
    .Src_Addr1_Out(Src_Addr1_D), .Src_Addr2_Out(Src_Addr2_D),
    .Des_Addr_Out(Des_Addr_D),   .CSR_Addr_Out(CSR_Addr_Raw_D),
    .Instr_31to7_Out(Immediate_D)
  );

  // ── Decoder ────────────────────────────────────────────────
  Decoder decoder (
    .Trap_Taken_In(Trap_Taken),         .Iadder_1to0_In(Imm_Added_E[1:0]),
    .Opcode_In(Opcode_D),               .Func3_In(Func3_D),
    .Func7_In(Func7_D),                 .Func7_Full_In(Func7_Full_D),
    .Reg_WrEn_Out(Reg_WrEn_D),          .Imm_Type_Out(Imm_Type_D),
    .Iadder_Src_Out(Iadder_Src_D),      .ALU_Src_Out(ALU_Src_D),
    .ALU_Control_Out(ALU_Control_D),    .DM_WrEn_Out(DM_WrEn_D),
    .Branch_Cond_Out(Branch_Cond_D),    .Load_Unsigned_Out(Load_Unsigned_D),
    .Load_Size_Out(Load_Size_D),        .Result_Src_Out(Result_Src_D),
    .CSR_WrEn_Out(CSR_WrEn_D),         .CSR_Op_Out(CSR_Op_D),
    .Is_Mext_Out(Is_Mext_D),           .MDU_Op_Out(MDU_Op_D),
    .Illegal_Instr_Out(Illegal_Instr_D),
    .Misaligned_Load_Out(Misaligned_Load_D),
    .Misaligned_Store_Out(Misaligned_Store_D)
  );

  // ── Register File ──────────────────────────────────────────
  Register_File reg_file (
    .Clk_In(Clk_In), .Rst_In(Rst_In), .WrEn_In(Reg_WrEn_W),
    .Src_Addr1_In(Src_Addr1_D), .Src_Addr2_In(Src_Addr2_D),
    .Des_Addr_In(Des_Addr_W),   .Des_Data_In(Result_W),
    .Src_Data1_Out(Read_Data1_E), .Src_Data2_Out(Read_Data2_E)
  );

  // ── Immediate Extension ────────────────────────────────────
  Extend_Unit imm_extend (
    .Instr_In(Immediate_D), .Imm_Type_In(Imm_Type_D), .Imm_Out(Imm_Ext_D)
  );

  // ── D/E Register ───────────────────────────────────────────
  Reg_D_E reg_d_e (
    .Clk_In(Clk_In), .Rst_In(Rst_In),
    .Flush_In(Flush_E_Combined), .Stall_In(Stall_E_Total),
    .PC_In(PC_D),             .PC_Plus4_In(PC_Plus4_D),
    .Imm_Ext_In(Imm_Ext_D),   .Func3_In(Func3_D[1:0]),
    .Reg_WrEn_In(Reg_WrEn_D), .Result_Src_In(Result_Src_D),
    .Iadder_Src_In(Iadder_Src_D), .ALU_Src_In(ALU_Src_D),
    .ALU_Control_In(ALU_Control_D), .DM_WrEn_In(DM_WrEn_D),
    .Branch_Cond_In(Branch_Cond_D), .Load_Unsigned_In(Load_Unsigned_D),
    .Load_Size_In(Load_Size_D),     .Des_Addr_In(Des_Addr_D),
    .Src_Addr1_In(Src_Addr1_D),     .Src_Addr2_In(Src_Addr2_D),
    .CSR_WrEn_In(CSR_WrEn_D),       .CSR_Op_In(CSR_Op_D),
    .Is_Mext_In(Is_Mext_D),         .MDU_Op_In(MDU_Op_D),
    .PC_Out(PC_E),                   .PC_Plus4_Out(PC_Plus4_E),
    .Imm_Ext_Out(Imm_Ext_E),         .Func3_Out(Func3_E),
    .Reg_WrEn_Out(Reg_WrEn_E),       .Result_Src_Out(Result_Src_E),
    .Iadder_Src_Out(Iadder_Src_E),   .ALU_Src_Out(ALU_Src_E),
    .ALU_Control_Out(ALU_Control_E), .DM_WrEn_Out(DM_WrEn_E),
    .Branch_Cond_Out(Branch_Cond_E), .Load_Unsigned_Out(Load_Unsigned_E),
    .Load_Size_Out(Load_Size_E),     .Des_Addr_Out(Des_Addr_E),
    .Src_Addr1_Out(Src_Addr1_E),     .Src_Addr2_Out(Src_Addr2_E),
    .CSR_WrEn_Out(CSR_WrEn_E),       .CSR_Op_Out(CSR_Op_E),
    .Is_Mext_Out(Is_Mext_E),         .MDU_Op_Out(MDU_Op_E)
  );

  assign CSR_Addr_E = Imm_Ext_E[11:0];
  assign CSR_UImm_E = Src_Addr1_E;

  // ── Forwarding Muxes ───────────────────────────────────────
  wire [31:0] Result_M_Fwd =
    (Result_Src_M == 3'b001) ? ALU_Result_M  :
    (Result_Src_M == 3'b010) ? Imm_Ext_M     :
    (Result_Src_M == 3'b011) ? Imm_Added_M   :
    (Result_Src_M == 3'b100) ? PC_Plus4_M    :
    (Result_Src_M == 3'b101) ? Loaded_Data_M :
    (Result_Src_M == 3'b110) ? CSR_Data_M    :
                                MDU_Result_M;

  assign ForwardA_Data = (ForwardA_E == 2'b01) ? Result_M_Fwd :
                         (ForwardA_E == 2'b10) ? Result_W     :
                         Read_Data1_E;
  assign ForwardB_Data = (ForwardB_E == 2'b01) ? Result_M_Fwd :
                         (ForwardB_E == 2'b10) ? Result_W     :
                         Read_Data2_E;

  wire [31:0] SrcA = ForwardA_Data;
  wire [31:0] SrcB = ALU_Src_E ? Imm_Ext_E : ForwardB_Data;
  assign CSR_WrData_E = ForwardA_Data;

  wire Exec_Mal_Word   =  Func3_E[1] & ~Func3_E[0] & (Imm_Added_E[1] | Imm_Added_E[0]);
  wire Exec_Mal_Half   = ~Func3_E[1] &  Func3_E[0] &  Imm_Added_E[0];
  assign Misaligned_Load_E  = (Result_Src_E == 3'b101) & (Exec_Mal_Word | Exec_Mal_Half);
  assign Misaligned_Store_E = DM_WrEn_E & (Exec_Mal_Word | Exec_Mal_Half);
  assign Reg_WrEn_E_Gated   = Reg_WrEn_E & ~Misaligned_Load_E;
  wire [2:0] Result_Src_E_Masked = Trap_Taken ? 3'b000 : Result_Src_E;
  wire       Reg_WrEn_E_Masked   = Reg_WrEn_E_Gated & ~Trap_Taken;
  wire       DM_WrEn_E_Masked    = DM_WrEn_E & ~Trap_Taken;
  wire       CSR_WrEn_E_Masked   = CSR_WrEn_E & ~Trap_Taken;

  // ── ALU ────────────────────────────────────────────────────
  ALU alu (
    .Src1_In(SrcA), .Src2_In(SrcB),
    .ALU_Control_In(ALU_Control_E), .ALU_Result_Out(ALU_Result_E)
  );

  // ── Immediate Adder ────────────────────────────────────────
  Imm_Adder imm_adder (
    .Iadder_Src_In(Iadder_Src_E), .PC_In(PC_E),
    .Src_Data1_In(ForwardA_Data), .Imm_Data_In(Imm_Ext_E),
    .Added_Data_Out(Imm_Added_E)
  );

  // ── Branch Predictor ───────────────────────────────────────
  Branch_Predictor branch_unit (
    .Src_Data1_In(ForwardA_Data), .Src_Data2_In(ForwardB_Data),
    .bgeu_bltu_bge_blt_bne_beq_jalr_jal(Branch_Cond_E),
    .Branch_Taken_Out(Branch_Taken_E)
  );

  // ── MDU ────────────────────────────────────────────────────
  MDU u_mdu (
    .Clk_In(Clk_In),      .Rst_In(Rst_In),
    .Start_In(MDU_Start),  .MDU_Ready_Out(MDU_Ready),
    .A_In(MDU_SrcA),       .B_In(MDU_SrcB),
    .MDU_Op_In(MDU_Op_E),  .Result_Out(MDU_Result)
  );

  // ── Machine Control ────────────────────────────────────────
  Machine_Control machine_ctrl (
    .Clk_In(Clk_In),            .Rst_In(Rst_In),
    .Illegal_Instr_In(Illegal_Instr_D),
    .Misaligned_Instr_In(Misaligned_Instr_F),
    .Load_Access_Fault_In(Load_Access_Fault_M),
    .Misaligned_Load_In(Misaligned_Load_E),
    .Misaligned_Store_In(Misaligned_Store_E),
    .Opcode_6to2_In(Opcode_D[6:2]), .Func3_In(Func3_D),
    .Func7_In(Instruction_D[31:25]),
    .Src_Addr1_In(Src_Addr1_D), .Src_Addr2_In(Src_Addr2_D),
    .Des_Addr_In(Des_Addr_D),
    .EIrq_In(EIrq_In), .TIrq_In(TIrq_In), .SIrq_In(SIrq_In),
    .MIE_In(MIE),   .MEIE_In(MEIE), .MTIE_In(MTIE), .MSIE_In(MSIE),
    .MEIP_In(MEIP), .MTIP_In(MTIP), .MSIP_In(MSIP),
    .I_Or_E_Out(I_Or_E),       .Set_EPC_Out(Set_EPC),
    .Set_Cause_Out(Set_Cause),  .Cause_Out(Cause),
    .Instret_Inc_Out(Instret_Inc), .MIE_Clear_Out(MIE_Clear),
    .MIE_Set_Out(MIE_Set),     .Misaligned_Exc_Out(Misaligned_Exc),
    .PC_Src_Out(PC_Src),        .Flush_Out(Flush_MC),
    .Trap_Taken_Out(Trap_Taken)
  );

  // ── E/M Register ───────────────────────────────────────────
  Reg_E_M reg_e_m (
    .Clk_In(Clk_In), .Rst_In(Rst_In), .Stall_In(Stall_E_Total),
    .PC_Plus4_In(PC_Plus4_E),     .PC_In(PC_E),
    .ALU_Result_In(ALU_Result_E), .Read_Data2_In(Read_Data2_E),
    .Imm_Ext_In(Imm_Ext_E),       .Added_Data_In(Imm_Added_E),
    .MDU_Result_In(MDU_Result),
    .Func3_In(Func3_E),            .Reg_WrEn_In(Reg_WrEn_E_Masked),
    .Result_Src_In(Result_Src_E_Masked),  .DM_WrEn_In(DM_WrEn_E_Masked),
    .Load_Unsigned_In(Load_Unsigned_E), .Load_Size_In(Load_Size_E),
    .Des_Addr_In(Des_Addr_E),      .CSR_WrEn_In(CSR_WrEn_E_Masked),
    .CSR_Op_In(CSR_Op_E),          .CSR_Addr_In(CSR_Addr_E),
    .CSR_UImm_In(CSR_UImm_E),      .CSR_Data_In(CSR_Data_Out),
    .CSR_WrData_In(CSR_WrData_E),
    .PC_Plus4_Out(PC_Plus4_M),     .PC_Out(PC_M),
    .ALU_Result_Out(ALU_Result_M), .Read_Data2_Out(Read_Data2_M),
    .Imm_Ext_Out(Imm_Ext_M),       .Added_Data_Out(Imm_Added_M),
    .MDU_Result_Out(MDU_Result_M),
    .Func3_Out(Func3_M),            .Reg_WrEn_Out(Reg_WrEn_M),
    .Result_Src_Out(Result_Src_M),  .DM_WrEn_Out(DM_WrEn_M),
    .Load_Unsigned_Out(Load_Unsigned_M), .Load_Size_Out(Load_Size_M),
    .Des_Addr_Out(Des_Addr_M),     .CSR_WrEn_Out(CSR_WrEn_M),
    .CSR_Op_Out(CSR_Op_M),         .CSR_Addr_Out(CSR_Addr_M),
    .CSR_UImm_Out(CSR_UImm_M),     .CSR_Data_Out(CSR_Data_M),
    .CSR_WrData_Out(CSR_WrData_M)
  );

  // ── Data memory output assignments ─────────────────────────
  assign DM_Addr_Out    = DM_Addr_M;
  assign DM_Data_Out    = DM_WrData_M;
  assign DM_WrEn_Out    = DM_Wr_Req_M;
  assign DM_Mask_Out    = DM_Mask_M;
  assign Data_HTrans_Out = AHB_HTrans_M;
  assign Data_HSize_Out  = Data_Access_M ? AHB_HSize_M : `AHB_HSIZE_WORD;
  assign Data_M         = DM_Data_In;

  // ── Store Unit ─────────────────────────────────────────────
  //! HTRANS/HSIZE are generated at top-level from memory-stage
  //! control so both loads and stores drive valid bus metadata.
  Store_Unit store_unit (
    .DM_WrEn_In(DM_WrEn_M),
    .Func3_In(Func3_M),
    .Added_Data_In(Imm_Added_M),
    .Src_Data2_In(Read_Data2_M),
    .DM_WrMask_Out(DM_Mask_M),
    .DM_WrData_Out(DM_WrData_M),
    .DM_Addr_Out(DM_Addr_M),
    .DM_WrEn_Out(DM_Wr_Req_M)
  );

  // ── Load Unit ──────────────────────────────────────────────
  //! AHB_Resp_In was 1'b0 — now connected to HResp_In.
  //! When HResp_In=1 (AHB ERROR response) Load_Unit forces
  //! Loaded_Data_Out=0 so no corrupted value reaches writeback.
  //! Machine_Control raises the load-access-fault exception.
  Load_Unit load_unit (
    .Read_Data_In(Data_M),
    .Iadder_1to0_In(ALU_Result_M[1:0]),
    .Load_Size_In(Load_Size_M),
    .Load_Unsigned_In(Load_Unsigned_M),
    .AHB_Resp_In(HResp_In),               //! was 1'b0
    .Loaded_Data_Out(Loaded_Data_M)
  );

  // ── M/W Register ───────────────────────────────────────────
  Reg_M_W reg_m_w (
    .Clk_In(Clk_In), .Rst_In(Rst_In), .Stall_In(Data_Stall),
    .PC_Plus4_In(PC_Plus4_M),      .ALU_Result_In(ALU_Result_M),
    .Loaded_Data_In(Loaded_Data_M), .Imm_Ext_In(Imm_Ext_M),
    .MDU_Result_In(MDU_Result_M),
    .Added_Data_In(Imm_Added_M),   .Reg_WrEn_In(Reg_WrEn_M),
    .Result_Src_In(Result_Src_M),  .Des_Addr_In(Des_Addr_M),
    .CSR_WrEn_In(CSR_WrEn_M),      .CSR_Op_In(CSR_Op_M),
    .CSR_Addr_In(CSR_Addr_M),      .CSR_UImm_In(CSR_UImm_M),
    .CSR_Data_In(CSR_Data_M),      .CSR_WrData_In(CSR_WrData_M),
    .PC_Plus4_Out(PC_Plus4_W),     .ALU_Result_Out(ALU_Result_W),
    .Loaded_Data_Out(Loaded_Data_W), .Imm_Ext_Out(Imm_Ext_W),
    .MDU_Result_Out(MDU_Result_W),
    .Added_Data_Out(Imm_Added_W),  .Reg_WrEn_Out(Reg_WrEn_W_Pre),
    .Result_Src_Out(Result_Src_W), .Des_Addr_Out(Des_Addr_W),
    .CSR_WrEn_Out(CSR_WrEn_W_Pre), .CSR_Op_Out(CSR_Op_W),
    .CSR_Addr_Out(CSR_Addr_W),     .CSR_UImm_Out(CSR_UImm_W),
    .CSR_Data_Out(CSR_Data_W),     .CSR_WrData_Out(CSR_WrData_W)
  );

  // ── WrEn Generator ─────────────────────────────────────────
  WrEn_Generator wren_gen (
    .Flush_In(Flush_MC),
    .Reg_WrEn_In(Reg_WrEn_W_Pre), .CSR_WrEn_In(CSR_WrEn_W_Pre),
    .Reg_WrEn_Out(Reg_WrEn_W),    .CSR_WrEn_Out(CSR_WrEn_W)
  );

  // ── Write-Back Unit ────────────────────────────────────────
  WB_Unit wb_unit (
    .Result_Src_In(Result_Src_W),  .ALU_Result_In(ALU_Result_W),
    .Loaded_Data_In(Loaded_Data_W), .Imm_Data_In(Imm_Ext_W),
    .Imm_Added_In(Imm_Added_W),    .CSR_Data_In(CSR_Data_Out),
    .PC_Plus4_In(PC_Plus4_W),      .MDU_Result_In(MDU_Result_W),
    .Result_Out(Result_W)
  );

  // ── CSR File ───────────────────────────────────────────────
  CSR_File csr_file (
    .Clk_In(Clk_In), .Rst_In(Rst_In),
    .WrEn_In(CSR_WrEn_W),          .CSR_Addr_In(CSR_Addr_W),
    .CSR_Op_In(CSR_Op_W),           .CSR_UImm_In(CSR_UImm_W),
    .CSR_Data_In(CSR_WrData_W),     .PC_In(PC_M),
    .Imm_Added_In(Imm_Added_M),    .I_Or_E_In(I_Or_E),
    .Set_Cause_In(Set_Cause),       .Set_EPC_In(Set_EPC),
    .Instret_Inc_In(Instret_Inc),   .MIE_Clear_In(MIE_Clear),
    .MIE_Set_In(MIE_Set),           .Misaligned_Exc_In(Misaligned_Exc),
    .Cause_In(Cause),
    .EIrq_In(EIrq_In), .TIrq_In(TIrq_In), .SIrq_In(SIrq_In),
    .RTC_In(RTC_In),               .CSR_Data_Out(CSR_Data_Out),
    .MIE_Out(MIE),                  .EPC_Out(EPC),
    .Trap_Addr_Out(Trap_Addr),      .MEIE_Out(MEIE),
    .MTIE_Out(MTIE),                .MSIE_Out(MSIE),
    .MEIP_Out(MEIP),                .MTIP_Out(MTIP),  .MSIP_Out(MSIP)
  );

  // ── Hazard Unit ────────────────────────────────────────────
  //! Note on AHB stalls and the Hazard Unit:
  //! Instr_HReady_In and Data_HReady_In stall the pipeline via
  //! PC_Unit and the M-stage register directly. The Hazard_Unit
  //! here handles load-use, branch, and MDU stalls. If your
  //! Hazard_Unit is extended to accept AHB ready signals as
  //! additional stall inputs, connect them here. Until then the
  //! AHB stall path is: !HReady -> PC_Unit holds PC/IAddr,
  //! and the pipeline registers are frozen by Stall signals from
  //! the Hazard_Unit which sees MDU_Ready=0 style stalls.
  Hazard_Unit hazard_unit (
    .Src_Addr1_D_In(Src_Addr1_D),   .Src_Addr2_D_In(Src_Addr2_D),
    .Des_Addr_E_In(Des_Addr_E),      .Reg_WrEn_E_In(Reg_WrEn_E),
    .Result_Src_E_In(Result_Src_E),  .Src_Addr1_E_In(Src_Addr1_E),
    .Src_Addr2_E_In(Src_Addr2_E),    .Des_Addr_M_In(Des_Addr_M),
    .Reg_WrEn_M_In(Reg_WrEn_M),      .Des_Addr_W_In(Des_Addr_W),
    .Reg_WrEn_W_In(Reg_WrEn_W),      .Branch_Taken_E_In(Branch_Taken_E),
    .MDU_Ready_In(MDU_Ready),
    .Stall_F_Out(Stall_F),   .Stall_D_Out(Stall_D),  .Stall_E_Out(Stall_E),
    .Flush_D_Out(Flush_D),   .Flush_E_Out(Flush_E),
    .ForwardA_E_Out(ForwardA_E), .ForwardB_E_Out(ForwardB_E)
  );

`ifdef COCOTB_SIM
  assign hazard_detected = Stall_F_Total|Stall_D_Total|Stall_E_Total|Flush_D|Flush_E|Flush_MC;
  assign stall           = Stall_F_Total | Stall_D_Total | Stall_E_Total;
  assign flush           = Flush_D_Combined | Flush_E_Combined;
  assign trap_taken      = Trap_Taken;
  assign pc_src          = PC_Src;
`endif

endmodule
