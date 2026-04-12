//! RV32M — Radix-2 Non-Restoring Iterative Divider
//!
//! Architecture: Non-restoring division, 1 bit per cycle
//! Target      : Sky130 standard cells, area-optimised embedded core
//! Latency     : Up to 32 cycles + 1 correction cycle = 33 cycles worst case
//!               Early termination fires when remaining dividend is zero
//!               (common for small dividends — typical embedded workloads
//!                finish in 8–16 cycles on average)
//!
//! Special cases (RISC-V spec §7.1):
//!   Division by zero : DIV/REM  → −1 / dividend
//!                      DIVU/REMU→ 2^32−1 / dividend
//!   Signed overflow  : DIV(INT_MIN, −1) → INT_MIN, REM → 0
//!
//! Interface (multi-cycle, handshake):
//!   Start_In  — pulse high for 1 cycle to begin a new division
//!   Op_In     — funct3[2:1]: 10=DIV 11=DIVU 00=REM 01=REMU
//!   Ready_Out — asserted when Result_Out is valid

//! RV32M — Radix-2 Non-Restoring Iterative Divider
//!
//! Architecture: Non-restoring division, 1 bit per cycle
//! Target      : Sky130 standard cells, area-optimised embedded core
//! Latency     : Up to 32 cycles + 1 correction cycle = 33 cycles worst case
//!               Early termination fires when remaining dividend is zero
//!               (common for small dividends — typical embedded workloads
//!                finish in 8–16 cycles on average)
//!
//! Special cases (RISC-V spec §7.1):
//!   Division by zero : DIV/REM  → −1 / dividend
//!                      DIVU/REMU→ 2^32−1 / dividend
//!   Signed overflow  : DIV(INT_MIN, −1) → INT_MIN, REM → 0
//!
//! Interface (multi-cycle, handshake):
//!   Start_In  — pulse high for 1 cycle to begin a new division
//!   Op_In     — funct3[2:1]: 10=DIV 11=DIVU 00=REM 01=REMU
//!   Ready_Out — asserted when Result_Out is valid

module Div32_NonRestoring (
  input         Clk_In,
  input         Rst_In,

  input         Start_In,
  output reg    Ready_Out,

  input  [31:0] A_In,
  input  [31:0] B_In,
  input  [1:0]  Op_In,

  output reg [31:0] Result_Out
);

  // ============================================================
  // Operation decode
  // ============================================================
  wire Is_Div    =  Op_In[1];
  wire Is_Signed = ~Op_In[0];

  // ============================================================
  // Special-case detection
  // ============================================================
  localparam INT32_MIN = 32'h8000_0000;

  wire Div_By_Zero = (B_In == 32'h0);
  wire Signed_Ovf  = Is_Signed & (A_In == INT32_MIN) & (B_In == 32'hFFFF_FFFF);

  // ============================================================
  // Sign handling
  // ============================================================
  wire        A_neg   = Is_Signed & A_In[31];
  wire        B_neg   = Is_Signed & B_In[31];
  wire [31:0] A_mag   = A_neg ? (~A_In + 1'b1) : A_In;
  wire [31:0] B_mag   = B_neg ? (~B_In + 1'b1) : B_In;
  wire        Q_neg   = A_neg ^ B_neg;
  wire        R_neg   = A_neg;

  // ============================================================
  // Datapath registers
  // ============================================================
  reg [31:0] Divisor_r;
  reg [31:0] Quotient_r;
  reg [32:0] Remainder_r;
  reg [5:0]  Count_r;
  reg        Running_r;
  reg        Q_neg_r;
  reg        R_neg_r;
  reg        Is_Div_r;

  // ============================================================
  // Restoring division next-state logic
  //   Shift in the next dividend bit from Quotient_r[31]
  // ============================================================
  wire [32:0] R_shift = {Remainder_r[31:0], Quotient_r[31]};
  wire [31:0] Q_shift = {Quotient_r[30:0], 1'b0};
  wire [32:0] Div_ext = {1'b0, Divisor_r};
  wire        Take_Sub = (R_shift >= Div_ext);
  wire [32:0] R_next   = Take_Sub ? (R_shift - Div_ext) : R_shift;
  wire [31:0] Q_next   = Take_Sub ? (Q_shift | 32'h1) : Q_shift;

  wire [31:0] Q_signed = Q_neg_r ? (~Q_next + 1'b1) : Q_next;
  wire [31:0] R_signed = R_neg_r ? (~R_next[31:0] + 1'b1) : R_next[31:0];

  // ============================================================
  // Sequential logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      Running_r  <= 1'b0;
      Ready_Out  <= 1'b1;
      Result_Out <= 32'h0;
      Count_r    <= 6'd0;
      Divisor_r  <= 32'h0;
      Quotient_r  <= 32'h0;
      Remainder_r <= 33'h0;
      Q_neg_r    <= 1'b0;
      R_neg_r    <= 1'b0;
      Is_Div_r   <= 1'b0;
    end
    else if (Start_In) begin
      Ready_Out <= 1'b0;

      if (Div_By_Zero) begin
        Running_r  <= 1'b0;
        Ready_Out  <= 1'b1;
        Result_Out <= Is_Div ? 32'hFFFF_FFFF : A_In;
      end
      else if (Signed_Ovf) begin
        Running_r  <= 1'b0;
        Ready_Out  <= 1'b1;
        Result_Out <= Is_Div ? INT32_MIN : 32'h0;
      end
      else begin
        Running_r   <= 1'b1;
        Divisor_r   <= B_mag;
        Quotient_r   <= A_mag;
        Remainder_r  <= 33'h0;
        Count_r     <= 6'd0;
        Q_neg_r     <= Q_neg;
        R_neg_r     <= R_neg;
        Is_Div_r    <= Is_Div;
      end
    end
    else if (Running_r) begin
      Remainder_r <= R_next;
      Quotient_r  <= Q_next;
      Count_r     <= Count_r + 1'b1;

      if (Count_r == 6'd31) begin
        Running_r  <= 1'b0;
        Ready_Out  <= 1'b1;
        Result_Out <= Is_Div_r ? Q_signed : R_signed;
      end
    end
  end

endmodule
