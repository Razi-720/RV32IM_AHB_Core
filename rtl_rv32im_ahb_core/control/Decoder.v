//! Instruction Decoder
//! Decodes the instruction opcode, funct3, and funct7 fields into all
//! pipeline control signals. Supports the full RV32I base ISA plus the
//! Zicsr extension (CSRRW, CSRRS, CSRRC and their immediate variants)
//! and the RV32M multiply/divide extension.
//!
//! Result_Src encoding (used by WB_Unit):
//!   3'b000 — default / no writeback
//!   3'b001 — ALU result        (R-type, I-type ALU)
//!   3'b010 — Immediate value   (LUI)
//!   3'b011 — PC + Immediate    (AUIPC)
//!   3'b100 — PC + 4            (JAL, JALR)
//!   3'b101 — Load data         (Load)
//!   3'b110 — CSR read data     (CSR instructions)
//!   3'b111 — MDU result        (RV32M multiply/divide)
//!
//! Misalignment detection:
//!   Word  (funct3[1:0]=10): misaligned if Iadder_1to0_In[1] | Iadder_1to0_In[0]
//!   Half  (funct3[1:0]=01): misaligned if Iadder_1to0_In[0]
//!   Byte  (funct3[1:0]=00): always aligned
//!   Misaligned_Load_Out / Misaligned_Store_Out feed Machine_Control.
//!   DM_WrEn_Out is suppressed when a store is misaligned or trap is taken.
module Decoder (
  input         Trap_Taken_In,       //! From Machine_Control: suppress all outputs to NOP
  input  [1:0]  Iadder_1to0_In,      //! Effective address [1:0] from Imm_Adder — misalignment check

  input  [6:0]  Opcode_In,           //! 7-bit opcode field  [6:0]
  input  [2:0]  Func3_In,            //! funct3 field        [14:12]
  input         Func7_In,            //! funct7 bit 30 only  [30] — distinguishes SUB/SRA/SRAI
  input  [6:0]  Func7_Full_In,       //! funct7 full field   [31:25] — M-extension detect

  //! ── RV32I base outputs ──────────────────────────────────────
  output reg        Reg_WrEn_Out,        //! Integer register file write enable
  output reg [2:0]  Imm_Type_Out,        //! Immediate encoding: 000=none 001=I 010=S 011=B 100=U 101=J
  output reg        Iadder_Src_Out,      //! Immediate adder base: 0=PC, 1=RS1
  output reg        ALU_Src_Out,         //! ALU second source: 0=RS2, 1=immediate
  output reg [3:0]  ALU_Control_Out,     //! ALU operation selector
  output reg        DM_WrEn_Out,         //! Store write enable (0 when misaligned or trap taken)
  output reg [7:0]  Branch_Cond_Out,     //! One-hot branch/jump type {BGEU,BLTU,BGE,BLT,BNE,BEQ,JALR,JAL}
  output reg        Load_Unsigned_Out,   //! 1=zero-extend load, 0=sign-extend
  output reg [1:0]  Load_Size_Out,       //! Load width: 00=byte 01=half 10=word
  output reg [2:0]  Result_Src_Out,      //! Write-back source selector (see encoding above)

  //! ── Zicsr extension outputs ─────────────────────────────────
  output reg        CSR_WrEn_Out,        //! CSR file write enable
  output reg [2:0]  CSR_Op_Out,          //! CSR operation: funct3 passed through (RW/RS/RC + imm bit)

  //! ── RV32M extension outputs ─────────────────────────────────
  output reg        Is_Mext_Out,         //! 1 = RV32M instruction — route operands to MDU
  output reg [2:0]  MDU_Op_Out,          //! funct3 passed to MDU: selects MUL/MULH/DIV/REM variant

  //! ── Exception outputs ───────────────────────────────────────
  output            Illegal_Instr_Out,   //! Unrecognised opcode — routed to Machine_Control (never gated by Trap_Taken_In)

  //! ── Misalignment exception outputs ──────────────────────────
  output            Misaligned_Load_Out,  //! Load address misaligned → Machine_Control
  output            Misaligned_Store_Out  //! Store address misaligned → Machine_Control
);

  // ============================================================
  //! Combinatorial Decode
  // ============================================================
  /* verilator lint_off CASEINCOMPLETE */
  always @* begin
    //! ── Default values (NOP / no side-effects) ──────────────
    Reg_WrEn_Out     = 1'b0;
    Imm_Type_Out     = 3'b000;
    Iadder_Src_Out   = 1'b0;
    ALU_Src_Out      = 1'b0;
    ALU_Control_Out  = 4'b0000;
    DM_WrEn_Out      = 1'b0;
    Branch_Cond_Out  = 8'b0;
    Load_Unsigned_Out= 1'b0;
    Load_Size_Out    = 2'b00;
    Result_Src_Out   = 3'b000;
    CSR_WrEn_Out     = 1'b0;
    CSR_Op_Out       = 3'b000;
    Is_Mext_Out      = 1'b0;
    MDU_Op_Out       = 3'b000;

    //! When a trap is being taken, suppress all control signals
    //! so the flushed instruction produces no side-effects.
    if (Trap_Taken_In) begin
      //! All outputs remain at their default NOP values above
    end
    else begin
      case (Opcode_In)

        // ──────────────────────────────────────────────────────
        //! R-type: RV32I ADD SUB SLL SLT SLTU XOR SRL SRA OR AND
        //!         RV32M MUL MULH MULHSU MULHU DIV DIVU REM REMU
        //! Both use opcode 7'b0110011.
        //! funct7 = 7'b0000001 → RV32M, all others → RV32I.
        // ──────────────────────────────────────────────────────
        7'b0110011: begin
          Reg_WrEn_Out = 1'b1;

          if (Func7_Full_In == 7'b0000001) begin
            //! ── RV32M multiply / divide / remainder ─────────
            //! The ALU is bypassed entirely for these instructions.
            //! ALU_Src and ALU_Control remain at NOP defaults —
            //! they are don't-care when Result_Src = 3'b111.
            Is_Mext_Out    = 1'b1;
            MDU_Op_Out     = Func3_In;     //! funct3 directly selects MDU operation
            Result_Src_Out = 3'b111;       //! write-back from MDU result
          end
          else begin
            //! ── RV32I register-register ALU ─────────────────
            ALU_Src_Out    = 1'b0;
            Result_Src_Out = 3'b001;
            case ({Func7_In, Func3_In})
              4'b0000: ALU_Control_Out = 4'b0000; //! ADD
              4'b1000: ALU_Control_Out = 4'b1000; //! SUB
              4'b0001: ALU_Control_Out = 4'b0001; //! SLL
              4'b0010: ALU_Control_Out = 4'b0010; //! SLT
              4'b0011: ALU_Control_Out = 4'b0011; //! SLTU
              4'b0100: ALU_Control_Out = 4'b0100; //! XOR
              4'b0101: ALU_Control_Out = 4'b0101; //! SRL
              4'b1101: ALU_Control_Out = 4'b1101; //! SRA
              4'b0110: ALU_Control_Out = 4'b0110; //! OR
              4'b0111: ALU_Control_Out = 4'b0111; //! AND
              default: ALU_Control_Out = 4'b0000;
            endcase
          end
        end

        // ──────────────────────────────────────────────────────
        //! I-type ALU: ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
        // ──────────────────────────────────────────────────────
        7'b0010011: begin
          Reg_WrEn_Out   = 1'b1;
          ALU_Src_Out    = 1'b1;
          Imm_Type_Out   = 3'b001;
          Result_Src_Out = 3'b001;
          case (Func3_In)
            3'b000: ALU_Control_Out = 4'b0000;                            //! ADDI
            3'b001: ALU_Control_Out = 4'b0001;                            //! SLLI
            3'b010: ALU_Control_Out = 4'b0010;                            //! SLTI
            3'b011: ALU_Control_Out = 4'b0011;                            //! SLTIU
            3'b100: ALU_Control_Out = 4'b0100;                            //! XORI
            3'b101: ALU_Control_Out = Func7_In ? 4'b1101 : 4'b0101;      //! SRAI / SRLI
            3'b110: ALU_Control_Out = 4'b0110;                            //! ORI
            3'b111: ALU_Control_Out = 4'b0111;                            //! ANDI
          endcase
        end

        // ──────────────────────────────────────────────────────
        //! Load: LB LH LW LBU LHU
        // ──────────────────────────────────────────────────────
        7'b0000011: begin
          Reg_WrEn_Out     = 1'b1;
          ALU_Src_Out      = 1'b1;
          Imm_Type_Out     = 3'b001;
          Iadder_Src_Out   = 1'b1;
          Result_Src_Out   = 3'b101;
          Load_Size_Out    = Func3_In[1:0];
          Load_Unsigned_Out= Func3_In[2];
          ALU_Control_Out  = 4'b0000;
        end

        // ──────────────────────────────────────────────────────
        //! Store: SB SH SW
        // ──────────────────────────────────────────────────────
        7'b0100011: begin
          DM_WrEn_Out    = ~Trap_Taken_In;
          ALU_Src_Out    = 1'b1;
          Imm_Type_Out   = 3'b010;
          Iadder_Src_Out = 1'b1;
          ALU_Control_Out= 4'b0000;
        end

        // ──────────────────────────────────────────────────────
        //! Branch: BEQ BNE BLT BGE BLTU BGEU
        // ──────────────────────────────────────────────────────
        7'b1100011: begin
          Imm_Type_Out = 3'b011;
          case (Func3_In)
            3'b000: Branch_Cond_Out = 8'b00000100; //! BEQ
            3'b001: Branch_Cond_Out = 8'b00001000; //! BNE
            3'b100: Branch_Cond_Out = 8'b00010000; //! BLT
            3'b101: Branch_Cond_Out = 8'b00100000; //! BGE
            3'b110: Branch_Cond_Out = 8'b01000000; //! BLTU
            3'b111: Branch_Cond_Out = 8'b10000000; //! BGEU
            default: ;
          endcase
        end

        // ──────────────────────────────────────────────────────
        //! JAL
        // ──────────────────────────────────────────────────────
        7'b1101111: begin
          Reg_WrEn_Out   = 1'b1;
          Imm_Type_Out   = 3'b101;
          Result_Src_Out = 3'b100;
          Branch_Cond_Out= 8'b00000001;
        end

        // ──────────────────────────────────────────────────────
        //! JALR
        // ──────────────────────────────────────────────────────
        7'b1100111: begin
          Reg_WrEn_Out   = 1'b1;
          Imm_Type_Out   = 3'b001;
          Iadder_Src_Out = 1'b1;
          Result_Src_Out = 3'b100;
          Branch_Cond_Out= 8'b00000010;
        end

        // ──────────────────────────────────────────────────────
        //! LUI
        // ──────────────────────────────────────────────────────
        7'b0110111: begin
          Reg_WrEn_Out   = 1'b1;
          Imm_Type_Out   = 3'b100;
          Result_Src_Out = 3'b010;
        end

        // ──────────────────────────────────────────────────────
        //! AUIPC
        // ──────────────────────────────────────────────────────
        7'b0010111: begin
          Reg_WrEn_Out   = 1'b1;
          Imm_Type_Out   = 3'b100;
          Result_Src_Out = 3'b011;
        end

        // ──────────────────────────────────────────────────────
        //! SYSTEM — CSR instructions and ECALL/EBREAK/MRET
        // ──────────────────────────────────────────────────────
        7'b1110011: begin
          case (Func3_In)
            3'b000: begin
              Reg_WrEn_Out = 1'b0;
              CSR_WrEn_Out = 1'b0;
            end
            3'b001, 3'b010, 3'b011,
            3'b101, 3'b110, 3'b111: begin
              Reg_WrEn_Out   = 1'b1;
              CSR_WrEn_Out   = 1'b1;
              CSR_Op_Out     = Func3_In;
              Result_Src_Out = 3'b110;
              Imm_Type_Out   = 3'b001;
            end
            default: begin end
          endcase
        end

        // ──────────────────────────────────────────────────────
        //! MISC-MEM: FENCE — treated as NOP
        // ──────────────────────────────────────────────────────
        7'b0001111: begin
          //! NOP defaults — FENCE is a no-op in this in-order pipeline
        end

        default: begin end

      endcase
    end
  end
  /* verilator lint_on CASEINCOMPLETE */

  // ============================================================
  //! Misalignment Detection (combinatorial)
  // ============================================================
  wire Is_Load  = (Opcode_In[6:2] == 5'b00000);
  wire Is_Store = (Opcode_In[6:2] == 5'b01000);

  wire Mal_Word   = Func3_In[1] & ~Func3_In[0]
                  & (Iadder_1to0_In[1] | Iadder_1to0_In[0]);
  wire Mal_Half   = ~Func3_In[1] & Func3_In[0] & Iadder_1to0_In[0];
  wire Misaligned = Mal_Word | Mal_Half;

  assign Misaligned_Load_Out  = Is_Load  & Misaligned;
  assign Misaligned_Store_Out = Is_Store & Misaligned;

  // ============================================================
  //! Illegal Instruction Detection (independent of Trap_Taken_In)
  //! Must NOT be gated by Trap_Taken_In to avoid combinational loop.
  //! opcode 7'b0110011 covers both RV32I R-type and RV32M — both legal.
  // ============================================================
  reg Illegal_Instr_Reg;
  assign Illegal_Instr_Out = Illegal_Instr_Reg;

  always @* begin
    case (Opcode_In)
      7'b0110011,  //! R-type (RV32I) + M-extension (RV32M) — same opcode
      7'b0010011,  //! I-type ALU
      7'b0000011,  //! Load
      7'b0100011,  //! Store
      7'b1100011,  //! Branch
      7'b1101111,  //! JAL
      7'b1100111,  //! JALR
      7'b0110111,  //! LUI
      7'b0010111,  //! AUIPC
      7'b0001111,  //! FENCE
      7'b1110011:  //! SYSTEM
        Illegal_Instr_Reg = 1'b0;
      default:
        Illegal_Instr_Reg = 1'b1;
    endcase
  end

endmodule
