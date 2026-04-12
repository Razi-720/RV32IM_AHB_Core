//! Machine Interrupt Enable Register (mie)
//! Stores the three implemented interrupt-enable bits for machine mode:
//!   MEIE (bit 11) — machine external interrupt enable
//!   MTIE (bit  7) — machine timer interrupt enable
//!   MSIE (bit  3) — machine software interrupt enable
//! All other bits of mie are hardwired to zero.
//! The individual enable bits are exposed as scalar outputs so
//! Machine_Control can use them directly without bit-slicing.
module MIE_Reg (
  input         Clk_In,          //! Clock input
  input         Rst_In,          //! Synchronous reset — clears all enable bits
  input         WrEn_In,         //! CSR file write enable (gated by flush upstream)
  input         Data_Wr_11_In,   //! Write data bit 11 — new MEIE value
  input         Data_Wr_7_In,    //! Write data bit  7 — new MTIE value
  input         Data_Wr_3_In,    //! Write data bit  3 — new MSIE value
  input  [11:0] CSR_Addr_In,     //! CSR address — must equal MIE to write
  output        MEIE_Out,         //! Machine external interrupt enable (routed to Machine_Control)
  output        MTIE_Out,         //! Machine timer interrupt enable    (routed to Machine_Control)
  output        MSIE_Out,         //! Machine software interrupt enable (routed to Machine_Control)
  output [31:0] MIE_Reg_Out       //! Full 32-bit mie read value
);

  // ============================================================
  //! CSR Address
  // ============================================================
  localparam MIE_ADDR = 12'h304;

  // ============================================================
  //! Internal State
  // ============================================================
  reg MEIE;  //! Machine external interrupt enable
  reg MTIE;  //! Machine timer interrupt enable
  reg MSIE;  //! Machine software interrupt enable

  // ============================================================
  //! mie Read Value
  //! [31:12] = 0, [11] = MEIE, [10:8] = 0,
  //! [7] = MTIE, [6:4] = 0, [3] = MSIE, [2:0] = 0
  // ============================================================
  assign MIE_Reg_Out = {20'b0, MEIE, 3'b0, MTIE, 3'b0, MSIE, 3'b0};
  assign MEIE_Out    = MEIE;
  assign MTIE_Out    = MTIE;
  assign MSIE_Out    = MSIE;

  // ============================================================
  //! Register Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      MEIE <= 1'b0;
      MTIE <= 1'b0;
      MSIE <= 1'b0;
    end
    else if (CSR_Addr_In == MIE_ADDR && WrEn_In) begin
      MEIE <= Data_Wr_11_In;
      MTIE <= Data_Wr_7_In;
      MSIE <= Data_Wr_3_In;
    end
  end

endmodule
