# RV32IM_AHB_Core

A Verilog implementation of a 5-stage pipelined RISC-V CPU core with:

- RV32I base integer ISA
- Zicsr CSR support
- RV32M multiply/divide extension
- AHB-lite style instruction/data memory handshake signals

This repository includes synthesizable RTL, directed testbenches, and a Verilator-based simulation flow.

## Features

- 5-stage pipeline: Fetch, Decode, Execute, Memory, Writeback
- Hazard handling and data forwarding
- Branch and control-flow handling
- CSR subsystem for machine-mode state and counters
- MDU support for MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
- AHB-lite readiness and response integration:
  - Instruction-side ready gating
  - Data-side ready stall handling
  - Data transfer type and size signaling
  - Access-fault propagation via bus response

## Directory Layout

- include/
  - Shared definitions and macros (for example rv_defs.vh)
- rtl_rv32im_ahb_core/
  - top/: core top-level module
  - datapath_units/: ALU, PC unit, register file, and related datapath blocks
  - pipeline_registers/: F/D, D/E, E/M, M/W stage registers
  - control/: instruction decode and machine control logic
  - csr/: CSR file and machine CSRs/counters
  - memory_if/: load/store path logic
  - multiply/: multiplier/divider and MDU logic
  - hazards/: hazard detection and forwarding control
- tb_rv32im_ahb_core/
  - Main directed testbenches for core verification
- sim_rv32im_ahb_core/
  - Generated Verilator simulation output (ignored by Git)
- waves/
  - Generated waveform files (ignored by Git)

## Tool Requirements

- Linux environment
- GNU Make
- Verilator
- GTKWave (optional, for waveform viewing)

Suggested package install on Ubuntu:

```bash
sudo apt update
sudo apt install -y make verilator gtkwave
```

## Quick Start

From the project root:

```bash
make lint
make run
make wave
```

What each target does:

- make lint
  - Runs Verilator lint on RTL only
- make run
  - Compiles testbench + RTL using Verilator
  - Runs the simulation executable
  - Moves generated VCD to waves/tb_Pip_RV32I.vcd
- make wave
  - Opens waves/tb_Pip_RV32I.vcd in GTKWave

Useful additional targets:

- make files
  - Prints all resolved RTL source files and testbench source path
- make lint-log
  - Saves lint output to logs/verilator_lint.log
- make clean
  - Removes generated simulation, wave, and lint log directories/files

## Current Top-Level Names in Build Flow

From the Makefile:

- RTL top module: Pip_RV32I
- Testbench module used by make run: tb_Pip_RV32I

## Verification Notes

The testbench in tb_rv32im_ahb_core/tb_Pip_RV32I.v includes broad directed testing for:

- Arithmetic and logic instructions
- Branch and jump behavior
- Loads/stores and alignment behavior
- CSR operations and machine trap flow
- Interrupt handling
- RV32M operations and pipeline stall behavior for division/remainder

The reference note in FIX_REFERENCE.md records previously verified passing summaries, including:

- PASS=93, FAIL=0, TOTAL=93
- Later stress extension regression: PASS=137, FAIL=0, TOTAL=137

Use make run to reproduce the current status in your local environment.

## AHB-lite Interface Intent

The core exposes separate instruction and data memory channels with handshake signals that allow wait states and access-fault signaling.

Instruction side:

- Instruction_In, Instr_Addr_Out, Instr_HReady_In

Data side:

- DM_Data_In, DM_Addr_Out, DM_Data_Out, DM_Mask_Out, DM_WrEn_Out
- Data_HReady_In, HResp_In, Data_HTrans_Out, Data_HSize_Out

This allows the pipeline to stall appropriately on memory wait states and reflect data-bus transfer metadata.

## Git Workflow

Typical update flow:

```bash
git add .
git commit -m "Describe your change"
git push
```

This repository already ignores generated outputs such as:

- sim_rv32im_ahb_core/
- **/obj_dir/
- *.vcd
- waves/

## Troubleshooting

- Verilator not found:
  - Install Verilator and confirm with verilator --version
- No waveform file after make run:
  - Check simulation output for early failures
  - Confirm waves/tb_Pip_RV32I.vcd is created
- GTKWave does not open:
  - Install gtkwave package
  - Open manually: gtkwave waves/tb_Pip_RV32I.vcd
- Stale build artifacts:
  - Run make clean, then rerun lint/sim

## Future Improvements

- Add CI workflow for automated lint and simulation on push
- Add constrained-random and coverage-driven verification
- Add memory model adapters for full AHB-lite protocol environments
- Add synthesis scripts and timing/resource reports

## Author

Maintained in this repository by Razi-720.
