# Synthesis and STA Guide

## Scope
This document describes the active synthesis and static timing flow for Pip_RV32IM_AHB in this repository.

## Flow Files

| Type | Path |
|---|---|
| Make orchestration | Makefile |
| Yosys script | syn_sta_rv32im_ahb_core/scripts/yosys_script.ys |
| OpenSTA script | syn_sta_rv32im_ahb_core/scripts/sta_script.tcl |
| Main timing constraints | syn_sta_rv32im_ahb_core/constraints/synthesis_constraints.sdc |
| Fmax sweep script | syn_sta_rv32im_ahb_core/scripts/fmax_sweep.sh |

## Run Commands

```bash
make synth
make sta
make flow
make fmax
```

## Library Selection

The Makefile supports HD flavors through LIB_FLAVOR.

- Default: LIB_FLAVOR=hd

If liberty files are missing in the active environment, make synth and make sta will fail fast with a clear error.

## Reporting Files

| Report | Path |
|---|---|
| Yosys synthesis log | syn_sta_rv32im_ahb_core/reports/synthesis/yosys.log |
| Synthesis stats | syn_sta_rv32im_ahb_core/reports/synthesis/synthesis_stats.txt |
| WNS summary | syn_sta_rv32im_ahb_core/reports/timing/report_wns.rpt |
| TNS summary | syn_sta_rv32im_ahb_core/reports/timing/report_tns.rpt |
| Detailed checks | syn_sta_rv32im_ahb_core/reports/timing/report_checks.rpt |
| Area report (if supported by STA build) | syn_sta_rv32im_ahb_core/reports/area/report_area.rpt |
| Power report | syn_sta_rv32im_ahb_core/reports/power/report_power.rpt |

## Current Performance Snapshot (130nm PDK)

| Metric | Value |
|---|---:|
| Best passing period | 14.00 ns |
| Estimated Fmax | 71.43 MHz |
| WNS @ 10 ns | -3.35 ns |
| TNS @ 10 ns | -151.77 ns |
| Core area | 173749.1392 um^2 |
| Sequential area | 61498.9824 um^2 (35.40%) |
| Total power | 9.92e-02 W |

## PPA Tracking Method

Use one fixed comparison point for quality tracking:

1. Keep synthesis_constraints.sdc at 10 ns when recording WNS and TNS trend.
2. Use make fmax only to identify the best passing period and derived Fmax.
3. Record each run as a new row in your run history table.

Fmax formula:

- Fmax (MHz) = 1000 / Period(ns)

## Practical Optimization Order

1. Remove long combinational arcs in RTL first.
2. Re-run synth + sta and confirm WNS and TNS movement.
3. Only then tighten period in fmax sweep.
4. If available, compare HD vs HS.
5. Keep area flow separate using area_opt and area_report.

## Known Caveats

- Some OpenSTA builds do not provide report_area or report_design_area.
- Pin-name-dependent multicycle constraints may break after synthesis rename/flatten changes.
- Power is activity-dependent; default vectorless power is useful for relative comparison only.
