//! Machine Trap Value Register (mtval)
//! Provides additional information about a trap to the trap handler.
//! For misaligned address exceptions the faulting address is stored.
//! For all other traps mtval is written to zero on trap entry.
//!
//! Three sources of update (priority order):
//!   1. Synchronous reset — zeros the register
//!   2. Set_Cause_In (from Machine_Control on any trap entry):
//!        If Misaligned_Exc_In=1 → store the faulting effective address (Imm_Added_In)
//!        If Misaligned_Exc_In=0 → store zero (mtval undefined for this trap type)
//!   3. Direct CSR write — software can write any value
module MTVal_Reg (
  input         Clk_In,            //! Clock input
  input         Rst_In,            //! Synchronous reset — zeros mtval
  input         WrEn_In,           //! CSR file write enable (gated by flush upstream)
  input         Set_Cause_In,      //! Trap entry: update mtval with fault address or zero
  input         Misaligned_Exc_In, //! 1=misaligned address exception, stores Imm_Added_In
  input  [31:0] Imm_Added_In,      //! Faulting effective address (from immediate adder)
  input  [31:0] Data_Wr_In,        //! Write data (from CSR_Data_Wr_Mux)
  input  [11:0] CSR_Addr_In,       //! CSR address — must equal MTVAL to write
  output reg [31:0] MTVal_Out       //! mtval read value
);

  // ============================================================
  //! CSR Address
  // ============================================================
  localparam MTVAL_ADDR = 12'h343;

  // ============================================================
  //! Register Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In)
      MTVal_Out <= 32'b0;
    else if (Set_Cause_In) begin
      //! On trap entry: record faulting address or clear to zero
      if (Misaligned_Exc_In)
        MTVal_Out <= Imm_Added_In;
      else
        MTVal_Out <= 32'b0;
    end
    else if (CSR_Addr_In == MTVAL_ADDR && WrEn_In)
      MTVal_Out <= Data_Wr_In;
  end

endmodule
