//! Machine Status Register (mstatus)
//! Implements the machine-mode subset of mstatus for RV32I+Zicsr.
//! Only the MIE (bit 3) and MPIE (bit 7) fields are implemented.
//! MPP is hardwired to 2'b11 (machine mode only).
//!
//! Priority of updates (highest to lowest):
//!   1. Synchronous reset
//!   2. Direct CSR write (CSRRW/CSRRS/CSRRC via wr_en + addr match)
//!   3. MIE_Clear_In — trap entry: saves MIE into MPIE, clears MIE
//!   4. MIE_Set_In   — trap return (MRET): restores MIE from MPIE, sets MPIE=1
module MStatus_Reg (
  input         Clk_In,         //! Clock input
  input         Rst_In,         //! Synchronous reset — clears MIE, sets MPIE=1
  input         WrEn_In,        //! CSR file write enable (gated by flush upstream)
  input         Data_Wr_3_In,   //! Write data bit 3  — new MIE  value on CSR write
  input         Data_Wr_7_In,   //! Write data bit 7  — new MPIE value on CSR write
  input         MIE_Clear_In,   //! Trap entry:  atomically move MIE→MPIE, MIE←0
  input         MIE_Set_In,     //! Trap return: atomically move MPIE→MIE, MPIE←1
  input  [11:0] CSR_Addr_In,    //! CSR address — must equal MSTATUS to write
  output [31:0] MStatus_Out,    //! Full 32-bit mstatus read value
  output reg    MIE_Out         //! Machine interrupt enable bit (bit 3) — routed to Machine_Control
);

  // ============================================================
  //! CSR Address
  // ============================================================
  localparam MSTATUS = 12'h300;

  // ============================================================
  //! Internal State
  // ============================================================
  reg MPIE;  //! Machine prior interrupt enable (bit 7 of mstatus)

  // ============================================================
  //! mstatus Read Value
  //! [31:13] = 0 (not implemented)
  //! [12:11] = MPP = 2'b11 (hardwired — machine mode only)
  //! [10:8]  = 0
  //! [7]     = MPIE
  //! [6:4]   = 0
  //! [3]     = MIE
  //! [2:0]   = 0
  // ============================================================
  assign MStatus_Out = {19'b0, 2'b11, 3'b0, MPIE, 3'b0, MIE_Out, 3'b0};

  // ============================================================
  //! Register Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      MIE_Out <= 1'b0;
      MPIE    <= 1'b1;
    end
    else if (CSR_Addr_In == MSTATUS && WrEn_In) begin
      //! Direct CSR write — highest runtime priority
      MIE_Out <= Data_Wr_3_In;
      MPIE    <= Data_Wr_7_In;
    end
    else if (MIE_Clear_In) begin
      //! Trap entry: atomically save and clear MIE
      MPIE    <= MIE_Out;
      MIE_Out <= 1'b0;
    end
    else if (MIE_Set_In) begin
      //! Trap return (MRET): restore MIE from MPIE, reset MPIE to 1
      MIE_Out <= MPIE;
      MPIE    <= 1'b1;
    end
  end

endmodule
