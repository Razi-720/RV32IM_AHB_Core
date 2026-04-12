//! MISA Register and CSR Pre-Data Source
//! Two responsibilities in one small module:
//!
//! 1. MISA — generates the read-only machine ISA register value.
//!    Hardwired for RV32IM: MXL=01 (32-bit),
//!    extensions = bit 8 (I base ISA) + bit 12 (M multiply/divide).
//!
//! 2. Pre_Data — selects the write-data source for all CSR operations.
//!    When CSR_Op[2]=1 (immediate form: CSRRWI/CSRRSI/CSRRCI), the
//!    source is the zero-extended 5-bit unsigned immediate from the
//!    instruction rs1 field. Otherwise the source is rs1 register data.
module MISA_PreData_Unit (
  input         CSR_Op_2_In,    //! CSR operation bit [2]: selects immediate vs register source
  input  [4:0]  CSR_UImm_In,    //! 5-bit unsigned immediate from instruction [19:15]
  input  [31:0] CSR_Data_In,    //! RS1 register data (used when CSR_Op[2]=0)
  output [31:0] MISA_Out,       //! Machine ISA register value (read-only, hardwired)
  output [31:0] Pre_Data_Out    //! Selected write-data source for CSR_Data_Wr_Mux
);

  // ============================================================
  //! MISA Field Encodings
  // ============================================================
  localparam MXL = 2'b01;  //! XLEN = 32

  //! Extensions bitfield [25:0] — one bit per letter (bit 0 = A, bit 8 = I, bit 12 = M ...)
  //! Bit  8 = I : RV32I base integer ISA
  //! Bit 12 = M : Integer multiply/divide extension (RV32M)
  localparam EXTENSIONS = 26'b00000000000100001000000000;
  //                          ^bit25                   ^bit0
  //                           bit12=M ──┘    └── bit8=I

  // ============================================================
  //! Pre-Data Source Mux
  // ============================================================
  assign Pre_Data_Out = CSR_Op_2_In ? {27'b0, CSR_UImm_In} : CSR_Data_In;

  // ============================================================
  //! MISA — hardwired read-only value
  //! [31:30] = MXL      (01 = RV32)
  //! [29:26] = 0000     (reserved)
  //! [25:0]  = EXTENSIONS (I + M)
  // ============================================================
  assign MISA_Out = {MXL, 4'b0, EXTENSIONS};

endmodule
