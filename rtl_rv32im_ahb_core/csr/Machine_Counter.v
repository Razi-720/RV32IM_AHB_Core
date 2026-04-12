//! Machine Performance Counters (mcycle, minstret, mtime)
//! Implements the three 64-bit machine-mode counters:
//!
//!   mcycle   — counts clock cycles since reset (or last software write).
//!              Inhibited (frozen) when MCountInhibit_CY_In = 1.
//!
//!   minstret — counts retired instructions. Incremented by Instret_Inc_In
//!              (asserted by Machine_Control for each committed instruction).
//!              Inhibited when MCountInhibit_IR_In = 1.
//!
//!   mtime    — real-time counter shadow. Not incremented internally;
//!              it is a registered copy of the external RTC_In bus,
//!              updated every cycle. Read-only from software.
//!
//! Software can write to MCYCLE/MCYCLEH and MINSTRET/MINSTRETH via CSR
//! instructions. The write takes effect on the same cycle as the counter
//! increment, so the net value is (written_value + increment).
module Machine_Counter (
  input         Clk_In,               //! Clock input
  input         Rst_In,               //! Synchronous reset — zeros all counters
  input         WrEn_In,              //! CSR file write enable (gated by flush upstream)
  input         MCountInhibit_CY_In,  //! 1 = freeze mcycle, 0 = increment each cycle
  input         MCountInhibit_IR_In,  //! 1 = freeze minstret, 0 = increment on retire
  input         Instret_Inc_In,        //! Pulse high for one cycle per retired instruction
  input  [11:0] CSR_Addr_In,          //! CSR address — selects which counter half to write
  input  [31:0] Data_Wr_In,           //! Write data (from CSR_Data_Wr_Mux)
  input  [63:0] RTC_In,               //! External real-time counter value
  output reg [63:0] MCycle_Out,        //! 64-bit machine cycle counter
  output reg [63:0] MInstret_Out,      //! 64-bit instructions-retired counter
  output reg [63:0] MTime_Out          //! 64-bit real-time counter shadow
);

  // ============================================================
  //! CSR Addresses
  // ============================================================
  localparam MCYCLE_ADDR    = 12'hB00;
  localparam MCYCLEH_ADDR   = 12'hB80;
  localparam MINSTRET_ADDR  = 12'hB02;
  localparam MINSTRETH_ADDR = 12'hB82;

  // ============================================================
  //! Reset Values
  // ============================================================
  localparam COUNTER_RESET = 64'h0000_0000_0000_0000;

  // ============================================================
  //! Counter Update Logic
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      MCycle_Out   <= COUNTER_RESET;
      MInstret_Out <= COUNTER_RESET;
      MTime_Out    <= COUNTER_RESET;
    end
    else begin

      // --------------------------------------------------------
      //! mtime — always shadow the external RTC regardless of inhibit
      // --------------------------------------------------------
      MTime_Out <= RTC_In;

      // --------------------------------------------------------
      //! mcycle — 64-bit cycle counter with optional SW write
      //! Writing to MCYCLEH or MCYCLE replaces that 32-bit half,
      //! then the counter still increments on that same cycle
      //! (unless inhibited). This matches the spec behaviour where
      //! the write is visible in the next read.
      // --------------------------------------------------------
      if (CSR_Addr_In == MCYCLE_ADDR && WrEn_In) begin
        if (!MCountInhibit_CY_In)
          MCycle_Out <= {MCycle_Out[63:32], Data_Wr_In} + 1;
        else
          MCycle_Out <= {MCycle_Out[63:32], Data_Wr_In};
      end
      else if (CSR_Addr_In == MCYCLEH_ADDR && WrEn_In) begin
        if (!MCountInhibit_CY_In)
          MCycle_Out <= {Data_Wr_In, MCycle_Out[31:0]} + 1;
        else
          MCycle_Out <= {Data_Wr_In, MCycle_Out[31:0]};
      end
      else begin
        if (!MCountInhibit_CY_In)
          MCycle_Out <= MCycle_Out + 1;
        //! else: counter frozen, no update
      end

      // --------------------------------------------------------
      //! minstret — 64-bit retired-instruction counter
      //! Incremented by Instret_Inc_In (not by 1 always, to allow
      //! future multi-issue extension without changing this module).
      // --------------------------------------------------------
      if (CSR_Addr_In == MINSTRET_ADDR && WrEn_In) begin
        if (!MCountInhibit_IR_In)
          MInstret_Out <= {MInstret_Out[63:32], Data_Wr_In} + Instret_Inc_In;
        else
          MInstret_Out <= {MInstret_Out[63:32], Data_Wr_In};
      end
      else if (CSR_Addr_In == MINSTRETH_ADDR && WrEn_In) begin
        if (!MCountInhibit_IR_In)
          MInstret_Out <= {Data_Wr_In, MInstret_Out[31:0]} + Instret_Inc_In;
        else
          MInstret_Out <= {Data_Wr_In, MInstret_Out[31:0]};
      end
      else begin
        if (!MCountInhibit_IR_In)
          MInstret_Out <= MInstret_Out + Instret_Inc_In;
        //! else: counter frozen, no update
      end

    end
  end

endmodule
