//! Machine Trap Cause Register (mcause)
//! Records the cause of the most recent trap taken by the machine.
//!
//! mcause layout:
//!   [31]   = Interrupt (1) or Exception (0)
//!   [30:4] = cause_rem — reserved/zero in hardware traps, writable by SW
//!   [3:0]  = cause code
//!
//! Three sources of update (priority order):
//!   1. Synchronous reset — zeros all fields
//!   2. Set_Cause_In (from Machine_Control on trap entry) — atomically
//!      latches I_Or_E_In and Cause_In; zeros cause_rem
//!   3. Direct CSR write — full 32-bit write from software (e.g. in trap handler)
//!
//! The registered cause and int_or_exc values are fed back to MTVec_Reg
//! so the vectored trap address can be computed from the same latched cause.
module MCause_Reg (
  input         Clk_In,        //! Clock input
  input         Rst_In,        //! Synchronous reset — clears cause and int/exc flag
  input         Set_Cause_In,  //! Trap entry: latch I_Or_E_In and Cause_In
  input         I_Or_E_In,     //! 1=interrupt, 0=exception (from Machine_Control)
  input         WrEn_In,       //! CSR file write enable (gated by flush upstream)
  input  [3:0]  Cause_In,      //! Trap cause code (from Machine_Control)
  input  [31:0] Data_Wr_In,    //! Write data (from CSR_Data_Wr_Mux)
  input  [11:0] CSR_Addr_In,   //! CSR address — must equal MCAUSE to write
  output [31:0] MCause_Out,    //! Full 32-bit mcause read value
  output reg [3:0]  Cause_Out,      //! Registered cause code — fed to MTVec_Reg for vectoring
  output reg        Int_Or_Exc_Out  //! Registered interrupt/exception flag — fed to MTVec_Reg
);

  // ============================================================
  //! CSR Address
  // ============================================================
  localparam MCAUSE_ADDR = 12'h342;

  // ============================================================
  //! Internal State
  // ============================================================
  reg [26:0] Cause_Rem;  //! mcause[30:4] — software-writable, zero on hardware trap

  // ============================================================
  //! mcause Read Value
  // ============================================================
  assign MCause_Out = {Int_Or_Exc_Out, Cause_Rem, Cause_Out};

  // ============================================================
  //! Register Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      Cause_Out     <= 4'b0;
      Cause_Rem     <= 27'b0;
      Int_Or_Exc_Out<= 1'b0;
    end
    else if (Set_Cause_In) begin
      //! Hardware trap: record cause, zero the reserved middle field
      Cause_Out      <= Cause_In;
      Cause_Rem      <= 27'b0;
      Int_Or_Exc_Out <= I_Or_E_In;
    end
    else if (CSR_Addr_In == MCAUSE_ADDR && WrEn_In) begin
      //! Software write: full field update (e.g. trap handler cleanup)
      Cause_Out      <= Data_Wr_In[3:0];
      Cause_Rem      <= Data_Wr_In[30:4];
      Int_Or_Exc_Out <= Data_Wr_In[31];
    end
  end

endmodule
