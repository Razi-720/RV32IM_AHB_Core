//! - Determines if a branch should be taken based on the instruction type and operand values.
//! - Supports both signed and unsigned comparisons.
//! - Used for conditional and unconditional branch decisions in CPU pipelines.
//! - Operates combinationally based on decoded branch type signal.
//! - Evaluates branch types: JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU.

module Branch_Predictor(
    input [31:0] Src_Data1_In,   //! First 32-bit source operand for comparison
    input [31:0] Src_Data2_In,   //! Second 32-bit source operand for comparison
    input [7:0] bgeu_bltu_bge_blt_bne_beq_jalr_jal, //! One-hot encoded branch type control signal
    output reg Branch_Taken_Out  //! Output flag indicating if branch should be taken
);

    wire equal = (Src_Data1_In == Src_Data2_In);
    wire not_equal = ~equal;
    wire less_than = ($signed(Src_Data1_In) < $signed(Src_Data2_In));
    wire greater_equal = ~less_than;
    wire less_than_unsigned = (Src_Data1_In < Src_Data2_In);
    wire greater_equal_unsigned = ~less_than_unsigned;
    
    always @(*) begin
        casez (bgeu_bltu_bge_blt_bne_beq_jalr_jal)
            8'b0000_0001: Branch_Taken_Out = 1'b1;
            8'b0000_0010: Branch_Taken_Out = 1'b1;
            8'b0000_0100: Branch_Taken_Out = equal;
            8'b0000_1000: Branch_Taken_Out = not_equal;
            8'b0001_0000: Branch_Taken_Out = less_than;
            8'b0010_0000: Branch_Taken_Out = greater_equal;
            8'b0100_0000: Branch_Taken_Out = less_than_unsigned;
            8'b1000_0000: Branch_Taken_Out = greater_equal_unsigned;
            default: Branch_Taken_Out = 1'b0;
        endcase
    end
endmodule
