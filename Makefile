# ==============================================================================
# Makefile - Verilator Lint + Simulation for RV32I Pipeline CPU
# ==============================================================================

# Top module (RTL)
TOPLEVEL := Pip_RV32I

# Testbench top module (must match module name inside the TB file)
MODULE := tb_Pip_RV32I

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
