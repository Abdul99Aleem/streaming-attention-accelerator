# Synthesis Script for Streaming Attention Accelerator
# Target: Zynq-7020 (xc7z020clg400-1)
# Purpose: Synthesize v4 design and generate resource reports

# Create project
create_project streaming_attention_synth ./synth_output -part xc7z020clg400-1 -force

# Add source files
add_files {
    ../rtl/primitives/mac_int8.v
    ../rtl/softmax/softmax_unit_v2.v
    ../rtl/attention/streaming_attention_v4.v
}

# Add memory files
add_files -fileset constrs_1 ../mem/exp_lut.hex

# Set top module
set_property top streaming_attention_v4 [current_fileset]

# Set synthesis options
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE PerformanceOptimized [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Create timing constraints
create_clock -period 10.000 -name clk [get_ports clk]
set_input_delay -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]

# Run synthesis
launch_runs synth_1
wait_on_run synth_1

# Open synthesized design
open_run synth_1

# Generate reports
report_utilization -file ./synth_output/utilization.rpt
report_timing_summary -file ./synth_output/timing.rpt
report_power -file ./synth_output/power.rpt
report_drc -file ./synth_output/drc.rpt

# Generate detailed resource breakdown
report_utilization -hierarchical -file ./synth_output/utilization_hierarchical.rpt

# Check timing
set slack [get_property SLACK [get_timing_paths]]
if {$slack < 0} {
    puts "ERROR: Timing not met. Slack: $slack ns"
} else {
    puts "SUCCESS: Timing met. Slack: $slack ns"
}

# Print summary
puts "\n=========================================="
puts "Synthesis Summary"
puts "=========================================="
puts "Design: streaming_attention_v4"
puts "Target: xc7z020clg400-1"
puts "Clock: 100 MHz (10 ns period)"
puts "=========================================="

# Close project
close_project
