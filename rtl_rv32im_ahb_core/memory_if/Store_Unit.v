//! Store Unit
//! Generates the write data, byte-enable mask, and word-aligned address
//! for data memory write operations.
//!
//! Supports the three RISC-V store instructions:
//!   SB (Func3=00) — store byte:     places byte in the correct lane, masks one byte
//!   SH (Func3=01) — store halfword: places half in the correct lane, masks two bytes
//!   SW (Func3=10) — store word:     writes full 32-bit value, masks all four bytes
//!
//! Address alignment:
//!   DM_Addr_Out = Added_Data_In[31:2] concatenated with 2'b00 (word-aligned).
//!   The byte-enable mask selects the correct sub-word lane so the memory
//!   controller receives a naturally aligned address at all times.
//!
//! Write mask gating:
//!   All mask bits are AND'd with Store_WrEn (DM_WrEn_In & ~misaligned)
//!   so the mask is zero when no write is requested, preventing spurious
//!   writes on stall or idle cycles.
//!
//! Bus metadata note:
//!   HTRANS and HSIZE are generated in Pip_RV32I (top-level) so both
//!   loads and stores are encoded consistently. This unit only produces
//!   write data/mask/address plus the aligned store write request.

`timescale 1ns/1ps

module Store_Unit (
  input         DM_WrEn_In,           //! Write enable from Decoder (0 on misalign or trap)
  input  [1:0]  Func3_In,             //! Store width: 00=byte 01=half 10=word
  input  [31:0] Added_Data_In,        //! Effective address from Imm_Adder
  input  [31:0] Src_Data2_In,         //! RS2 write data

  output [31:0] DM_Addr_Out,          //! Word-aligned address to data memory
  output reg [31:0] DM_WrData_Out,    //! Lane-positioned write data
  output reg [3:0]  DM_WrMask_Out,    //! Byte-enable mask (gated by Store_WrEn)
  output        DM_WrEn_Out           //! Write request to data memory
);

  // ============================================================
  //! Word-Aligned Address
  //! Bits [1:0] forced to zero — sub-word selection via mask.
  // ============================================================
  assign DM_Addr_Out = {Added_Data_In[31:2], 2'b00};

  // ============================================================
  //! Misalignment Detection and Write Enable
  //!   SW needs 4-byte alignment: addr[1:0] must be 2'b00
  //!   SH needs 2-byte alignment: addr[0]   must be 0
  //!   SB has no alignment requirement
  //! Store_WrEn suppresses the write (and mask) on misaligned access.
  //! Machine_Control independently raises the store-misaligned exception.
  // ============================================================
  wire Store_Misaligned;
  wire Store_WrEn;

  assign Store_Misaligned = (Func3_In == 2'b10) ? (Added_Data_In[1] | Added_Data_In[0]) :
                            (Func3_In == 2'b01) ?  Added_Data_In[0] :
                                                    1'b0;
  assign Store_WrEn  = DM_WrEn_In & ~Store_Misaligned;
  assign DM_WrEn_Out = Store_WrEn;

  // ============================================================
  //! Byte Lane Positioning (combinatorial)
  //! Data is placed into the exact target lane with zeros in
  //! unused lanes. Byte-enable mask then selects which lanes
  //! the memory controller commits.
  // ============================================================
  reg [31:0] Byte_Data;   //! Byte placed in the correct 8-bit lane
  reg [31:0] Half_Data;   //! Halfword placed in the correct 16-bit lane

  always @* begin
    case (Added_Data_In[1:0])
      2'b00: Byte_Data = {24'b0,              Src_Data2_In[7:0]};
      2'b01: Byte_Data = {16'b0, Src_Data2_In[7:0],  8'b0};
      2'b10: Byte_Data = { 8'b0, Src_Data2_In[7:0], 16'b0};
      2'b11: Byte_Data = {       Src_Data2_In[7:0], 24'b0};
    endcase
  end

  always @* begin
    case (Added_Data_In[1])
      1'b0: Half_Data = {16'b0,              Src_Data2_In[15:0]};
      1'b1: Half_Data = {      Src_Data2_In[15:0], 16'b0};
    endcase
  end

  // ============================================================
  //! Byte-Enable Mask Generation (combinatorial)
  // ============================================================
  reg [3:0] Byte_Mask;  //! One-hot byte lane mask for SB
  reg [3:0] Half_Mask;  //! Two-bit halfword lane mask for SH

  always @* begin
    case (Added_Data_In[1:0])
      2'b00: Byte_Mask = {3'b0,       Store_WrEn};
      2'b01: Byte_Mask = {2'b0, Store_WrEn, 1'b0};
      2'b10: Byte_Mask = {1'b0, Store_WrEn, 2'b0};
      2'b11: Byte_Mask = {      Store_WrEn, 3'b0};
    endcase
  end

  always @* begin
    case (Added_Data_In[1])
      1'b0: Half_Mask = {2'b0, {2{Store_WrEn}}};
      1'b1: Half_Mask = {      {2{Store_WrEn}}, 2'b0};
    endcase
  end

  // ============================================================
  //! Output Mux — Data and Mask
  //!
  //! HTRANS/HSIZE are generated in top-level from pipeline control.
  // ============================================================
  always @* begin
    case (Func3_In)
      2'b00:   DM_WrData_Out = Byte_Data;      //! SB
      2'b01:   DM_WrData_Out = Half_Data;      //! SH
      default: DM_WrData_Out = Src_Data2_In;   //! SW
    endcase
  end

  always @* begin
    case (Func3_In)
      2'b00:   DM_WrMask_Out = Byte_Mask;        //! SB — one byte enabled
      2'b01:   DM_WrMask_Out = Half_Mask;        //! SH — two bytes enabled
      default: DM_WrMask_Out = {4{Store_WrEn}};  //! SW — all four bytes
    endcase
  end

endmodule
