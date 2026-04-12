//! Write-Enable Generator
//! Gates the integer register file and CSR file write-enable signals
//! with the pipeline flush signal from Machine_Control.
//!
//! When Flush_In is asserted (trap entry, trap return, or branch taken),
//! any instruction currently in the pipeline that has not yet committed
//! must be prevented from writing its result. This module ensures that
//! both write ports are suppressed to zero during a flush, regardless
//! of what the pipeline registers are carrying.
//!
//! This is the only module that should gate these write-enables —
//! no other logic in the pipeline should add additional AND conditions
//! on Reg_WrEn or CSR_WrEn to avoid creating redundant gating paths.
module WrEn_Generator (
  input         Flush_In,        //! Pipeline flush from Machine_Control — suppresses all writes
  input         Reg_WrEn_In,     //! Integer register file write enable from pipeline register
  input         CSR_WrEn_In,     //! CSR file write enable from pipeline register
  output        Reg_WrEn_Out,    //! Gated integer register file write enable → Register_File
  output        CSR_WrEn_Out     //! Gated CSR file write enable → CSR_File
);

  // ============================================================
  //! Write-Enable Gating
  //! Both enables are unconditionally cleared on flush.
  //! When not flushing, the pipeline register values pass through.
  // ============================================================
  assign Reg_WrEn_Out = Flush_In ? 1'b0 : Reg_WrEn_In;
  assign CSR_WrEn_Out = Flush_In ? 1'b0 : CSR_WrEn_In;

endmodule
