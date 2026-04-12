//! @brief Immediate Adder Unit
//! @details
//! - Selects either PC or register data as base address based on control input.
//! - Adds base to the immediate value to produce an effective address or target.
//! - Commonly used for:
//!   - Branch/jump target calculation
//!   - Load/store address generation

module Imm_Adder (
    input Iadder_Src_In,             //! Select source: 0 = PC, 1 = Src_Data1
    input [31:0] PC_In,              //! Program Counter input
    input [31:0] Src_Data1_In,       //! Register data input (typically RS1)
    input [31:0] Imm_Data_In,        //! Immediate value input
    output [31:0] Added_Data_Out     //! Result of base + immediate addition
);
    wire [31:0] temp_adder_src;

    assign temp_adder_src = Iadder_Src_In ? Src_Data1_In : PC_In;
    assign Added_Data_Out = temp_adder_src + Imm_Data_In;

endmodule
