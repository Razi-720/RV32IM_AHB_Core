//! Load Unit
//! Extracts and sign/zero-extends a byte, halfword, or word from the
//! raw 32-bit data memory response, based on the access size and the
//! low-order address bits that select the sub-word position.
//!
//! Supports all five RISC-V load instructions:
//!   LB  (Load_Size=00, Load_Unsigned=0) — sign-extended byte
//!   LBU (Load_Size=00, Load_Unsigned=1) — zero-extended byte
//!   LH  (Load_Size=01, Load_Unsigned=0) — sign-extended halfword
//!   LHU (Load_Size=01, Load_Unsigned=1) — zero-extended halfword
//!   LW  (Load_Size=10)                  — full 32-bit word
//!
//! AHB error gating:
//!   When AHB_Resp_In=1 (HRESP=ERROR from the data memory bus), the
//!   load result is suppressed (output held at zero). Machine_Control
//!   is responsible for raising the bus-fault / load-access exception.
//!   The Load Unit does NOT generate the exception itself — it only
//!   gates the writeback data so a corrupted value is never committed
//!   to the register file.
//!
//! Relationship to reference design (msrv32_lu):
//!   The reference gates the entire case statement on !ahb_resp_in,
//!   leaving lu_output undefined (latch-inferred) when ahb_resp_in=1.
//!   This design explicitly drives Loaded_Data_Out=0 on error, which
//!   is synthesis-safe and matches the intent of the reference.

`timescale 1ns/1ps

module Load_Unit (
  input  [31:0] Read_Data_In,        //! Raw 32-bit data word from data memory
  input  [1:0]  Iadder_1to0_In,      //! Effective address [1:0] — selects byte/half lane
  input  [1:0]  Load_Size_In,        //! Access width: 00=byte 01=half 10=word
  input         Load_Unsigned_In,    //! 1=zero-extend, 0=sign-extend
  input         AHB_Resp_In,         //! AHB HRESP: 1=ERROR — forces output to zero
  output reg [31:0] Loaded_Data_Out  //! Sign/zero-extended load result
);

  // ============================================================
  //! Byte and Halfword Lane Selection (combinatorial)
  //! Pre-select the relevant sub-word before sign/zero extension
  //! so the extension logic is shared across all address offsets.
  // ============================================================
  reg  [7:0]  Data_Byte;  //! Selected byte lane
  reg  [15:0] Data_Half;  //! Selected halfword lane

  always @* begin
    case (Iadder_1to0_In)
      2'b00: Data_Byte = Read_Data_In[7:0];
      2'b01: Data_Byte = Read_Data_In[15:8];
      2'b10: Data_Byte = Read_Data_In[23:16];
      2'b11: Data_Byte = Read_Data_In[31:24];
    endcase
  end

  always @* begin
    case (Iadder_1to0_In[1])
      1'b0: Data_Half = Read_Data_In[15:0];
      1'b1: Data_Half = Read_Data_In[31:16];
    endcase
  end

  // ============================================================
  //! Sign/Zero Extension Wires
  // ============================================================
  wire [23:0] Byte_Ext;  //! Upper 24 bits for byte loads
  wire [15:0] Half_Ext;  //! Upper 16 bits for halfword loads

  assign Byte_Ext = Load_Unsigned_In ? 24'b0 : {24{Data_Byte[7]}};
  assign Half_Ext = Load_Unsigned_In ? 16'b0 : {16{Data_Half[15]}};

  // ============================================================
  //! Load Output Mux
  //!
  //! AHB_Resp_In=1 (bus error) forces the output to 32'b0.
  //! This prevents a corrupted or undefined value from being
  //! written back to the integer register file. Machine_Control
  //! will simultaneously raise the load-access-fault exception
  //! and flush the pipeline — so the zero written here is never
  //! architecturally visible.
  //!
  //! AHB_Resp_In=0 (normal): decode load size and extend.
  //!   Load_Size 2'b11 is not a legal RISC-V encoding but is
  //!   treated as a word load (same as reference msrv32_lu).
  // ============================================================
  always @* begin
    if (AHB_Resp_In) begin
      Loaded_Data_Out = 32'b0;          //! Bus error — suppress writeback
    end
    else begin
      case (Load_Size_In)
        2'b00:   Loaded_Data_Out = {Byte_Ext, Data_Byte};  //! LB / LBU
        2'b01:   Loaded_Data_Out = {Half_Ext, Data_Half};  //! LH / LHU
        2'b10:   Loaded_Data_Out = Read_Data_In;           //! LW
        default: Loaded_Data_Out = Read_Data_In;           //! treat 11 as word
      endcase
    end
  end

endmodule
