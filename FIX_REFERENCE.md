# RV32I+Zicsr Fix Reference

This note summarizes the main issues seen in `tb_Pip_RV32I.v` and how they were fixed.

Final verified status:
- `PASS=93`
- `FAIL=0`
- `TOTAL=93`

## 1) CSR reads returned zero for valid CSRs
- Symptom:
  - CSR tests failed (`CSRRS`, `CSRRC`, `CSRSI`, `CSRCI`, `mscratch` readback).
  - Counter CSR reads (`mcycle`, `minstret`) were `0`.
- Root cause:
  - Incomplete CSR address-to-data mapping on read mux path.
- Fix:
  - Added/verified full address decode for machine CSRs and counters:
    - `mstatus`, `misa`, `mie`, `mtvec`
    - `mscratch`, `mepc`, `mcause`, `mtval`, `mip`
    - `mcycle/mcycleh`, `minstret/minstreth`
    - `cycle/time/instret` shadows and high halves
    - `mcountinhibit`
- Files:
  - `rtl/risc-v_cpu_rtl/csr/CSR_Data_Mux_Unit.v`
  - `rtl/risc-v_cpu_rtl/csr/Machine_Counter_Setup.v`

## 2) Trap/exception flow did not update expected state
- Symptom:
  - ECALL/EBREAK/Illegal/MRET/interrupt tests failed in the earlier run.
- Root cause:
  - Trap metadata depended on stale or incomplete exception signaling at the stage boundary.
- Fix:
  - Ensured trap controller receives consistent exception inputs and CSR state updates occur in trap entry/return sequence.
  - After CSR read-path and exception signaling fixes, `mcause/mepc` checks and interrupt cause checks pass.
- Files:
  - `rtl/risc-v_cpu_rtl/control/Machine_Control.v`
  - `rtl/risc-v_cpu_rtl/top/Pip_RV32I.v`

## 3) Store word (`SW`) write was suppressed
- Symptom:
  - Store test failed at `dm[204]` (`SW` wrote `0x0` instead of `0x12345678`).
- Root cause:
  - Store write enable was being suppressed using misalignment information not tied to the final execute-stage effective address.
- Fix:
  - Decoder now gates store write enable only with trap condition.
  - Store_Unit now computes misalignment from current effective address and store width, then gates write enable/masks locally.
  - Top-level now generates execute-stage load/store misalignment signals from `Imm_Added_E[1:0]` and instruction width.
- Files:
  - `rtl/risc-v_cpu_rtl/control/Decoder.v`
  - `rtl/risc-v_cpu_rtl/memory/Store_Unit.v`
  - `rtl/risc-v_cpu_rtl/top/Pip_RV32I.v`

## 4) Branch test failures in T6
- Symptom:
  - `BEQ/BNE/BLT/BGE/BLTU` checks failed in one run even though branch datapath was mostly healthy.
- Root cause:
  - Test vectors used branch offsets/operand setup that did not match the intended target/check pattern.
- Fix:
  - Updated T6 branch immediates to the intended target distance.
  - Corrected BGEU operand setup to match the encoded rs1/rs2 usage.
- File:
  - `tb/risc-v_cpu_tb/tb_Pip_RV32I.v`

## 5) Load-halfword-unsigned (LHU) checks were based on known-bug expectation
- Symptom:
  - Old test expected zero due to a known bug note.
- Root cause:
  - Expected values lagged behind fixed behavior.
- Fix:
  - Updated checks to validate correct zero-extension (`0xCDAB`, `0x01EF`).
- File:
  - `tb/risc-v_cpu_tb/tb_Pip_RV32I.v`

## Quick verification command
```bash
make run
```

Expected tail summary:
```text
RESULTS: PASS=93  FAIL=0  TOTAL=93
*** ALL TESTS PASSED ***
```

## Stress Extension Added (T17-T23)

The testbench was extended with additional corner and robustness checks.

- T17 `ALU Corners`
  - Wraparound arithmetic, signed/unsigned compare boundaries, shift-by-31, and shift-amount masking via rs2[4:0].
- T18 `x0 Integrity`
  - Confirms writes to `x0` are ignored across ALU/LUI/AUIPC/load scenarios.
  - Includes direct hierarchical check of `dut.reg_file.register[0]`.
- T19 `Misaligned Store`
  - SW(+2) and SH(+1) traps.
  - Checks `mcause=6`, `mtval=fault_addr`, canary flush behavior, and memory no-write behavior.
- T20 `Misaligned Load`
  - LW(+2) and LH(+1) traps.
  - Checks `mcause=4`, `mtval=fault_addr`, canary flush behavior.
- T21 `mcountinhibit`
  - Verifies counter freeze/resume behavior for `mcycle` and `minstret` when `mcountinhibit` is set/cleared.
- T22 `Loop Stress`
  - Repeated store/load/branch/hazard interactions in a backward-branch loop.
  - Checks loop count, completion marker, accumulation, and final memory state.
- T23 `IRQ Corner`
  - Global MIE gating check (interrupts blocked when MIE=0).
  - Simultaneous IRQ priority check (external interrupt priority expected).

Latest full regression after stress extension:
```text
RESULTS: PASS=137  FAIL=0  TOTAL=137
*** ALL TESTS PASSED ***
```
