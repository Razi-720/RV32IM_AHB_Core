# ============================================================
# SDC Constraints for Pip_RV32IM_AHB
# Target: ASAP7 RVT Standard Cells
# ============================================================

# ============================================================
# 1. CLOCK DEFINITION
# ============================================================

# Initial target: 1 GHz
create_clock -name clk -period 10 -waveform {0 5.000} [get_ports Clk_In]

# More realistic OpenSTA assumptions for ASAP7
set_clock_uncertainty -setup 0.10 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]

# Relaxed transition for open-source ASAP7 flow
set_clock_transition 0.10 [get_clocks clk]

# ============================================================
# 2. RESET
# ============================================================

# Reset is asynchronous
set_false_path -from [get_ports Rst_In]

# ============================================================
# 3. INPUT DELAYS
# ============================================================

# ------------------------------------------------------------
# Instruction Interface
# ------------------------------------------------------------

set_input_delay -clock clk -max 0.10 [get_ports Instruction_In[*]]
set_input_delay -clock clk -min 0.01 [get_ports Instruction_In[*]]

set_input_delay -clock clk -max 0.10 [get_ports Instr_HReady_In]
set_input_delay -clock clk -min 0.01 [get_ports Instr_HReady_In]

# ------------------------------------------------------------
# Data Interface
# ------------------------------------------------------------

set_input_delay -clock clk -max 0.10 [get_ports DM_Data_In[*]]
set_input_delay -clock clk -min 0.01 [get_ports DM_Data_In[*]]

set_input_delay -clock clk -max 0.10 [get_ports Data_HReady_In]
set_input_delay -clock clk -min 0.01 [get_ports Data_HReady_In]

set_input_delay -clock clk -max 0.10 [get_ports HResp_In]
set_input_delay -clock clk -min 0.01 [get_ports HResp_In]

# NOTE:
# RTC + IRQ inputs are asynchronous.
# Do NOT apply synchronous input delays to them.

# ============================================================
# 4. OUTPUT DELAYS
# ============================================================

set_output_delay -clock clk -max 0.10 [get_ports Instr_Addr_Out[*]]
set_output_delay -clock clk -min 0.01 [get_ports Instr_Addr_Out[*]]

set_output_delay -clock clk -max 0.10 [get_ports DM_Addr_Out[*]]
set_output_delay -clock clk -min 0.01 [get_ports DM_Addr_Out[*]]

set_output_delay -clock clk -max 0.10 [get_ports DM_Data_Out[*]]
set_output_delay -clock clk -min 0.01 [get_ports DM_Data_Out[*]]

set_output_delay -clock clk -max 0.10 [get_ports DM_Mask_Out[*]]
set_output_delay -clock clk -min 0.01 [get_ports DM_Mask_Out[*]]

set_output_delay -clock clk -max 0.10 [get_ports DM_WrEn_Out]
set_output_delay -clock clk -min 0.01 [get_ports DM_WrEn_Out]

set_output_delay -clock clk -max 0.10 [get_ports Data_HTrans_Out[*]]
set_output_delay -clock clk -min 0.01 [get_ports Data_HTrans_Out[*]]

set_output_delay -clock clk -max 0.10 [get_ports Data_HSize_Out[*]]
set_output_delay -clock clk -min 0.01 [get_ports Data_HSize_Out[*]]

# ============================================================
# 5. DRIVING CELL + LOAD
# ============================================================

# Apply drive model only to synchronous data inputs
# Exclude:
#   - Clock
#   - Reset
#   - RTC
#   - Interrupts

set_driving_cell \
    -lib_cell BUFx4_ASAP7_75t_R \
    -pin Y \
    [get_ports {
        Instruction_In[*]
        Instr_HReady_In
        DM_Data_In[*]
        Data_HReady_In
        HResp_In
    }]

# Small output loading
set_load 0.002 [all_outputs]

# ============================================================
# 6. DESIGN RULE CONSTRAINTS
# ============================================================

# Relaxed constraints for open-source ASAP7 flow
set_max_fanout 32 [current_design]

set_max_transition 0.20 [current_design]

set_max_capacitance 0.10 [current_design]

# ============================================================
# 7. FALSE PATHS
# ============================================================

# Async interrupt paths
set_false_path -from [get_ports EIrq_In]

set_false_path -from [get_ports TIrq_In]

set_false_path -from [get_ports SIrq_In]

# RTC is asynchronous
set_false_path -from [get_ports RTC_In[*]]

# ============================================================
# 8. MULTICYCLE PATHS
# ============================================================

# Divider / MDU paths can be relaxed later if needed

# Example:
#
# set_multicycle_path -setup 2 \
#   -from [get_pins MDU_SrcA_r*/Q] \
#   -to   [get_pins reg_e_m/MDU_Result_*/D]
#
# set_multicycle_path -hold 1 \
#   -from [get_pins MDU_SrcA_r*/Q] \
#   -to   [get_pins reg_e_m/MDU_Result_*/D]

# ============================================================
# 9. CLOCK GROUPS
# ============================================================

# Single clock domain only

# ============================================================
# 10. OPTIONAL CLOCK PROTECTION
# ============================================================

# set_dont_touch_network [get_ports Clk_In]
