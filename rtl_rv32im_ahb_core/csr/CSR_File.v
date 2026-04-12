// `include "CSR_Data_Mux_Unit.v"
// `include "Data_Wr_Mux_Unit.v"
// `include "MISA_PreData_Unit.v"
// `include "MStatus_Reg.v"
// `include "MIE_Reg.v"
// `include "MIP_Reg.v"
// `include "MTVec_Reg.v"
// `include "MEPC_MScratch_Reg.v"
// `include "MCause_Reg.v"
// `include "MTVal_Reg.v"
// `include "Machine_Counter_Setup.v"
// `include "Machine_Counter.v"

//! CSR File — Control and Status Register File for RV32I+Zicsr
//! Top-level wrapper that instantiates all CSR sub-registers and the
//! two data-path mux units. Exposes a single read/write interface to
//! the pipeline and individual status/enable outputs to Machine_Control.
//!
//! Implemented CSRs:
//!   Machine Trap Setup:    mstatus (0x300), misa (0x301), mie (0x304), mtvec (0x305)
//!   Machine Trap Handling: mscratch (0x340), mepc (0x341), mcause (0x342),
//!                          mtval (0x343), mip (0x344)
//!   Machine Counters:      mcycle/h (0xB00/B80), minstret/h (0xB02/B82)
//!   Unprivileged Shadows:  cycle/h (0xC00/C80), time/h (0xC01/C81), instret/h (0xC02/C82)
//!   Counter Setup:         mcountinhibit (0x320)
module CSR_File (
  input         Clk_In,              //! Clock input
  input         Rst_In,              //! Synchronous reset
  input         WrEn_In,             //! CSR write enable — gated by WrEn_Generator upstream
  input  [11:0] CSR_Addr_In,         //! CSR address from instruction [31:20]
  input  [2:0]  CSR_Op_In,           //! CSR operation (funct3): RW/RS/RC and immediate variants
  input  [4:0]  CSR_UImm_In,         //! 5-bit unsigned immediate from instruction [19:15]
  input  [31:0] CSR_Data_In,         //! RS1 register data (used when CSR_Op[2]=0)

  //! Trap context inputs (from Machine_Control)
  input  [31:0] PC_In,               //! PC of trapping instruction — latched into mepc
  input  [31:0] Imm_Added_In,        //! Effective address — latched into mtval on misaligned exc
  input         I_Or_E_In,           //! 1=interrupt, 0=exception — written to mcause[31]
  input         Set_Cause_In,        //! Latch Cause_In and I_Or_E_In into mcause on trap entry
  input         Set_EPC_In,          //! Latch PC_In into mepc on trap entry
  input         Instret_Inc_In,       //! Pulse per retired instruction — increments minstret
  input         MIE_Clear_In,         //! Trap entry: save MIE→MPIE, clear MIE
  input         MIE_Set_In,           //! Trap return (MRET): restore MIE←MPIE
  input         Misaligned_Exc_In,    //! 1=misaligned address exception, store addr in mtval
  input  [3:0]  Cause_In,             //! Trap cause code — written to mcause[3:0]

  //! External interrupt request lines
  input         EIrq_In,             //! External interrupt request
  input         TIrq_In,             //! Timer interrupt request
  input         SIrq_In,             //! Software interrupt request

  //! Real-time counter
  input  [63:0] RTC_In,              //! External real-time counter (mapped to mtime)

  //! Read data output
  output [31:0] CSR_Data_Out,        //! Selected CSR register read value

  //! Outputs to Machine_Control / PC_Unit
  output        MIE_Out,             //! Global machine interrupt enable (mstatus.MIE)
  output [31:0] EPC_Out,             //! Exception return address (mepc) → PC_Unit
  output [31:0] Trap_Addr_Out,       //! Trap handler address (mtvec) → PC_Unit

  //! Individual interrupt enable bits → Machine_Control
  output        MEIE_Out,            //! Machine external interrupt enable
  output        MTIE_Out,            //! Machine timer interrupt enable
  output        MSIE_Out,            //! Machine software interrupt enable

  //! Individual interrupt pending bits → Machine_Control
  output        MEIP_Out,            //! Machine external interrupt pending
  output        MTIP_Out,            //! Machine timer interrupt pending
  output        MSIP_Out             //! Machine software interrupt pending
);

  // ============================================================
  //! Internal Wires — CSR Register Read Values
  // ============================================================
  wire [31:0] MStatus;       //! mstatus register value
  wire [31:0] MISA;          //! misa register value (hardwired)
  wire [31:0] MIE_Reg;       //! mie register value
  wire [31:0] MTVec;         //! mtvec register value
  wire [31:0] MScratch;      //! mscratch register value
  wire [31:0] MEPC;          //! mepc register value
  wire [31:0] MCause;        //! mcause register value
  wire [31:0] MTVal;         //! mtval register value
  wire [31:0] MIP_Reg;       //! mip register value
  wire [31:0] MCountInhibit; //! mcountinhibit register value
  wire [63:0] MCycle;        //! mcycle counter value
  wire [63:0] MTime;         //! mtime shadow value
  wire [63:0] MInstret;      //! minstret counter value

  // ============================================================
  //! Internal Wires — CSR Data Path
  // ============================================================
  wire [31:0] Pre_Data;  //! Selected write source (RS1 or zero-ext uimm)
  wire [31:0] Data_Wr;   //! Computed value to write into target CSR

  // ============================================================
  //! Internal Wires — Trap Cause Feedback
  //! Registered cause and int/exc flag from MCause_Reg fed back
  //! to MTVec_Reg so the vectored trap address uses the latched cause.
  // ============================================================
  wire [3:0] Cause_Latched;    //! Registered cause code from MCause_Reg
  wire       Int_Or_Exc;       //! Registered int/exc flag from MCause_Reg

  // ============================================================
  //! Internal Wires — Counter Inhibit
  // ============================================================
  wire MCountInhibit_CY;  //! Cycle counter inhibit scalar
  wire MCountInhibit_IR;  //! Instret counter inhibit scalar

  // ============================================================
  //! MISA and Pre-Data Source Unit
  //! Generates the hardwired misa value and selects the CSR write source.
  // ============================================================
  MISA_PreData_Unit misa_predata (
    .CSR_Op_2_In  (CSR_Op_In[2]),
    .CSR_UImm_In  (CSR_UImm_In),
    .CSR_Data_In  (CSR_Data_In),
    .MISA_Out     (MISA),
    .Pre_Data_Out (Pre_Data)
  );

  // ============================================================
  //! CSR Read Data Mux
  //! Selects the read value from all CSR registers based on CSR_Addr_In.
  // ============================================================
  CSR_Data_Mux_Unit csr_data_mux (
    .CSR_Addr_In      (CSR_Addr_In),
    .MCycle_In        (MCycle),
    .MTime_In         (MTime),
    .MInstret_In      (MInstret),
    .MScratch_In      (MScratch),
    .MIP_In           (MIP_Reg),
    .MTVal_In         (MTVal),
    .MCause_In        (MCause),
    .MEPC_In          (MEPC),
    .MTVec_In         (MTVec),
    .MStatus_In       (MStatus),
    .MISA_In          (MISA),
    .MIE_In           (MIE_Reg),
    .MCountInhibit_In (MCountInhibit),
    .CSR_Data_Out     (CSR_Data_Out)
  );

  // ============================================================
  //! CSR Write Data Mux
  //! Computes the value to write based on operation type (RW/RS/RC).
  //! Feeds back CSR_Data_Out so RS/RC can mask the current value.
  // ============================================================
  Data_Wr_Mux_Unit data_wr_mux (
    .CSR_Op_1_0_In  (CSR_Op_In[1:0]),
    .CSR_Data_Out_In(CSR_Data_Out),
    .Pre_Data_In    (Pre_Data),
    .Data_Wr_Out    (Data_Wr)
  );

  // ============================================================
  //! MStatus Register
  // ============================================================
  MStatus_Reg mstatus_reg (
    .Clk_In       (Clk_In),
    .Rst_In       (Rst_In),
    .WrEn_In      (WrEn_In),
    .Data_Wr_3_In (Data_Wr[3]),
    .Data_Wr_7_In (Data_Wr[7]),
    .MIE_Clear_In (MIE_Clear_In),
    .MIE_Set_In   (MIE_Set_In),
    .CSR_Addr_In  (CSR_Addr_In),
    .MStatus_Out  (MStatus),
    .MIE_Out      (MIE_Out)
  );

  // ============================================================
  //! MIE Register
  // ============================================================
  MIE_Reg mie_reg (
    .Clk_In        (Clk_In),
    .Rst_In        (Rst_In),
    .WrEn_In       (WrEn_In),
    .Data_Wr_11_In (Data_Wr[11]),
    .Data_Wr_7_In  (Data_Wr[7]),
    .Data_Wr_3_In  (Data_Wr[3]),
    .CSR_Addr_In   (CSR_Addr_In),
    .MEIE_Out      (MEIE_Out),
    .MTIE_Out      (MTIE_Out),
    .MSIE_Out      (MSIE_Out),
    .MIE_Reg_Out   (MIE_Reg)
  );

  // ============================================================
  //! MIP Register
  // ============================================================
  MIP_Reg mip_reg (
    .Clk_In     (Clk_In),
    .Rst_In     (Rst_In),
    .EIrq_In    (EIrq_In),
    .TIrq_In    (TIrq_In),
    .SIrq_In    (SIrq_In),
    .MEIP_Out   (MEIP_Out),
    .MTIP_Out   (MTIP_Out),
    .MSIP_Out   (MSIP_Out),
    .MIP_Reg_Out(MIP_Reg)
  );

  // ============================================================
  //! MTVec Register + Trap Address Generator
  // ============================================================
  MTVec_Reg mtvec_reg (
    .Clk_In        (Clk_In),
    .Rst_In        (Rst_In),
    .WrEn_In       (WrEn_In),
    .Int_Or_Exc_In (Int_Or_Exc),
    .Data_Wr_In    (Data_Wr),
    .CSR_Addr_In   (CSR_Addr_In),
    .Cause_In      (Cause_Latched),
    .MTVec_Out     (MTVec),
    .Trap_Addr_Out (Trap_Addr_Out)
  );

  // ============================================================
  //! MEPC and MScratch Registers
  // ============================================================
  MEPC_MScratch_Reg mepc_mscratch_reg (
    .Clk_In       (Clk_In),
    .Rst_In       (Rst_In),
    .WrEn_In      (WrEn_In),
    .Set_EPC_In   (Set_EPC_In),
    .PC_In        (PC_In),
    .Data_Wr_In   (Data_Wr),
    .CSR_Addr_In  (CSR_Addr_In),
    .MScratch_Out (MScratch),
    .MEPC_Out     (MEPC),
    .EPC_Out      (EPC_Out)
  );

  // ============================================================
  //! MCause Register
  // ============================================================
  MCause_Reg mcause_reg (
    .Clk_In        (Clk_In),
    .Rst_In        (Rst_In),
    .Set_Cause_In  (Set_Cause_In),
    .I_Or_E_In     (I_Or_E_In),
    .WrEn_In       (WrEn_In),
    .Cause_In      (Cause_In),
    .Data_Wr_In    (Data_Wr),
    .CSR_Addr_In   (CSR_Addr_In),
    .MCause_Out    (MCause),
    .Cause_Out     (Cause_Latched),
    .Int_Or_Exc_Out(Int_Or_Exc)
  );

  // ============================================================
  //! MTVal Register
  // ============================================================
  MTVal_Reg mtval_reg (
    .Clk_In            (Clk_In),
    .Rst_In            (Rst_In),
    .WrEn_In           (WrEn_In),
    .Set_Cause_In      (Set_Cause_In),
    .Misaligned_Exc_In (Misaligned_Exc_In),
    .Imm_Added_In      (Imm_Added_In),
    .Data_Wr_In        (Data_Wr),
    .CSR_Addr_In       (CSR_Addr_In),
    .MTVal_Out         (MTVal)
  );

  // ============================================================
  //! Machine Counter-Inhibit Register
  // ============================================================
  Machine_Counter_Setup machine_counter_setup (
    .Clk_In              (Clk_In),
    .Rst_In              (Rst_In),
    .WrEn_In             (WrEn_In),
    .Data_Wr_2_In        (Data_Wr[2]),
    .Data_Wr_0_In        (Data_Wr[0]),
    .CSR_Addr_In         (CSR_Addr_In),
    .MCountInhibit_CY_Out(MCountInhibit_CY),
    .MCountInhibit_IR_Out(MCountInhibit_IR),
    .MCountInhibit_Out   (MCountInhibit)
  );

  // ============================================================
  //! Machine Performance Counters
  // ============================================================
  Machine_Counter machine_counter (
    .Clk_In             (Clk_In),
    .Rst_In             (Rst_In),
    .WrEn_In            (WrEn_In),
    .MCountInhibit_CY_In(MCountInhibit_CY),
    .MCountInhibit_IR_In(MCountInhibit_IR),
    .Instret_Inc_In     (Instret_Inc_In),
    .CSR_Addr_In        (CSR_Addr_In),
    .Data_Wr_In         (Data_Wr),
    .RTC_In             (RTC_In),
    .MCycle_Out         (MCycle),
    .MInstret_Out       (MInstret),
    .MTime_Out          (MTime)
  );

endmodule
