//! Fetch → Decode Pipeline Register
//! Captures the fetched instruction, PC, and PC+4 on the rising
//! clock edge. Supports stall (hold) and flush (NOP injection).
//!
//! Flush priority: Flush_In overrides Stall_In — a flush always
//! inserts a NOP regardless of whether a stall was also requested.
module Reg_F_D (
  input         Clk_In,         //! Clock input
  input         Rst_In,         //! Synchronous reset — inserts NOP
  input         Stall_In,       //! Hold current values (load-use stall)
  input         Flush_In,       //! Insert NOP (branch misprediction or trap)
  input  [31:0] Instr_In,       //! Fetched instruction from instruction memory
  input  [31:0] PC_In,          //! Program counter of fetched instruction
  input  [31:0] PC_Plus4_In,    //! PC + 4

  output reg [31:0] Instr_Out,      //! Registered instruction → Decode stage
  output reg [31:0] PC_Out,         //! Registered PC → Decode stage
  output reg [31:0] PC_Plus4_Out    //! Registered PC+4 → Decode stage
);

  always @(posedge Clk_In) begin
    if (Rst_In || Flush_In) begin
      Instr_Out    <= 32'h0000_0013;  //! NOP = ADDI x0,x0,0 (opcode=0010011, safe flush value)
      PC_Out       <= 32'h0000_0000;
      PC_Plus4_Out <= 32'h0000_0000;
    end
    else if (Stall_In) begin
      //! Hold all outputs — values unchanged on stall
      Instr_Out    <= Instr_Out;
      PC_Out       <= PC_Out;
      PC_Plus4_Out <= PC_Plus4_Out;
    end
    else begin
      Instr_Out    <= Instr_In;
      PC_Out       <= PC_In;
      PC_Plus4_Out <= PC_Plus4_In;
    end
  end

endmodule
