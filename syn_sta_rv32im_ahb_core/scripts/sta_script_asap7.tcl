set top Pip_RV32IM_AHB

# ============================================================================
# ASAP7 Liberty Files
# ============================================================================

set libs {
	syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
	syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
	syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
	syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
}

set netlist syn_sta_rv32im_ahb_core/netlist/synthesized/asap7_synthesized_netlist.v

set sdc syn_sta_rv32im_ahb_core/constraints/asap7_synth_cons.sdc

set rpt_timing syn_sta_rv32im_ahb_core/reports/timing
set rpt_power  syn_sta_rv32im_ahb_core/reports/power
set rpt_area   syn_sta_rv32im_ahb_core/reports/area

exec mkdir -p $rpt_timing
exec mkdir -p $rpt_power
exec mkdir -p $rpt_area

# ============================================================================
# Read Liberty Files
# ============================================================================

foreach lib $libs {
	read_liberty $lib
}

# ============================================================================
# Read Netlist
# ============================================================================

read_verilog $netlist

link_design $top

read_sdc $sdc

# ============================================================================
# Timing Reports
# ============================================================================

report_checks \
	-path_delay min_max \
	-fields {slew cap input_pins fanout} \
	-format full_clock_expanded \
	> $rpt_timing/asap7_report_checks.rpt

report_tns > $rpt_timing/asap7_report_tns.rpt

report_wns > $rpt_timing/asap7_report_wns.rpt

# ============================================================================
# Power Report
# ============================================================================

report_power > $rpt_power/asap7_report_power.rpt

# ============================================================================
# Area Report
# ============================================================================

if {[llength [info commands report_design_area]] > 0} {

	report_design_area > $rpt_area/asap7_report_area.rpt

} elseif {[llength [info commands report_area]] > 0} {

	report_area > $rpt_area/asap7_report_area.rpt

} else {

	set f [open "$rpt_area/asap7_report_area.rpt" w]
	puts $f "Area report command not available in this OpenSTA build."
	close $f
}

exit