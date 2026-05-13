# ============================================================
# SDC Constraints for Pip_RV32IM_AHB
# RV32IM 5-Stage Pipelined Core with AHB-Lite Interface
# Target: SKY130 HD Standard Cells
# ============================================================

# ────────────────────────────────────────────────────────────
# 1. CLOCK DEFINITION
# ────────────────────────────────────────────────────────────
# Primary system clock — aggressive target for high-frequency optimization
# Adjust period based on timing reports:
#   - If setup violations: increase period
#   - If timing met with large positive slack: decrease period
create_clock -name clk -period 10.0 -waveform {0 5.0} [get_ports Clk_In]

# Clock uncertainty (jitter + skew estimate for pre-CTS)
set_clock_uncertainty -setup 0.2 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]

# Clock transition (slew) constraint
set_clock_transition 0.08 [get_clocks clk]

# ────────────────────────────────────────────────────────────
# 2. RESET — ASYNCHRONOUS FALSE PATH
# ────────────────────────────────────────────────────────────
# Reset is asynchronous — exclude from timing analysis
set_false_path -from [get_ports Rst_In]

# ────────────────────────────────────────────────────────────
# 3. INPUT DELAYS
# ────────────────────────────────────────────────────────────
# General rule: input_delay ≈ 20–40% of clock period
# Adjust based on upstream module timing

# --- Instruction Memory Interface (AHB-Lite) ---
set_input_delay -clock clk -max 0.5 [get_ports Instruction_In[*]]
set_input_delay -clock clk -min 0.0 [get_ports Instruction_In[*]]

set_input_delay -clock clk -max 0.5 [get_ports Instr_HReady_In]
set_input_delay -clock clk -min 0.0 [get_ports Instr_HReady_In]

# --- Data Memory Interface (AHB-Lite) ---
set_input_delay -clock clk -max 0.5 [get_ports DM_Data_In[*]]
set_input_delay -clock clk -min 0.0 [get_ports DM_Data_In[*]]

set_input_delay -clock clk -max 0.5 [get_ports Data_HReady_In]
set_input_delay -clock clk -min 0.0 [get_ports Data_HReady_In]

set_input_delay -clock clk -max 0.5 [get_ports HResp_In]
set_input_delay -clock clk -min 0.0 [get_ports HResp_In]

# --- Interrupt Inputs ---
# Interrupts are asynchronous by nature but synchronized internally.
# Constrain loosely — they are sampled by Machine_Control.
set_input_delay -clock clk -max 6.0 [get_ports EIrq_In]
set_input_delay -clock clk -min 0.5 [get_ports EIrq_In]

set_input_delay -clock clk -max 6.0 [get_ports TIrq_In]
set_input_delay -clock clk -min 0.5 [get_ports TIrq_In]

set_input_delay -clock clk -max 6.0 [get_ports SIrq_In]
set_input_delay -clock clk -min 0.5 [get_ports SIrq_In]

# --- Real-Time Counter (64-bit) ---
# RTC is a free-running counter from external domain.
# If truly asynchronous, use set_false_path instead.
# For now, constrain loosely assuming synchronous sampling.
set_input_delay -clock clk -max 5.0 [get_ports RTC_In[*]]
set_input_delay -clock clk -min 1.0 [get_ports RTC_In[*]]

# ────────────────────────────────────────────────────────────
# 4. OUTPUT DELAYS
# ────────────────────────────────────────────────────────────
# General rule: output_delay ≈ 20–40% of clock period
# Represents setup requirement of downstream AHB slave

# --- Instruction Address (AHB-Lite) ---
set_output_delay -clock clk -max 0.5 [get_ports Instr_Addr_Out[*]]
set_output_delay -clock clk -min 0.0 [get_ports Instr_Addr_Out[*]]

# --- Data Memory Interface (AHB-Lite) ---
set_output_delay -clock clk -max 0.5 [get_ports DM_Addr_Out[*]]
set_output_delay -clock clk -min 0.0 [get_ports DM_Addr_Out[*]]

set_output_delay -clock clk -max 0.5 [get_ports DM_Data_Out[*]]
set_output_delay -clock clk -min 0.0 [get_ports DM_Data_Out[*]]

set_output_delay -clock clk -max 0.5 [get_ports DM_Mask_Out[*]]
set_output_delay -clock clk -min 0.0 [get_ports DM_Mask_Out[*]]

set_output_delay -clock clk -max 0.5 [get_ports DM_WrEn_Out]
set_output_delay -clock clk -min 0.0 [get_ports DM_WrEn_Out]

# --- AHB Control Outputs ---
set_output_delay -clock clk -max 0.5 [get_ports Data_HTrans_Out[*]]
set_output_delay -clock clk -min 0.0 [get_ports Data_HTrans_Out[*]]

set_output_delay -clock clk -max 0.5 [get_ports Data_HSize_Out[*]]
set_output_delay -clock clk -min 0.0 [get_ports Data_HSize_Out[*]]

# ────────────────────────────────────────────────────────────
# 5. DRIVING CELL & OUTPUT LOAD
# ────────────────────────────────────────────────────────────
# Model what drives the inputs (upstream buffer strength)
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_8 -pin X [all_inputs]

# Model capacitive load on outputs (downstream gate input cap)
# ~50 fF typical for moderate fanout
set_load -pin_load 0.02 [all_outputs]

# ────────────────────────────────────────────────────────────
# 6. MAX FANOUT
# ────────────────────────────────────────────────────────────
set_max_fanout 8 [current_design]

# ────────────────────────────────────────────────────────────
# 7. MAX TRANSITION (SLEW)
# ────────────────────────────────────────────────────────────
# Prevent slow transitions that cause short-circuit power
set_max_transition 0.5 [current_design]

# ────────────────────────────────────────────────────────────
# 8. MAX CAPACITANCE
# ────────────────────────────────────────────────────────────
set_max_capacitance 0.2 [current_design]

# ────────────────────────────────────────────────────────────
# 9. FALSE PATHS & MULTICYCLE PATHS
# ────────────────────────────────────────────────────────────

# --- RTC is asynchronous (if from different clock domain) ---
# Uncomment if RTC_In is truly from a separate clock domain:
# set_false_path -from [get_ports RTC_In[*]]

# --- Interrupt inputs (asynchronous, synchronized internally) ---
# If interrupts have no internal synchronizer, add false paths:
# set_false_path -from [get_ports EIrq_In]
# set_false_path -from [get_ports TIrq_In]
# set_false_path -from [get_ports SIrq_In]

# --- MDU Multicycle Path ---
# The divider (Div32_NonRestoring) takes multiple cycles.
# MDU_Started_r / MDU_Ready handshake manages the stall.
# The datapath from MDU_SrcA_r/MDU_SrcB_r → MDU_Result is
# multicycle by design (pipeline is stalled via MDU_Stall).
#
# If critical path goes through divider, allow extra cycles:
# Typical non-restoring divider: 32+2 cycles for 32-bit
# But since pipeline stalls, we mark it as multicycle:

# NOTE:
# The pin patterns below are design-name dependent and may not survive
# synthesis/flattening, which causes OpenSTA warnings if left enabled.
# Re-enable only after confirming exact pin names in the synthesized netlist.
# set_multicycle_path -setup 2 -from [get_pins MDU_SrcA_r*/Q] \
#                              -to   [get_pins reg_e_m/MDU_Result_*/D]
# set_multicycle_path -hold  1 -from [get_pins MDU_SrcA_r*/Q] \
#                              -to   [get_pins reg_e_m/MDU_Result_*/D]
#
# set_multicycle_path -setup 2 -from [get_pins MDU_SrcB_r*/Q] \
#                              -to   [get_pins reg_e_m/MDU_Result_*/D]
# set_multicycle_path -hold  1 -from [get_pins MDU_SrcB_r*/Q] \
#                              -to   [get_pins reg_e_m/MDU_Result_*/D]

# ────────────────────────────────────────────────────────────
# 10. CLOCK GROUPS (if applicable)
# ────────────────────────────────────────────────────────────
# Only one clock domain (Clk_In) — no clock groups needed.
# If RTC has its own clock, add:
# create_clock -name rtc_clk -period 30.0 [get_ports RTC_Clk_In]
# set_clock_groups -asynchronous \
#   -group [get_clocks clk] \
#   -group [get_clocks rtc_clk]

# ────────────────────────────────────────────────────────────
# 11. DESIGN RULE CONSTRAINTS
# ────────────────────────────────────────────────────────────
# Don't allow the tool to resize clock buffers during optimization
# (CTS will handle clock tree separately)
# set_dont_touch [get_nets Clk_In] ;# optional, tool-specific

# ────────────────────────────────────────────────────────────
# 12. OPERATING CONDITIONS (optional, library-dependent)
# ────────────────────────────────────────────────────────────
# set_operating_conditions -max tt_025C_1v80 -min tt_025C_1v80