//! CSR Read Data Mux
//! Selects which CSR register value to present on the read data bus
//! based on the 12-bit CSR address. All standard machine-mode and
//! unprivileged counter CSRs defined in the RISC-V spec are supported.
module CSR_Data_Mux_Unit (
  input      [11:0] CSR_Addr_In,        //! CSR address from instruction [31:20]

  //! 64-bit counter inputs (split into high/low 32-bit halves by this mux)
  input      [63:0] MCycle_In,           //! Machine cycle counter
  input      [63:0] MTime_In,            //! Real-time counter shadow
  input      [63:0] MInstret_In,         //! Machine instructions-retired counter

  //! 32-bit CSR register inputs
  input      [31:0] MScratch_In,         //! Machine scratch register
  input      [31:0] MIP_In,              //! Machine interrupt pending register
  input      [31:0] MTVal_In,            //! Machine trap value register
  input      [31:0] MCause_In,           //! Machine trap cause register
  input      [31:0] MEPC_In,             //! Machine exception program counter
  input      [31:0] MTVec_In,            //! Machine trap-vector base register
  input      [31:0] MStatus_In,          //! Machine status register
  input      [31:0] MISA_In,             //! Machine ISA register
  input      [31:0] MIE_In,              //! Machine interrupt enable register
  input      [31:0] MCountInhibit_In,    //! Machine counter-inhibit register

  output reg [31:0] CSR_Data_Out         //! Selected CSR read data
);

  // ============================================================
  //! CSR Address Map — Unprivileged Counters (read-only shadows)
  // ============================================================
  localparam CYCLE     = 12'hC00;  //! Cycle counter low
  localparam TIME      = 12'hC01;  //! Real-time counter low
  localparam INSTRET   = 12'hC02;  //! Instructions-retired low
  localparam CYCLEH    = 12'hC80;  //! Cycle counter high
  localparam TIMEH     = 12'hC81;  //! Real-time counter high
  localparam INSTRETH  = 12'hC82;  //! Instructions-retired high

  // ============================================================
  //! CSR Address Map — Machine Trap Setup
  // ============================================================
  localparam MSTATUS   = 12'h300;  //! Machine status
  localparam MISA      = 12'h301;  //! Machine ISA and extensions
  localparam MIE       = 12'h304;  //! Machine interrupt enable
  localparam MTVEC     = 12'h305;  //! Machine trap-vector base

  // ============================================================
  //! CSR Address Map — Machine Trap Handling
  // ============================================================
  localparam MSCRATCH  = 12'h340;  //! Machine scratch
  localparam MEPC      = 12'h341;  //! Machine exception PC
  localparam MCAUSE    = 12'h342;  //! Machine trap cause
  localparam MTVAL     = 12'h343;  //! Machine trap value
  localparam MIP       = 12'h344;  //! Machine interrupt pending

  // ============================================================
  //! CSR Address Map — Machine Counters / Timers
  // ============================================================
  localparam MCYCLE    = 12'hB00;  //! Machine cycle counter low
  localparam MCYCLEH   = 12'hB80;  //! Machine cycle counter high
  localparam MINSTRET  = 12'hB02;  //! Machine instret low
  localparam MINSTRETH = 12'hB82;  //! Machine instret high

  // ============================================================
  //! CSR Address Map — Machine Counter Setup
  // ============================================================
  localparam MCOUNTINHIBIT = 12'h320;  //! Machine counter-inhibit

  // ============================================================
  //! Read Data Mux
  // ============================================================
  always @* begin
    case (CSR_Addr_In)
      CYCLE:        CSR_Data_Out = MCycle_In[31:0];
      CYCLEH:       CSR_Data_Out = MCycle_In[63:32];
      TIME:         CSR_Data_Out = MTime_In[31:0];
      TIMEH:        CSR_Data_Out = MTime_In[63:32];
      INSTRET:      CSR_Data_Out = MInstret_In[31:0];
      INSTRETH:     CSR_Data_Out = MInstret_In[63:32];
      MSTATUS:      CSR_Data_Out = MStatus_In;
      MISA:         CSR_Data_Out = MISA_In;
      MIE:          CSR_Data_Out = MIE_In;
      MTVEC:        CSR_Data_Out = MTVec_In;
      MSCRATCH:     CSR_Data_Out = MScratch_In;
      MEPC:         CSR_Data_Out = MEPC_In;
      MCAUSE:       CSR_Data_Out = MCause_In;
      MTVAL:        CSR_Data_Out = MTVal_In;
      MIP:          CSR_Data_Out = MIP_In;
      MCYCLE:       CSR_Data_Out = MCycle_In[31:0];
      MCYCLEH:      CSR_Data_Out = MCycle_In[63:32];
      MINSTRET:     CSR_Data_Out = MInstret_In[31:0];
      MINSTRETH:    CSR_Data_Out = MInstret_In[63:32];
      MCOUNTINHIBIT:CSR_Data_Out = MCountInhibit_In;
      default:      CSR_Data_Out = 32'b0;
    endcase
  end

endmodule
