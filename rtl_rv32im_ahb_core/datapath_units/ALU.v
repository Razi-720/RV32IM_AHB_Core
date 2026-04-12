//! @brief Arithmetic Logic Unit (ALU)
//! - Performs arithmetic and logic operations based on ALU_Control_In signal.
//! - Supports the following operations:
//! 1. ADD - Addition
//! 2. SUB - Subtraction
//! 3. SLL - Logical left shift
//! 4. SLT - Set less than (signed)
//! 5. SLTU - Set less than (unsigned)
//! 6. XOR - Bitwise exclusive OR
//! 7. SRL - Logical right shift
//! 8. SRA - Arithmetic right shift
//! 9. OR - Bitwise OR
//! 10. AND - Bitwise AND

module ALU(
    input [31:0] Src1_In,      //! First 32-bit source operand
    input [31:0] Src2_In,      //! Second 32-bit source operand
    input [3:0] ALU_Control_In,//! 4-bit control signal determining the ALU operation
    output reg [31:0] ALU_Result_Out //! 32-bit result of the ALU operation
);

    wire signed [31:0] signed_src1 = Src1_In;
    wire signed [31:0] signed_src2 = Src2_In;
    
    always @(*) begin
        case (ALU_Control_In)
            4'b0000: ALU_Result_Out = Src1_In + Src2_In;
            4'b1000: ALU_Result_Out = Src1_In - Src2_In;
            4'b0001: ALU_Result_Out = Src1_In << Src2_In[4:0];
            4'b0010: ALU_Result_Out = (signed_src1 < signed_src2) ? 1 : 0;
            4'b0011: ALU_Result_Out = (Src1_In < Src2_In) ? 1 : 0;
            4'b0100: ALU_Result_Out = Src1_In ^ Src2_In;
            4'b0101: ALU_Result_Out = Src1_In >> Src2_In[4:0];
            4'b1101: ALU_Result_Out = signed_src1 >>> Src2_In[4:0];
            4'b0110: ALU_Result_Out = Src1_In | Src2_In;
            4'b0111: ALU_Result_Out = Src1_In & Src2_In;
            default: ALU_Result_Out = 32'b0;
        endcase
    end
endmodule
