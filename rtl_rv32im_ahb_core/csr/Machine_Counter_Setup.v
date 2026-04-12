//! Machine Counter-Inhibit Register (mcountinhibit)
//! Controls which performance counters are allowed to increment.
//! Only two bits are implemented:
//!   CY (bit 2) — inhibit mcycle  from incrementing when 1
//!   IR (bit 0) — inhibit minstret from incrementing when 1
//! Bit 1 is hardwired to 0 (no TM counter in this implementation).
//!
//! The individual inhibit bits are exposed as scalar outputs so
//! Machine_Counter can gate its increment logic directly.
module Machine_Counter_Setup (
  input         Clk_In,               //! Clock input
  input         Rst_In,               //! Synchronous reset — disables both inhibits (counters run)
  input         WrEn_In,              //! CSR file write enable (gated by flush upstream)
  input         Data_Wr_2_In,         //! Write data bit 2 — new CY inhibit value
  input         Data_Wr_0_In,         //! Write data bit 0 — new IR inhibit value
  input  [11:0] CSR_Addr_In,          //! CSR address — must equal MCOUNTINHIBIT to write
  output reg    MCountInhibit_CY_Out, //! Cycle-counter inhibit bit — fed to Machine_Counter
  output reg    MCountInhibit_IR_Out, //! Instret-counter inhibit bit — fed to Machine_Counter
  output [31:0] MCountInhibit_Out     //! Full 32-bit mcountinhibit read value
);

  // ============================================================
  //! CSR Address
  // ============================================================
  localparam MCOUNTINHIBIT_ADDR = 12'h320;

  // ============================================================
  //! Reset Values — both inhibits off (counters increment freely)
  // ============================================================
  localparam CY_RESET = 1'b0;
  localparam IR_RESET = 1'b0;

  // ============================================================
  //! mcountinhibit Read Value
  //! [31:3] = 0, [2] = CY, [1] = 0 (no TM), [0] = IR
  // ============================================================
  assign MCountInhibit_Out = {29'b0, MCountInhibit_CY_Out, 1'b0, MCountInhibit_IR_Out};

  // ============================================================
  //! Register Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      MCountInhibit_CY_Out <= CY_RESET;
      MCountInhibit_IR_Out <= IR_RESET;
    end
    else if (CSR_Addr_In == MCOUNTINHIBIT_ADDR && WrEn_In) begin
      MCountInhibit_CY_Out <= Data_Wr_2_In;
      MCountInhibit_IR_Out <= Data_Wr_0_In;
    end
  end

endmodule
