//! @brief Immediate Extend Unit
//! @details
//! - Generates 32-bit sign-extended immediates from instruction bits based on type.
//! - Supports the following RISC-V formats:
//!   - R-type: No immediate (output is zero)
//!   - I-type: 12-bit immediate, sign-extended
//!   - S-type: Combines fields for store immediate, sign-extended
//!   - B-type: Combines and aligns fields for conditional branches
//!   - U-type: Upper 20 bits immediate (LUI/AUIPC)
//!   - J-type: Jump immediate with sign-extension and alignment

module Extend_Unit(
    input [31:7] Instr_In,        //! Instruction bits [31:7] for immediate extraction
    input [2:0] Imm_Type_In,      //! Immediate type selector (R, I, S, B, U, J)
    output reg [31:0] Imm_Out     //! Sign-extended 32-bit immediate output
);
    always @(*) begin
        case (Imm_Type_In)
            3'b000: Imm_Out = 32'b0;  // R-type
            3'b001: Imm_Out = {{20{Instr_In[31]}}, Instr_In[31:20]};  // I-type
            3'b010: Imm_Out = {{20{Instr_In[31]}}, Instr_In[31:25], Instr_In[11:7]};  // S-type
            3'b011: Imm_Out = {{20{Instr_In[31]}}, Instr_In[7], Instr_In[30:25], Instr_In[11:8], 1'b0};  // B-type
            3'b100: Imm_Out = {Instr_In[31:12], 12'b0};  // U-type
            3'b101: Imm_Out = {{12{Instr_In[31]}}, Instr_In[19:12], Instr_In[20], Instr_In[30:21], 1'b0};  // J-type
            default: Imm_Out = 32'b0;
        endcase
    end
endmodule
