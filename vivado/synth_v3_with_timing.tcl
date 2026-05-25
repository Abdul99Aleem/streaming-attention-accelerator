# Synthesis script for streaming_attention_v3 with timing constraints
# Target: Zynq-7020 (xc7z020clg400-1)

# Set the target part
set_part xc7z020clg400-1

# Read design files
read_verilog ../rtl/softmax/softmax_unit_v2.v
read_verilog ../rtl/attention/streaming_attention_v3.v

# Read timing constraints
read_xdc constraints/streaming_attention_v3.xdc

# Note: Memory initialization files not needed for synthesis
# They are only required for simulation

# Synthesize design
synth_design -top streaming_attention_v3 -part xc7z020clg400-1 -mode out_of_context

# Generate reports
report_utilization -file synth_v3_timing_output/utilization.rpt
report_timing_summary -file synth_v3_timing_output/timing.rpt -max_paths 10 -report_unconstrained
report_power -file synth_v3_timing_output/power.rpt

# Write checkpoint
write_checkpoint -force synth_v3_timing_output/post_synth.dcp

# Write synthesized netlist
write_verilog -force synth_v3_timing_output/streaming_attention_v3_synth.v

puts "Synthesis with timing constraints completed successfully"
