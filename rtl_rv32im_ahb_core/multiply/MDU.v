//! RV32M Multiply-Divide Unit — Top Level
//!
//! Wraps Mul32_Booth (single-cycle) and Div32_NonRestoring (32-cycle iterative)
//! into one module with a clean interface to the 5-stage pipeline.
//!
//! ── Latency summary ─────────────────────────────────────────────────────────
//!   MUL / MULH / MULHSU / MULHU : 1 cycle  (MDU_Ready_Out asserts next cycle)
//!   DIV / DIVU / REM / REMU     : 2–33 cycles (MDU_Ready_Out when done)
//!                                  early-termination fires when remainder = 0
//!
//! ── Pipeline integration ────────────────────────────────────────────────────
//!   Start_In     ← Is_Mext_E & valid instruction entering Execute stage
//!   MDU_Ready_Out→ Hazard_Unit: deasserted = stall Fetch+Decode, flush Execute
//!   Result_Out   → WB_Unit Result_Src mux (3'b111)
//!
//! ── Decoder signals consumed here ───────────────────────────────────────────
//!   Is_Mext_In   : set by Decoder when funct7==7'b0000001 & opcode==7'b0110011
//!   MDU_Op_In    : funct3 passed through (selects one of the 8 M-ext ops)
//! RV32M Multiply-Divide Unit — Top Level
module MDU (
  input         Clk_In,
  input         Rst_In,
  input         Start_In,
  output        MDU_Ready_Out,
  input  [31:0] A_In,
  input  [31:0] B_In,
  input  [2:0]  MDU_Op_In,
  output [31:0] Result_Out
);

  wire Is_Mul = ~MDU_Op_In[2];
  wire Is_Div =  MDU_Op_In[2];

  wire [31:0] Mul_Result;
  Mul32_Booth u_mul (
    .A_In      (A_In),
    .B_In      (B_In),
    .Op_In     (MDU_Op_In[1:0]),
    .Result_Out(Mul_Result)
  );

  wire [31:0] Div_Result;
  wire        Div_Ready;
  Div32_NonRestoring u_div (
    .Clk_In    (Clk_In),
    .Rst_In    (Rst_In),
    .Start_In  (Start_In & Is_Div),
    .Ready_Out (Div_Ready),
    .A_In      (A_In),
    .B_In      (B_In),
    .Op_In     ({~MDU_Op_In[1], MDU_Op_In[0]}),  //! encode: DIV→10 DIVU→11 REM→00 REMU→01
    .Result_Out(Div_Result)
  );

  // Delay divide-class ready by one cycle so pipeline capture occurs after
  // Div_Result register has been updated on the completion edge.
  reg Div_Ready_Delayed_r;
  always @(posedge Clk_In) begin
    if (Rst_In)
      Div_Ready_Delayed_r <= 1'b1;
    else if (Start_In & Is_Div)
      Div_Ready_Delayed_r <= 1'b0;
    else
      Div_Ready_Delayed_r <= Div_Ready;
  end

  assign MDU_Ready_Out = Is_Mul ? 1'b1 : (Div_Ready_Delayed_r & ~(Start_In & Is_Div));
  assign Result_Out    = Is_Mul ? Mul_Result : Div_Result;

endmodule
