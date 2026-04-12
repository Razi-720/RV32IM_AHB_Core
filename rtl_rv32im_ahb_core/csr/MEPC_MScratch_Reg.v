//! Machine Exception PC (mepc) and Machine Scratch (mscratch) Registers
//! Two independent CSRs sharing one module since they have similar structure.
//!
//! mscratch (0x340): General-purpose scratch register for machine-mode
//!   trap handlers. Updated only by direct CSR writes.
//!
//! mepc (0x341): Holds the PC of the instruction that caused a trap.
//!   Three sources of update (priority order):
//!     1. Synchronous reset
//!     2. Set_EPC_In (from Machine_Control on trap entry) — latches PC_In
//!     3. Direct CSR write — MEPC is word-aligned: bits [1:0] forced to 00
//!
//! EPC_Out is a direct wire alias of MEPC, fed to the PC unit for MRET.
module MEPC_MScratch_Reg (
  input         Clk_In,       //! Clock input
  input         Rst_In,       //! Synchronous reset — zeros both registers
  input         WrEn_In,      //! CSR file write enable (gated by flush upstream)
  input         Set_EPC_In,   //! Trap entry: latch current PC into MEPC
  input  [31:0] PC_In,        //! Current PC value (from Machine_Control on trap)
  input  [31:0] Data_Wr_In,   //! Write data (from CSR_Data_Wr_Mux)
  input  [11:0] CSR_Addr_In,  //! CSR address — selects MSCRATCH or MEPC
  output reg [31:0] MScratch_Out, //! mscratch read value
  output reg [31:0] MEPC_Out,     //! mepc internal register
  output     [31:0] EPC_Out       //! EPC wired to PC unit for MRET return address
);

  // ============================================================
  //! CSR Addresses
  // ============================================================
  localparam MSCRATCH_ADDR = 12'h340;
  localparam MEPC_ADDR     = 12'h341;

  // ============================================================
  //! Reset Values
  // ============================================================
  localparam MSCRATCH_RESET = 32'h0000_0000;
  localparam MEPC_RESET     = 32'h0000_0000;

  // ============================================================
  //! EPC Output — direct alias of MEPC register
  // ============================================================
  assign EPC_Out = MEPC_Out;

  // ============================================================
  //! MScratch Register Update
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In)
      MScratch_Out <= MSCRATCH_RESET;
    else if (CSR_Addr_In == MSCRATCH_ADDR && WrEn_In)
      MScratch_Out <= Data_Wr_In;
  end

  // ============================================================
  //! MEPC Register Update
  //! Word-aligned on CSR write: spec requires bits [1:0] = 00
  //! (IALIGN=32, so the bottom two bits of a return address are always 0)
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In)
      MEPC_Out <= MEPC_RESET;
    else if (Set_EPC_In)
      MEPC_Out <= PC_In;
    else if (CSR_Addr_In == MEPC_ADDR && WrEn_In)
      MEPC_Out <= {Data_Wr_In[31:2], 2'b00};
  end

endmodule
