//! CSR Write Data Mux
//! Computes the value to write into a CSR register based on the
//! CSR operation type. Implements CSRRW, CSRRS, CSRRC semantics
//! and their immediate variants (op[2] selects imm vs rs1, handled
//! upstream in MISA_PreData_Unit before reaching this mux).
//!
//! Truth table:
//!   CSR_Op[1:0] = 00 (NOP)  -> write current CSR value back (no change)
//!   CSR_Op[1:0] = 01 (RW)   -> write pre_data directly
//!   CSR_Op[1:0] = 10 (RS)   -> set bits:   CSR | pre_data
//!   CSR_Op[1:0] = 11 (RC)   -> clear bits: CSR & ~pre_data
module Data_Wr_Mux_Unit (
  input      [1:0]  CSR_Op_1_0_In,   //! CSR operation code [1:0] from instruction funct3
  input      [31:0] CSR_Data_Out_In,  //! Current CSR register read value (feedback)
  input      [31:0] Pre_Data_In,      //! Pre-computed write source (RS1 or zero-extended uimm)
  output reg [31:0] Data_Wr_Out       //! Computed value to write into the CSR
);

  // ============================================================
  //! CSR Operation Encodings (funct3[1:0])
  // ============================================================
  localparam CSR_NOP = 2'b00;  //! No operation — preserve current value
  localparam CSR_RW  = 2'b01;  //! Read-write  — replace with pre_data
  localparam CSR_RS  = 2'b10;  //! Read-set    — set bits in pre_data mask
  localparam CSR_RC  = 2'b11;  //! Read-clear  — clear bits in pre_data mask

  // ============================================================
  //! Write Data Computation
  // ============================================================
  always @* begin
    case (CSR_Op_1_0_In)
      CSR_RW:  Data_Wr_Out = Pre_Data_In;
      CSR_RS:  Data_Wr_Out = CSR_Data_Out_In |  Pre_Data_In;
      CSR_RC:  Data_Wr_Out = CSR_Data_Out_In & ~Pre_Data_In;
      CSR_NOP: Data_Wr_Out = CSR_Data_Out_In;
    endcase
  end

endmodule
