# ==============================================================================
# Makefile - Verilator Lint + Simulation for RV32I Pipeline CPU
# ==============================================================================

# Top module (RTL)
TOPLEVEL := Pip_RV32IM_AHB

# Testbench top module (must match module name inside the TB file)
MODULE := tb_Pip_RV32IM_AHB

# RTL directories
RTL_BASE  := $(shell pwd)/rtl_rv32im_ahb_core
TB_BASE   := $(shell pwd)/tb_rv32im_ahb_core
SIM_DIRS  := $(shell pwd)/sim_rv32im_ahb_core
WAVE_DIR  := $(shell pwd)/waves
RTL_INCLUDE_DIR := $(shell pwd)/include

RTL_DIRS := \
	$(RTL_BASE)/top \
	$(RTL_BASE)/pipeline_registers \
	$(RTL_BASE)/control \
	$(RTL_BASE)/datapath_units \
	$(RTL_BASE)/csr \
	$(RTL_BASE)/memory_if \
	$(RTL_BASE)/multiply \
	$(RTL_BASE)/hazards

# Collect all RTL Verilog files
VERILOG_SOURCES := $(shell find $(RTL_DIRS) -name "*.v")

# Testbench source file
TB_SOURCES := $(TB_BASE)/$(MODULE).v

# Include directories
INCLUDE_DIRS := $(addprefix -I,$(RTL_DIRS) $(RTL_INCLUDE_DIR))

# Synthesis/STA directories
SYN_BASE := $(shell pwd)/syn_sta_rv32im_ahb_core
SYN_SCRIPT := $(SYN_BASE)/scripts/yosys_script.ys
STA_SCRIPT := $(SYN_BASE)/scripts/sta_script.tcl

# Library flavor for synthesis/STA: hd (default) or hs
LIB_FLAVOR ?= hd

HD_LIB_FILE := $(firstword \
	$(wildcard /foss/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib) \
	$(wildcard /foss/pdks/sky130A/libs.ref/sky130_fd_sc_hd/timing/sky130_fd_sc_hd__tt_025C_1v80.lib))

HS_LIB_FILE := $(firstword \
	$(wildcard /foss/pdks/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib) \
	$(wildcard /foss/pdks/sky130A/libs.ref/sky130_fd_sc_hs/timing/sky130_fd_sc_hs__tt_025C_1v80.lib))

ifeq ($(LIB_FLAVOR),hs)
LIB_FILE := $(HS_LIB_FILE)
else
LIB_FILE := $(HD_LIB_FILE)
endif

# ==============================================================================
# ASAP7 Synthesis / STA Configuration
# ==============================================================================

ASAP7_LIB_DIR := $(SYN_BASE)/lib

# Typical Corner
ASAP7_LIBS := \
	$(ASAP7_LIB_DIR)/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
	$(ASAP7_LIB_DIR)/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib \
	$(ASAP7_LIB_DIR)/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
	$(ASAP7_LIB_DIR)/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib

ASAP7_SYN_SCRIPT := $(SYN_BASE)/scripts/yosys_script_asap7.ys
ASAP7_STA_SCRIPT := $(SYN_BASE)/scripts/sta_script_asap7.tcl

# Shared Verilator warning flags
VERILATOR_WARN := \
	--Wall \
	-Wno-DECLFILENAME \
	-Wno-UNUSED \
	-Wno-WIDTH

# ==============================================================================
# Lint (RTL only, no TB)
# ==============================================================================
.PHONY: lint
lint:
	@echo "Running Verilator Lint..."
	verilator --lint-only \
		$(VERILATOR_WARN) \
		--top-module $(TOPLEVEL) \
		$(INCLUDE_DIRS) \
		$(VERILOG_SOURCES)

# ==============================================================================
# Run — Verilator binary simulation
# TB top module is $(MODULE); waveform saved to waves/$(MODULE).vcd
# ==============================================================================
.PHONY: run
run:
	@mkdir -p $(SIM_DIRS) $(WAVE_DIR)
	@echo "Compiling with Verilator..."
	verilator --binary --trace \
		$(VERILATOR_WARN) \
		--top-module $(MODULE) \
		-Mdir $(SIM_DIRS) \
		$(INCLUDE_DIRS) \
		$(TB_SOURCES) $(VERILOG_SOURCES)
	@echo "Running simulation..."
	$(SIM_DIRS)/V$(MODULE)
	@if [ -f dump.vcd ]; then mv dump.vcd $(WAVE_DIR)/$(MODULE).vcd; fi
	@if [ -f $(MODULE).vcd ]; then mv $(MODULE).vcd $(WAVE_DIR)/$(MODULE).vcd; fi
	@echo "Waveform: $(WAVE_DIR)/$(MODULE).vcd"

# ==============================================================================
# Open waveform in GTKWave
# ==============================================================================
.PHONY: wave
wave:
	gtkwave $(WAVE_DIR)/$(MODULE).vcd &

# ==============================================================================
# Show collected files (debug)
# ==============================================================================
.PHONY: files
files:
	@echo "RTL directories:"
	@for dir in $(RTL_DIRS); do echo $$dir; done
	@echo ""
	@echo "Verilog files:"
	@for file in $(VERILOG_SOURCES); do echo $$file; done
	@echo ""
	@echo "Testbench: $(TB_SOURCES)"

# ==============================================================================
# Save lint output to file
# ==============================================================================
.PHONY: lint-log
lint-log:
	@mkdir -p logs
	verilator --lint-only \
		$(VERILATOR_WARN) \
		--top-module $(TOPLEVEL) \
		$(INCLUDE_DIRS) \
		$(VERILOG_SOURCES) \
		2>&1 | tee logs/verilator_lint.log

# ==============================================================================
# Clean
# ==============================================================================
.PHONY: clean
clean:
	rm -rf $(SIM_DIRS) $(WAVE_DIR) logs obj_dir verilator.log

.PHONY: synth
synth: 
	@mkdir -p $(SYN_BASE)/netlist/synthesized $(SYN_BASE)/reports/synthesis
	@if [ -z "$(LIB_FILE)" ]; then \
		echo "Error: could not find liberty file for LIB_FLAVOR=$(LIB_FLAVOR)."; \
		echo "Checked HD and HS lib/timing paths under /foss/pdks/sky130A/libs.ref/."; \
		exit 1; \
	fi
	@echo "Running Yosys synthesis (LIB_FLAVOR=$(LIB_FLAVOR))..."
	@tmp_ys=$$(mktemp); \
	sed "s|/foss/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib|$(LIB_FILE)|g" $(SYN_SCRIPT) > $$tmp_ys; \
	yosys -s $$tmp_ys | tee $(SYN_BASE)/reports/synthesis/yosys.log; \
	rm -f $$tmp_ys

.PHONY: sta
sta:
	@mkdir -p $(SYN_BASE)/reports/timing $(SYN_BASE)/reports/power $(SYN_BASE)/reports/area
	@if [ -z "$(LIB_FILE)" ]; then \
		echo "Error: could not find liberty file for LIB_FLAVOR=$(LIB_FLAVOR)."; \
		exit 1; \
	fi
	@echo "Running OpenSTA (LIB_FLAVOR=$(LIB_FLAVOR))..."
	@LIB_FILE="$(LIB_FILE)" sta $(STA_SCRIPT)

.PHONY: flow
flow: synth sta
	@echo "Synthesis + STA flow complete. Check reports under $(SYN_BASE)/reports"

.PHONY: fmax
fmax:
	@echo "Sweeping clock period for max passing frequency..."
	@bash syn_sta_rv32im_ahb_core/scripts/fmax_sweep.sh

.PHONY: fmax_hs
fmax_hs:
	@echo "Sweeping clock period with HS library..."
	@LIB_FLAVOR=hs bash syn_sta_rv32im_ahb_core/scripts/fmax_sweep.sh

# ==============================================================================
# ASAP7 Synthesis
# ==============================================================================
.PHONY: synth_asap7
synth_asap7:
	@mkdir -p $(SYN_BASE)/netlist/synthesized
	@mkdir -p $(SYN_BASE)/reports/synthesis

	@echo "=========================================================="
	@echo "Running ASAP7 Yosys Synthesis"
	@echo "=========================================================="

	yosys -s syn_sta_rv32im_ahb_core/scripts/yosys_script_asap7.ys \
	| tee syn_sta_rv32im_ahb_core/reports/synthesis/asap7_yosys.log

# ==============================================================================
# ASAP7 STA
# ==============================================================================
.PHONY: sta_asap7
sta_asap7:
	@mkdir -p $(SYN_BASE)/reports/timing
	@mkdir -p $(SYN_BASE)/reports/power
	@mkdir -p $(SYN_BASE)/reports/area

	@echo "=========================================================="
	@echo "Running ASAP7 OpenSTA"
	@echo "=========================================================="

	@LIB_FILES="$(ASAP7_LIBS)" sta $(ASAP7_STA_SCRIPT) \
		| tee $(SYN_BASE)/reports/timing/opensta_asap7.log

# ==============================================================================
# Complete ASAP7 Flow
# ==============================================================================
.PHONY: flow_asap7
flow_asap7: synth_asap7 sta_asap7
	@echo "=========================================================="
	@echo "ASAP7 Synthesis + STA Complete"
	@echo "Reports:"
	@echo "  $(SYN_BASE)/reports/"
	@echo "=========================================================="

.PHONY: fmax_asap7
fmax_asap7:
	@echo "=========================================================="
	@echo "Running ASAP7 Fmax Sweep"
	@echo "=========================================================="
	@bash syn_sta_rv32im_ahb_core/scripts/fmax_sweep_asap7.sh

.PHONY: all
all: 
	@echo "Running all targets..."
	@echo "--------------------------------------------------------------"
	@echo "Cleaning previous builds..."
	@echo "--------------------------------------------------------------"
	@make clean
	@echo "--------------------------------------------------------------"
	@echo "Running lint..."
	@echo "--------------------------------------------------------------"

	@make lint-log
	@echo "--------------------------------------------------------------"
	@echo "Running simulation..."
	@echo "--------------------------------------------------------------"
	@make run | tee logs/simulation.log
	@echo "--------------------------------------------------------------"
	@echo "Running synthesis + STA flow..."
	@echo "--------------------------------------------------------------"
	@make flow
