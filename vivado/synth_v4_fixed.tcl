# Synthesis Script for Streaming Attention Accelerator v4 (Fixed)
# Target: Zynq-7020 (xc7z020clg400-1)

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

# Run synthesis
puts "\n=========================================="
puts "Running Synthesis..."
puts "=========================================="
launch_runs synth_1
wait_on_run synth_1

# Check if synthesis succeeded
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis did not complete successfully"
    exit 1
}

# Open synthesized design
puts "\n=========================================="
puts "Opening Synthesized Design..."
puts "=========================================="
open_run synth_1

# Now create timing constraints (after design is open)
create_clock -period 10.000 -name clk [get_ports clk]
set_input_delay -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]

# Generate reports
puts "\n=========================================="
puts "Generating Reports..."
puts "=========================================="
report_utilization -file ./synth_output/utilization.rpt
report_timing_summary -file ./synth_output/timing.rpt
report_power -file ./synth_output/power.rpt
report_drc -file ./synth_output/drc.rpt
report_utilization -hierarchical -file ./synth_output/utilization_hierarchical.rpt

# Check timing
set slack [get_property SLACK [get_timing_paths -max_paths 1]]
puts "\n=========================================="
puts "Synthesis Summary"
puts "=========================================="
puts "Design: streaming_attention_v4"
puts "Target: xc7z020clg400-1"
puts "Clock: 100 MHz (10 ns period)"

if {$slack < 0} {
    puts "Timing: FAILED (slack: $slack ns)"
} else {
    puts "Timing: MET (slack: $slack ns)"
}

# Print resource summary
set util [report_utilization -return_string]
puts "\n$util"

puts "=========================================="
puts "Reports saved to ./synth_output/"
puts "=========================================="

# Close project
close_project
