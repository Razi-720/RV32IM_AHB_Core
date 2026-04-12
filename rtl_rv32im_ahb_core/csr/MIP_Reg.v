//! Machine Interrupt Pending Register (mip)
//! Samples the three external interrupt request lines on every rising
//! clock edge and reflects them as the corresponding pending bits.
//! mip is read-only from software in this implementation — the pending
//! bits are set by hardware (external interrupt controller) only.
//!
//! Implemented bits:
//!   MEIP (bit 11) — machine external interrupt pending
//!   MTIP (bit  7) — machine timer interrupt pending
//!   MSIP (bit  3) — machine software interrupt pending
//! All other bits are hardwired to zero.
module MIP_Reg (
  input         Clk_In,      //! Clock input
  input         Rst_In,      //! Synchronous reset — clears all pending bits
  input         EIrq_In,     //! External interrupt request line → MEIP
  input         TIrq_In,     //! Timer interrupt request line    → MTIP
  input         SIrq_In,     //! Software interrupt request line → MSIP
  output        MEIP_Out,    //! Machine external interrupt pending (routed to Machine_Control)
  output        MTIP_Out,    //! Machine timer interrupt pending    (routed to Machine_Control)
  output        MSIP_Out,    //! Machine software interrupt pending (routed to Machine_Control)
  output [31:0] MIP_Reg_Out  //! Full 32-bit mip read value
);

  // ============================================================
  //! Internal State — registered interrupt pending bits
  // ============================================================
  reg MEIP;  //! Machine external interrupt pending
  reg MTIP;  //! Machine timer interrupt pending
  reg MSIP;  //! Machine software interrupt pending

  // ============================================================
  //! mip Read Value
  //! [31:12] = 0, [11] = MEIP, [10:8] = 0,
  //! [7] = MTIP, [6:4] = 0, [3] = MSIP, [2:0] = 0
  // ============================================================
  assign MIP_Reg_Out = {20'b0, MEIP, 3'b0, MTIP, 3'b0, MSIP, 3'b0};
  assign MEIP_Out    = MEIP;
  assign MTIP_Out    = MTIP;
  assign MSIP_Out    = MSIP;

  // ============================================================
  //! Register Update Logic
  //! Pending bits are directly sampled from interrupt request lines.
  //! No masking with MIE is done here — that is handled in Machine_Control.
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      MEIP <= 1'b0;
      MTIP <= 1'b0;
      MSIP <= 1'b0;
    end
    else begin
      MEIP <= EIrq_In;
      MTIP <= TIrq_In;
      MSIP <= SIrq_In;
    end
  end

endmodule
