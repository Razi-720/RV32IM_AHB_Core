# Design and Verification Guide

## Scope
This document captures the active architecture and verification status for Pip_RV32IM_AHB.

## Design Summary

| Item | Description |
|---|---|
| ISA | RV32I + RV32M + Zicsr |
| Pipeline | 5-stage in-order (IF, ID, EX, MEM, WB) |
| Privilege | Machine mode |
| Branch policy | Static not-taken |
| MDU policy | Handshake based, MUL path registered, DIV iterative |
| Bus model | AHB-Lite aware split instruction and data channels |

## Top-Level Interface Highlights

Instruction side:

- Instruction_In
- Instr_Addr_Out
- Instr_HReady_In

Data side:

- DM_Data_In, DM_Addr_Out, DM_Data_Out
- DM_Mask_Out, DM_WrEn_Out
- Data_HReady_In, HResp_In
- Data_HTrans_Out, Data_HSize_Out

Interrupt and timing side:

- EIrq_In, TIrq_In, SIrq_In
- RTC_In

## Pipeline and Hazard Behavior

- Forwarding is implemented for EX and MEM result reuse paths.
- Load-use hazards trigger controlled stalls.
- Data and instruction ready back-pressure can stall pipeline progress.
- M-extension operations use explicit start/ready sequencing.
- Trap/flush control coordinates with CSR and machine control logic.

## MDU Notes

- MUL result is registered to reduce long combinational delay impact.
- DIV and REM operations are iterative and hold pipeline until ready.
- Start and ready behavior is unified so execute-stage control remains stable during stalls.

## Verification Environment

| Item | Value |
|---|---|
| Simulator | Verilator |
| Testbench | tb_rv32im_ahb_core/tb_Pip_RV32IM_AHB.v |
| Style | Directed self-checking tests |
| Current aggregate result | PASS=235, FAIL=0, TOTAL=235 |

## Verification Coverage Areas

- RV32I ALU operations
- Immediate, load, store, and branch behavior
- Forwarding and load-use hazards
- Jump and trap flows
- CSR accesses and machine-mode trap control
- M-extension functional checks
- AHB wait-state behavior with ready back-pressure
- Access-fault signaling through HResp_In

## Run Instructions

```bash
make lint
make run
```

Waveform debug:

```bash
make wave
```

## Regression Tracking Template

| Run ID | Date | Scope | PASS | FAIL | TOTAL | Notes |
|---|---|---|---:|---:|---:|---|
| SIM-R1 | 2026-04-17 | Directed + stress mix | 137 | 0 | 137 | Current stable baseline |
| SIM-R2 | YYYY-MM-DD | <new scope> | <value> | <value> | <value> | <notes> |

## Open Items

- Add additional edge-case directed tests for consecutive M-extension dependency chains.
- Add more explicit checks for interrupt priority and MRET edge timing.
- Optionally add automated regression summary export for CI integration.
