set top Pip_RV32IM_AHB
if {[info exists ::env(LIB_FILE)]} {
	set lib $::env(LIB_FILE)
} else {
	set lib /foss/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
}
set netlist syn_sta_rv32im_ahb_core/netlist/synthesized/synthesized_netlist.v
set sdc syn_sta_rv32im_ahb_core/constraints/synthesis_constraints.sdc
set rpt_timing syn_sta_rv32im_ahb_core/reports/timing
set rpt_power syn_sta_rv32im_ahb_core/reports/power
set rpt_area syn_sta_rv32im_ahb_core/reports/area

exec mkdir -p $rpt_timing
exec mkdir -p $rpt_power
exec mkdir -p $rpt_area

read_liberty $lib
read_verilog $netlist
link_design $top
read_sdc $sdc

report_checks -path_delay min_max -fields {slew cap input_pins fanout} -format full_clock_expanded > $rpt_timing/report_checks.rpt
report_tns > $rpt_timing/report_tns.rpt
report_wns > $rpt_timing/report_wns.rpt
report_power > $rpt_power/report_power.rpt

# Area reporting command differs across STA builds.
if {[llength [info commands report_design_area]] > 0} {
	report_design_area > $rpt_area/report_area.rpt
} elseif {[llength [info commands report_area]] > 0} {
	report_area > $rpt_area/report_area.rpt
} else {
	set f [open "$rpt_area/report_area.rpt" w]
	puts $f "Area report command not available in this OpenSTA build."
	close $f
}

exit
