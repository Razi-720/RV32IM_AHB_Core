//! Machine Control Unit
//! Implements the machine-mode trap controller as a 4-state Moore FSM.
//! Responsible for:
//!   - Detecting all trap conditions (interrupts, exceptions, ECALL, EBREAK)
//!   - Sequencing trap entry and trap return (MRET)
//!   - Driving PC source selection, pipeline flush, and CSR update strobes
//!   - Registering the trap cause and interrupt/exception flag for MCause_Reg
//!
//! State encoding (one-hot):
//!   RESET       (0001) — held for one cycle after reset, boots the PC
//!   OPERATING   (0010) — normal execution
//!   TRAP_TAKEN  (0100) — one-cycle trap entry: flush, save EPC/cause, jump to handler
//!   TRAP_RETURN (1000) — one-cycle MRET: flush, restore MIE, jump to EPC
//!
//! Trap priority (highest to lowest, evaluated combinatorially):
//!   1. External interrupt  (EIP) — requires MIE=1
//!   2. Software interrupt  (SIP) — requires MIE=1
//!   3. Timer interrupt     (TIP) — requires MIE=1
//!   4. Illegal instruction
//!   5. Instruction address misaligned
//!   6. ECALL
//!   7. EBREAK
//!   8. Load access fault (AHB HRESP=ERROR on load)
//!   9. Store address misaligned
//!  10. Load address misaligned

module Machine_Control (
  input         Clk_In,              //! Clock input
  input         Rst_In,              //! Synchronous reset

  //! ── Exception flags from Decoder / pipeline ─────────────────
  input         Illegal_Instr_In,    //! Unrecognised opcode from Decoder
  input         Misaligned_Instr_In, //! PC not 4-byte aligned (from PC_Unit)
  input         Load_Access_Fault_In,//! Data bus error on load transaction
  input         Misaligned_Load_In,  //! Load effective address misaligned
  input         Misaligned_Store_In, //! Store effective address misaligned

  //! ── Instruction fields (for ECALL/EBREAK/MRET decode) ───────
  input  [4:0]  Opcode_6to2_In,      //! Instruction opcode [6:2]
  input  [2:0]  Func3_In,            //! funct3 field
  input  [6:0]  Func7_In,            //! funct7 field
  input  [4:0]  Src_Addr1_In,        //! RS1 address
  input  [4:0]  Src_Addr2_In,        //! RS2 address
  input  [4:0]  Des_Addr_In,         //! RD address

  //! ── Interrupt request lines ──────────────────────────────────
  input         EIrq_In,             //! External interrupt request
  input         TIrq_In,             //! Timer interrupt request
  input         SIrq_In,             //! Software interrupt request

  //! ── CSR status bits (from CSR_File) ──────────────────────────
  input         MIE_In,              //! Global machine interrupt enable (mstatus.MIE)
  input         MEIE_In,             //! Machine external interrupt enable (mie.MEIE)
  input         MTIE_In,             //! Machine timer interrupt enable    (mie.MTIE)
  input         MSIE_In,             //! Machine software interrupt enable (mie.MSIE)
  input         MEIP_In,             //! Machine external interrupt pending (mip.MEIP)
  input         MTIP_In,             //! Machine timer interrupt pending    (mip.MTIP)
  input         MSIP_In,             //! Machine software interrupt pending (mip.MSIP)

  //! ── Outputs to CSR_File ──────────────────────────────────────
  output reg        I_Or_E_Out,           //! 1=interrupt, 0=exception — written to mcause[31]
  output reg        Set_EPC_Out,          //! Strobe: latch PC into mepc
  output reg        Set_Cause_Out,        //! Strobe: latch cause into mcause
  output reg [3:0]  Cause_Out,            //! Trap cause code — written to mcause[3:0]
  output reg        Instret_Inc_Out,      //! Pulse per retired instruction — increments minstret
  output reg        MIE_Clear_Out,        //! Trap entry:  save MIE→MPIE, clear MIE
  output reg        MIE_Set_Out,          //! Trap return: restore MIE←MPIE
  output reg        Misaligned_Exc_Out,   //! Registered misaligned flag → MTVal_Reg

  //! ── Outputs to PC_Unit ───────────────────────────────────────
  output reg [1:0]  PC_Src_Out,           //! Next-PC selector (see PC_SRC_* encoding)

  //! ── Outputs to pipeline registers ────────────────────────────
  output reg        Flush_Out,            //! Flush F/D and D/E pipeline registers

  //! ── Output to Decoder ────────────────────────────────────────
  output            Trap_Taken_Out        //! Combinational: trap in progress — Decoder outputs NOP
);

  // ============================================================
  //! FSM State Encoding (one-hot 4-bit)
  // ============================================================
  localparam STATE_RESET       = 4'b0001;
  localparam STATE_OPERATING   = 4'b0010;
  localparam STATE_TRAP_TAKEN  = 4'b0100;
  localparam STATE_TRAP_RETURN = 4'b1000;

  // ============================================================
  //! PC Source Selector Encoding
  // ============================================================
  localparam PC_SRC_BOOT = 2'b00;  //! Reset: jump to boot address
  localparam PC_SRC_EPC  = 2'b01;  //! MRET:  return to mepc
  localparam PC_SRC_TRAP = 2'b10;  //! Trap:  jump to mtvec handler
  localparam PC_SRC_NEXT = 2'b11;  //! Normal: PC+4 or branch target

  // ============================================================
  //! FSM State Registers
  // ============================================================
  reg [3:0] Curr_State;  //! Current FSM state (registered)
  reg [3:0] Next_State;  //! Next FSM state (combinatorial)

  // ============================================================
  //! SYSTEM Instruction Decode
  //! MRET / ECALL / EBREAK share opcode[6:2] = 11100
  //! Distinguished by funct7, funct3, rs1, rs2, rd fields
  // ============================================================
  wire Is_System;    //! Opcode[6:2] = 11100 (SYSTEM)
  wire Func3_Zero;   //! funct3 = 000
  wire Func7_Zero;   //! funct7 = 0000000
  wire Func7_MRET;   //! funct7 = 0011000
  wire RS1_Zero;     //! rs1 = x0
  wire RS2_Zero;     //! rs2 = x0
  wire RS2_MRET;     //! rs2 = 00010
  wire RS2_EBREAK;   //! rs2 = 00001
  wire RD_Zero;      //! rd  = x0

  assign Is_System  =  Opcode_6to2_In[4] &  Opcode_6to2_In[3] &  Opcode_6to2_In[2]
                    & ~Opcode_6to2_In[1] & ~Opcode_6to2_In[0];

  assign Func3_Zero = ~(Func3_In[2] | Func3_In[1] | Func3_In[0]);

  assign Func7_Zero = ~(Func7_In[6] | Func7_In[5] | Func7_In[4] | Func7_In[3]
                      | Func7_In[2] | Func7_In[1] | Func7_In[0]);

  assign Func7_MRET = ~Func7_In[6] & ~Func7_In[5] &  Func7_In[4]
                    &  Func7_In[3] & ~Func7_In[2] & ~Func7_In[1] & ~Func7_In[0];

  assign RS1_Zero   = ~(Src_Addr1_In[4] | Src_Addr1_In[3] | Src_Addr1_In[2]
                      | Src_Addr1_In[1] | Src_Addr1_In[0]);

  assign RS2_Zero   = ~(Src_Addr2_In[4] | Src_Addr2_In[3] | Src_Addr2_In[2]
                      | Src_Addr2_In[1] | Src_Addr2_In[0]);

  assign RD_Zero    = ~(Des_Addr_In[4]  | Des_Addr_In[3]  | Des_Addr_In[2]
                      | Des_Addr_In[1]  | Des_Addr_In[0]);

  assign RS2_MRET   = ~Src_Addr2_In[4] & ~Src_Addr2_In[3] & ~Src_Addr2_In[2]
                    &  Src_Addr2_In[1] & ~Src_Addr2_In[0];  //! rs2 = 00010

  assign RS2_EBREAK = ~Src_Addr2_In[4] & ~Src_Addr2_In[3] & ~Src_Addr2_In[2]
                    & ~Src_Addr2_In[1] &  Src_Addr2_In[0]; //! rs2 = 00001

  wire MRET;    //! Decoded MRET  instruction
  wire ECALL;   //! Decoded ECALL instruction
  wire EBREAK;  //! Decoded EBREAK instruction

  assign MRET   = Is_System & Func7_MRET & RS2_MRET   & RS1_Zero & Func3_Zero & RD_Zero;
  assign ECALL  = Is_System & Func7_Zero & RS2_Zero    & RS1_Zero & Func3_Zero & RD_Zero;
  assign EBREAK = Is_System & Func7_Zero & RS2_EBREAK  & RS1_Zero & Func3_Zero & RD_Zero;

  // ============================================================
  //! Interrupt Pending — qualified by individual enable bits
  //! Global MIE gate is applied in Trap_Taken_Out and FSM separately
  // ============================================================
  wire EIP;  //! External interrupt: enabled and pending
  wire TIP;  //! Timer interrupt:    enabled and pending
  wire SIP;  //! Software interrupt: enabled and pending
  wire IP;   //! Any interrupt enabled and pending

  assign EIP = MEIE_In & (EIrq_In | MEIP_In);
  assign TIP = MTIE_In & (TIrq_In | MTIP_In);
  assign SIP = MSIE_In & (SIrq_In | MSIP_In);
  assign IP  = EIP | TIP | SIP;

  // ============================================================
  //! Exception Detection — synchronous, unconditional
  // ============================================================
  wire Exception;
  assign Exception = Illegal_Instr_In | Misaligned_Instr_In
                   | Load_Access_Fault_In
                   | Misaligned_Load_In | Misaligned_Store_In;

  // ============================================================
  //! Trap Taken — combinatorial output
  //! Asserted whenever the pipeline must be redirected to a handler.
  //! Fed back to Decoder so the current instruction is nullified.
  // ============================================================
  assign Trap_Taken_Out = (MIE_In & IP) | Exception | ECALL | EBREAK;

  // ============================================================
  //! FSM — Next State Logic (combinatorial)
  // ============================================================
  always @* begin
    case (Curr_State)
      STATE_RESET:
        Next_State = STATE_OPERATING;

      STATE_OPERATING:
        if      (Trap_Taken_Out) Next_State = STATE_TRAP_TAKEN;
        else if (MRET)           Next_State = STATE_TRAP_RETURN;
        else                     Next_State = STATE_OPERATING;

      STATE_TRAP_TAKEN:
        Next_State = STATE_OPERATING;

      STATE_TRAP_RETURN:
        Next_State = STATE_OPERATING;

      default:
        Next_State = STATE_OPERATING;
    endcase
  end

  // ============================================================
  //! FSM — Combinatorial Output Logic (Moore outputs)
  // ============================================================
  always @* begin
    case (Curr_State)

      STATE_RESET: begin
        PC_Src_Out      = PC_SRC_BOOT;
        Flush_Out       = 1'b1;
        Instret_Inc_Out = 1'b0;
        Set_EPC_Out     = 1'b0;
        Set_Cause_Out   = 1'b0;
        MIE_Clear_Out   = 1'b0;
        MIE_Set_Out     = 1'b0;
      end

      STATE_OPERATING: begin
        PC_Src_Out      = PC_SRC_NEXT;
        Flush_Out       = 1'b0;
        Instret_Inc_Out = 1'b1;
        Set_EPC_Out     = 1'b0;
        Set_Cause_Out   = 1'b0;
        MIE_Clear_Out   = 1'b0;
        MIE_Set_Out     = 1'b0;
      end

      STATE_TRAP_TAKEN: begin
        PC_Src_Out      = PC_SRC_TRAP;
        Flush_Out       = 1'b1;
        Instret_Inc_Out = 1'b0;
        Set_EPC_Out     = 1'b1;  //! Latch PC into mepc
        Set_Cause_Out   = 1'b1;  //! Latch cause into mcause
        MIE_Clear_Out   = 1'b1;  //! Save MIE→MPIE, disable interrupts
        MIE_Set_Out     = 1'b0;
      end

      STATE_TRAP_RETURN: begin
        PC_Src_Out      = PC_SRC_EPC;
        Flush_Out       = 1'b1;
        Instret_Inc_Out = 1'b0;
        Set_EPC_Out     = 1'b0;
        Set_Cause_Out   = 1'b0;
        MIE_Clear_Out   = 1'b0;
        MIE_Set_Out     = 1'b1;  //! Restore MIE←MPIE on MRET
      end

      default: begin
        PC_Src_Out      = PC_SRC_NEXT;
        Flush_Out       = 1'b0;
        Instret_Inc_Out = 1'b1;
        Set_EPC_Out     = 1'b0;
        Set_Cause_Out   = 1'b0;
        MIE_Clear_Out   = 1'b0;
        MIE_Set_Out     = 1'b0;
      end

    endcase
  end

  // ============================================================
  //! FSM — State Register (sequential)
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) Curr_State <= STATE_RESET;
    else        Curr_State <= Next_State;
  end

  // ============================================================
  //! Misaligned Exception Flag Register (sequential)
  //! Registered one cycle ahead of Set_Cause_Out so MTVal_Reg
  //! sees a stable value when it decides whether to store the
  //! faulting address into mtval.
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In)
      Misaligned_Exc_Out <= 1'b0;
    else
      Misaligned_Exc_Out <= Misaligned_Instr_In | Misaligned_Load_In | Misaligned_Store_In;
  end

  // ============================================================
  //! Cause and I_Or_E Registers (sequential)
  //! Pre-computed in STATE_OPERATING so the values are stable when
  //! STATE_TRAP_TAKEN asserts Set_Cause_Out on the following cycle.
  //!
  //! BUG FIX vs original msrv32_machine_control.v:
  //! The original used nested if/else-if WITHOUT begin/end around
  //! the STATE_OPERATING check, so the `else if(mie_in & sip)` and
  //! all subsequent branches were at the top always-block level —
  //! they fired in TRAP_TAKEN and TRAP_RETURN states as well,
  //! corrupting cause_out during trap sequencing.
  //! Fixed by wrapping the entire priority chain inside
  //! `if (Curr_State == STATE_OPERATING) begin ... end`.
  // ============================================================
  always @(posedge Clk_In) begin
    if (Rst_In) begin
      Cause_Out  <= 4'b0;
      I_Or_E_Out <= 1'b0;
    end
    else if (Curr_State == STATE_OPERATING) begin
      if (MIE_In & EIP) begin
        Cause_Out  <= 4'b1011;  //! Machine external interrupt
        I_Or_E_Out <= 1'b1;
      end
      else if (MIE_In & SIP) begin
        Cause_Out  <= 4'b0011;  //! Machine software interrupt
        I_Or_E_Out <= 1'b1;
      end
      else if (MIE_In & TIP) begin
        Cause_Out  <= 4'b0111;  //! Machine timer interrupt
        I_Or_E_Out <= 1'b1;
      end
      else if (Illegal_Instr_In) begin
        Cause_Out  <= 4'b0010;  //! Illegal instruction
        I_Or_E_Out <= 1'b0;
      end
      else if (Misaligned_Instr_In) begin
        Cause_Out  <= 4'b0000;  //! Instruction address misaligned
        I_Or_E_Out <= 1'b0;
      end
      else if (ECALL) begin
        Cause_Out  <= 4'b1011;  //! Environment call from M-mode
        I_Or_E_Out <= 1'b0;
      end
      else if (EBREAK) begin
        Cause_Out  <= 4'b0011;  //! Breakpoint
        I_Or_E_Out <= 1'b0;
      end
      else if (Load_Access_Fault_In) begin
        Cause_Out  <= 4'b0101;  //! Load access fault (data bus error)
        I_Or_E_Out <= 1'b0;
      end
      else if (Misaligned_Store_In) begin
        Cause_Out  <= 4'b0110;  //! Store/AMO address misaligned
        I_Or_E_Out <= 1'b0;
      end
      else if (Misaligned_Load_In) begin
        Cause_Out  <= 4'b0100;  //! Load address misaligned
        I_Or_E_Out <= 1'b0;
      end
      //! No trap this cycle: hold current values
    end
    //! TRAP_TAKEN / TRAP_RETURN: hold stable so MCause_Reg latches correctly
  end

endmodule
