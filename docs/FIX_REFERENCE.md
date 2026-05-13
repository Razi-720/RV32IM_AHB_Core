# Legacy Fix Reference

## Purpose
This file keeps historical fix notes from the earlier RV32I-focused stage of development.
It is retained for traceability only.

## Current Project Context

| Item | Current Value |
|---|---|
| Active top | Pip_RV32IM_AHB |
| Active RTL root | rtl_rv32im_ahb_core |
| Active testbench root | tb_rv32im_ahb_core |
| Active docs | docs/Design_Verfication.md and docs/Synthesis_STA.md |

## Legacy-to-Current Path Mapping

| Legacy Path Style | Current Path Style |
|---|---|
| rtl/risc-v_cpu_rtl/... | rtl_rv32im_ahb_core/... |
| tb/risc-v_cpu_tb/... | tb_rv32im_ahb_core/... |
| Pip_RV32I | Pip_RV32IM_AHB |

## Historical Verification Snapshot

- Earlier milestone result: PASS=93, FAIL=0, TOTAL=93
- Current milestone result: PASS=137, FAIL=0, TOTAL=137

## Historical Fix Themes

- CSR decode/read path completeness
- Trap and exception state update alignment
- Store write-enable and misalignment handling
- Branch test vector corrections
- Testbench expectation cleanup and stress extensions

For active design and verification details, use:

- docs/Design_Verfication.md
- docs/Synthesis_STA.md
