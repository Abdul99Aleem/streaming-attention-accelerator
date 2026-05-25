# Timing Constraints for streaming_attention_v3
# Target: Zynq-7020 (xc7z020clg400-1)
# Clock: 100 MHz (10 ns period)
# Date: 2026-04-13
# Purpose: Constrain design for timing analysis and closure

#==============================================================================
# Primary Clock Constraint
#==============================================================================
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# Clock uncertainty (accounts for jitter and skew)
# Conservative 200 ps = 2% of period
set_clock_uncertainty 0.200 [get_clocks clk]

#==============================================================================
# Input Delay Constraints
#==============================================================================
# Assume external BRAM provides data with 2 ns setup/hold window
# Max delay: data arrives 3 ns after clock edge
# Min delay: data stable 1 ns after clock edge

set_input_delay -clock clk -min 1.000 [get_ports {start q_data k_data v_data scale_shift}]
set_input_delay -clock clk -max 3.000 [get_ports {start q_data k_data v_data scale_shift}]

#==============================================================================
# Output Delay Constraints
#==============================================================================
# Assume external BRAM/logic requires data stable 3 ns after clock
# Leaves 7 ns for internal logic (10 - 3 = 7 ns)

set_output_delay -clock clk -min 1.000 [get_ports {done busy q_addr q_rd_en k_addr k_rd_en v_addr v_rd_en out_addr out_data out_wr_en}]
set_output_delay -clock clk -max 3.000 [get_ports {done busy q_addr q_rd_en k_addr k_rd_en v_addr v_rd_en out_addr out_data out_wr_en}]

#==============================================================================
# False Path Constraints
#==============================================================================
# Asynchronous reset - don't time reset paths
set_false_path -from [get_ports rst_n] -to [all_registers]

#==============================================================================
# Maximum Delay Constraints
#==============================================================================
# Combinational paths through the design
set_max_delay 10.000 -from [all_inputs] -to [all_outputs]

#==============================================================================
# Multi-Cycle Path Constraints
#==============================================================================
# None needed - all operations complete in 1 cycle

#==============================================================================
# Timing Exceptions
#==============================================================================
# None needed currently
