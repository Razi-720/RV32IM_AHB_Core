# RV32IM_AHB_Core

A high-performance, fully verified **5-stage pipelined RISC-V core** supporting RV32IM + Zicsr extensions with integrated AHB-Lite memory interfaces. Designed for embedded systems with emphasis on timing closure and area optimization.

### Key Highlights

- ✅ **Fully Verified**: 235 test cases passing (100% pass rate)
- 🚀 **High Performance**: 71.43 MHz Fmax @ 14 ns period
- 🏗️ **Lean Design**: 173,749 µm² total core area
- 🔧 **Production Ready**: Complete synthesis and STA flow included
- 📚 **Well Documented**: Comprehensive design verification and implementation guides

## Project Snapshot

| Item | Value |
|---|---|
| Top module | Pip_RV32IM_AHB |
| ISA | RV32I + M + Zicsr |
| Pipeline | IF, ID, EX, MEM, WB |
| Privilege mode | Machine mode |
| Verification status | PASS=235, FAIL=0, TOTAL=235 |
| Latest measured Fmax | 71.43 MHz (best passing period 14 ns) |

## Features & Capabilities

### ISA Support
- **Base**: RV32I (RISC-V 32-bit integer)
- **Extensions**: 
  - M: Multiplication and division
  - Zicsr: Control and status registers for machine mode
- **Privilege Mode**: Machine mode only

### Microarchitecture
- **Pipeline Stages**: 5-stage (IF → ID → EX → MEM → WB)
- **Hazard Detection**: Full forwarding and stall logic
- **Branch Prediction**: Static prediction with optional speculative execution
- **CSR Support**: Full machine mode CSRs (MISA, MStatus, MTVEC, MEPC, MCause, MIP, MIE, MTVal, MScratch)
- **Interrupt Handling**: Software and timer interrupts with prioritized exception handling

### Memory Interface
- **Instruction Interface**: AHB-Lite compliant read-only
- **Data Interface**: AHB-Lite compliant read/write with byte enable support
- **Load/Store Units**: Dedicated units for aligned and unaligned memory operations

## Current PPA (R1)

| Metric | R0 | R1 | Delta |
|---|---:|---:|---:|
| Best passing period | 16.00 ns | 14.00 ns | -2.00 ns |
| Fmax | 62.50 MHz | 71.43 MHz | +8.93 MHz |
| WNS @ 10 ns | -4.27 ns | -3.35 ns | +0.92 ns |
| TNS @ 10 ns | -183.95 ns | -151.77 ns | +32.18 ns |
| Core area | N/A | 173749.1392 um^2 | N/A |
| Sequential area | N/A | 61498.9824 um^2 (35.40%) | N/A |
| Total power | N/A | 9.92e-02 W | N/A |

## Repository Structure

```text
RV32IM_AHB_Core/
├── include/
│   └── rv_defs.vh
├── rtl_rv32im_ahb_core/
│   ├── top/
│   ├── pipeline_registers/
│   ├── control/
│   ├── datapath_units/
│   ├── csr/
│   ├── memory_if/
│   ├── multiply/
│   └── hazards/
├── tb_rv32im_ahb_core/
├── syn_sta_rv32im_ahb_core/
│   ├── scripts/
│   ├── constraints/
│   ├── reports/
│   └── netlist/
├── docs/
│   ├── Design_Verfication.md
│   ├── Synthesis_STA.md
│   └── FIX_REFERENCE.md
└── Makefile
```

## Quick Start

### Environment Setup

This project is optimized for the **IIC-OSIC-TOOLS** container environment, which provides:
- Verilator (RTL simulation & linting)
- Yosys (synthesis)
- OpenSTA (timing analysis & power estimation)
- GTKWave (waveform visualization)
- SKY130 PDK (130nm node for synthesis)

**Installation**: https://github.com/iic-jku/IIC-OSIC-TOOLS

### Prerequisites

```bash
# Core tools required:
verilator >= 5.046
yosys >= 0.64
opensta >= 3.1.0
gtk-wave (for waveform viewing)

# Optional:
python3 (for build scripts)
```

### RTL Simulation & Verification

```bash
# Run lint checks on RTL
make lint

# Run simulation tests
make run

# View waveforms in GTKWave
make wave
```

### Synthesis & STA Flow

```bash
# Run complete flow (synthesis + STA)
make flow

# Or run individually:
make synth        # Yosys synthesis
make sta          # OpenSTA timing/power analysis

# Performance sweeping
make fmax         # Estimate maximum frequency
make fmax_hs      # Sweep using HS library variant (if available)
```

## Make Targets

| Target | Purpose | Output |
|---|---|---|
| `make lint` | Verilator lint on RTL | Terminal output |
| `make lint-log` | Lint with saved log | `logs/verilator_lint.log` |
| `make run` | Build and run simulation | Test results, VCD file |
| `make wave` | Open VCD in GTKWave | GTKWave GUI |
| `make synth` | Run Yosys synthesis | `netlist/synthesized_netlist.*` |
| `make sta` | Run OpenSTA timing/power | `reports/timing/`, `reports/power/` |
| `make flow` | Run synth then sta | Combined synthesis & timing reports |
| `make fmax` | Sweep period to find Fmax | `reports/synthesis/synthesis_stats.txt` |
| `make fmax_hs` | Fmax sweep with HS library | Performance results with HS variant |
| `make files` | Print resolved source lists | RTL and testbench file lists |
| `make clean` | Remove all generated outputs | Clean workspace state |

## RTL Modules

### Core Hierarchy

```
Pip_RV32IM_AHB (top)
├── Control Unit (Decoder, Instruction Decoder, Machine Control)
├── Datapath (ALU, Register File, PC Unit, Extend Unit)
├── CSR File (Machine mode control and status registers)
├── Hazard Detection (Forwarding and pipeline control)
├── Memory Interface (Load/Store units with AHB-Lite)
├── Multiply/Divide Unit (Booth multiplier, non-restoring divider)
└── Pipeline Registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
```

### Module Organization

| Directory | Purpose |
|-----------|---------|
| `rtl_rv32im_ahb_core/control/` | Instruction decoding and control signal generation |
| `rtl_rv32im_ahb_core/datapath_units/` | Computation (ALU, register file, immediates) |
| `rtl_rv32im_ahb_core/csr/` | CSR registers (MISA, MStatus, MTVEC, MEPC, etc.) |
| `rtl_rv32im_ahb_core/pipeline_registers/` | Stage boundary registers |
| `rtl_rv32im_ahb_core/memory_if/` | Load/Store units and memory operations |
| `rtl_rv32im_ahb_core/multiply/` | M-extension: Multiply and divide units |
| `rtl_rv32im_ahb_core/hazards/` | Pipeline hazard detection and resolution |
| `rtl_rv32im_ahb_core/top/` | Top-level module (Pip_RV32IM_AHB) |

## Verification & Testing

### Test Coverage

**Current Status**: ✅ **235/235 tests passing (100%)**

### Test Suites

| Testbench | Purpose |
|-----------|---------|
| `tb_Pip_RV32IM_AHB.v` | Core functionality tests (primary suite) |
| `tb_stress_regression_Pip_RV32IM_AHB.v` | Extended regression suite |
| `tb2_Pip_RV32IM_AHB.v` | Additional test variants |
| `tb_Machine_Control.v` | Control unit unit tests |
| `tb_CSR_File.v` | CSR file functional verification |
| `tb_MDU.v` | Multiply/divide unit tests |

### Running Tests

```bash
# Build and run all tests
make run

# View waveforms of test execution
make wave

# Generate lint report without running tests
make lint
```

## Documentation

### Design & Implementation

| Document | Content |
|----------|---------|
| [Design_Verfication.md](docs/Design_Verfication.md) | Microarchitecture details, pipeline design, hazard resolution, verification plan, and test strategy |
| [Synthesis_STA.md](docs/Synthesis_STA.md) | Synthesis flow, timing constraints, STA methodology, PPA tracking, and timing closure approach |
| [FIX_REFERENCE.md](docs/FIX_REFERENCE.md) | Historical RV32I fixes, performance improvements, and design iterations |

### Key Design Files

- [rv_defs.vh](include/rv_defs.vh) - Instruction format definitions and constants
- [Pip_RV32IM_AHB.v](rtl_rv32im_ahb_core/top/Pip_RV32IM_AHB.v) - Top-level module

## Known Issues & Notes

### Current Limitations

- **Timing Closure**: Closure at 10 ns period is still in progress (current best: 14 ns)
- **OpenSTA Integration**: Area reporting depends on build configuration; fall back to Yosys synthesis stats if unavailable
- **HS Library**: HS (high-speed) variants require matching library files in runtime environment

### Performance Characteristics(130nm PDK)

- **Current Fmax**: 71.43 MHz (14 ns period)
- **Worst Negative Slack (WNS) @ 10 ns**: -3.35 ns
- **Total Negative Slack (TNS) @ 10 ns**: -151.77 ns
- **Core Area**: 173,749.14 µm²
  - Sequential (registers): 35.40% of total
  - Combinational logic: 64.60% of total
- **Power @ Fmax**: ~99.2 mW (estimated)

## Future Work & Optimization

- [ ] Timing closure for 10 ns period
- [ ] Additional test coverage for edge cases
- [ ] Performance profiling and optimization
- [ ] Design space exploration (area vs. frequency tradeoffs)

## Troubleshooting

### Issue: Simulation fails to build

**Solution**: Ensure Verilator is installed and accessible. Run from within the IIC-OSIC-TOOLS container.

### Issue: Synthesis reports don't include area information

**Solution**: OpenSTA area command may not be available. Use Yosys synthesis stats in `reports/synthesis/synthesis_stats.txt` instead.

### Issue: HS sweep fails

**Solution**: HS library files must be present. Use standard `make fmax` instead or ensure library files are available in `syn_sta_rv32im_ahb_core/lib/`.

## Additional Resources

- [RISC-V Specification](https://riscv.org/technical/specifications/)
- [RISC-V ISA Manual](https://github.com/riscv/riscv-isa-manual)
- [AHB-Lite Protocol](https://developer.arm.com/documentation/)
- [IIC-OSIC-TOOLS Repository](https://github.com/iic-jku/IIC-OSIC-TOOLS)
- [Yosys Documentation](http://yosyshq.net/yosys/)
- [OpenSTA Documentation](https://github.com/The-OpenROAD-Project/OpenSTA)

## Maintainer

**Razi Ahmed**  
📧 md.razi720@gmail.com