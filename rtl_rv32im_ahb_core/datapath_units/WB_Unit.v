//! Write-Back Unit
//! Selects the value to be written back to the integer register file
//! from among all possible result sources in the pipeline.
//!
//! Result_Src encoding — must match Decoder.v and Reg_M_W output:
//!   3'b000 — no writeback     (default / NOP)
//!   3'b001 — ALU result       (R-type, I-type ALU)
//!   3'b010 — Immediate value  (LUI)
//!   3'b011 — PC + Immediate   (AUIPC)
//!   3'b100 — PC + 4           (JAL, JALR)
//!   3'b101 — Load data        (LB, LH, LW, LBU, LHU)
//!   3'b110 — CSR read data    (CSRRW, CSRRS, CSRRC and immediate variants)
//!   3'b111 — MDU result       (RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU)
//!
//! RV32M writeback:
//!   MDU_Result_In is driven directly by MDU.Result_Out.
//!   For MUL* (single-cycle) the result is combinatorial and stable.
//!   For DIV*/REM* the Hazard_Unit has held the pipeline until
//!   MDU.Ready_Out fired, so MDU_Result_In is guaranteed valid here.
module WB_Unit (
  input  [2:0]  Result_Src_In,   //! Write-back source selector from Reg_M_W
  input  [31:0] ALU_Result_In,   //! ALU computation result
  input  [31:0] Loaded_Data_In,  //! Processed load data from Load_Unit
  input  [31:0] Imm_Data_In,     //! Sign-extended immediate (LUI)
  input  [31:0] Imm_Added_In,    //! Immediate adder output — PC+Imm (AUIPC)
  input  [31:0] CSR_Data_In,     //! CSR read data from CSR_File
  input  [31:0] PC_Plus4_In,     //! PC + 4 link address (JAL/JALR)
  input  [31:0] MDU_Result_In,   //! RV32M multiply/divide result from MDU
  output reg [31:0] Result_Out   //! Selected write-back value → Register_File
);

  // ============================================================
  //! Result Source Encodings
  // ============================================================
  localparam WB_ALU      = 3'b001;
  localparam WB_LOAD     = 3'b101;
  localparam WB_IMM      = 3'b010;
  localparam WB_PC_IMM   = 3'b011;
  localparam WB_PC_PLUS4 = 3'b100;
  localparam WB_CSR      = 3'b110;
  localparam WB_MDU      = 3'b111;  //! RV32M result

  // ============================================================
  //! Write-Back Mux
  // ============================================================
  always @* begin
    case (Result_Src_In)
      WB_ALU:      Result_Out = ALU_Result_In;
      WB_LOAD:     Result_Out = Loaded_Data_In;
      WB_IMM:      Result_Out = Imm_Data_In;
      WB_PC_IMM:   Result_Out = Imm_Added_In;
      WB_PC_PLUS4: Result_Out = PC_Plus4_In;
      WB_CSR:      Result_Out = CSR_Data_In;
      WB_MDU:      Result_Out = MDU_Result_In;   //! RV32M writeback
      default:     Result_Out = ALU_Result_In;
    endcase
  end

endmodule
