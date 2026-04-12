//! Machine Trap-Vector Base Register (mtvec) + Trap Address Generator
//! Stores the trap handler base address and mode, and computes the
//! concrete trap target address that the PC unit jumps to on a trap.
//!
//! mtvec layout: [31:2] = BASE, [1:0] = MODE
//!   MODE = 00 (Direct)   — all traps jump to BASE<<2
//!   MODE = 01 (Vectored) — interrupts jump to (BASE<<2) + (cause × 4)
//!                          exceptions always jump to BASE<<2
//!
//! Trap address selection:
//!   Int_Or_Exc_In = 0 (exception) → always BASE<<2
//!   Int_Or_Exc_In = 1 (interrupt) → BASE<<2 + (Cause_In << 2) if MODE=Vectored
//!                                    BASE<<2                    if MODE=Direct
module MTVec_Reg (
  input         Clk_In,          //! Clock input
  input         Rst_In,          //! Synchronous reset — clears BASE and MODE to 0
  input         WrEn_In,         //! CSR file write enable (gated by flush upstream)
  input         Int_Or_Exc_In,   //! 1=interrupt, 0=exception — selects vectored vs direct
  input  [31:0] Data_Wr_In,      //! Write data (from CSR_Data_Wr_Mux)
  input  [11:0] CSR_Addr_In,     //! CSR address — must equal MTVEC to write
  input  [3:0]  Cause_In,        //! Interrupt cause code (from mcause[3:0]) for vectored mode
  output [31:0] MTVec_Out,       //! Full 32-bit mtvec read value {BASE, MODE}
  output [31:0] Trap_Addr_Out    //! Computed jump target for the PC unit on trap entry
);

  // ============================================================
  //! CSR Address
  // ============================================================
  localparam MTVEC_ADDR = 12'h305;

  // ============================================================
  //! Reset Values
  // ============================================================
  localparam BASE_RESET = 30'b0;  //! Reset trap base to address 0
  localparam MODE_RESET =  2'b0;  //! Reset to Direct mode

  // ============================================================
  //! Internal State
  // ============================================================
  reg [29:0] BASE;  //! Trap handler base address [31:2]
  reg [1:0]  MODE;  //! Trap mode: 00=Direct, 01=Vectored

  // ============================================================
  //! mtvec Read Value
  // ============================================================
  assign MTVec_Out = {BASE, MODE};

  // ============================================================
  //! Trap Address Computation
  //! Base address (word-aligned) = {BASE, 2'b00}
  //! Vector offset for interrupts = Cause_In << 2 (4 bytes per entry)
  //! Vectored interrupt target    = base + offset (only when MODE[0]=1)
  //! All exceptions               = base (direct, regardless of MODE)
  // ============================================================
  wire [31:0] Base_Addr   = {BASE, 2'b00};
  wire [31:0] Base_Offset = {26'b0, Cause_In, 2'b00};  //! Cause_In << 2
  wire [31:0] Vec_Addr    = MODE[0] ? Base_Addr + Base_Offset : Base_Addr;
  assign Trap_Addr_Out    = Int_Or_Exc_In ? Vec_Addr : Base_Addr;

  // ============================================================
  //! Register Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      MODE <= MODE_RESET;
      BASE <= BASE_RESET;
    end
    else if (CSR_Addr_In == MTVEC_ADDR && WrEn_In) begin
      MODE <= Data_Wr_In[1:0];
      BASE <= Data_Wr_In[31:2];
    end
  end

endmodule
