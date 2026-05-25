# Post-Synthesis Simulation Script for streaming_attention_v3
# Compares synthesized netlist behavior with RTL behavior

# Create work library
vlib work

# Compile Xilinx simulation libraries (primitives needed for synthesized netlist)
vlog /home/aleem/Vivado/2024.2/data/verilog/src/glbl.v

# Compile the synthesized netlist
vlog ../vivado/synth_v3_timing_output/streaming_attention_v3_synth.v

# Compile the testbench
vlog tb_streaming_attention.v

# Simulate with glbl module for Xilinx primitives
vsim -t 1ps -L unisims_ver work.tb_streaming_attention work.glbl

# Run simulation
run -all

# Exit
quit -f
