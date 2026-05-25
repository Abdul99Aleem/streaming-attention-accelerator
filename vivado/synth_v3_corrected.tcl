# Synthesis Script for Streaming Attention v3 (Corrected)
# Target: Zynq-7020 (xc7z020clg400-1)
# Purpose: Analyze resource utilization and timing after synthesis fixes
# Note: Only includes files actually used by v3

# Create project
create_project streaming_attention_v3_synth ./synth_v3_output -part xc7z020clg400-1 -force

# Add ONLY the source files that v3 actually uses
# v3 does NOT use mac_int8 or dot_product_engine
# v3 only uses softmax_unit_v2
add_files {
    ../rtl/softmax/softmax_unit_v2.v
    ../rtl/attention/streaming_attention_v3.v
}

# Set top module
set_property top streaming_attention_v3 [current_fileset]

# Create synthesis run
synth_design -top streaming_attention_v3 -part xc7z020clg400-1 \
    -directive PerformanceOptimized \
    -fsm_extraction one_hot \
    -keep_equivalent_registers \
    -resource_sharing off \
    -no_lc \
    -shreg_min_size 5

# Generate reports
report_utilization -file synth_v3_output/utilization.rpt
report_timing_summary -file synth_v3_output/timing.rpt
report_power -file synth_v3_output/power.rpt

# Write checkpoint
write_checkpoint -force synth_v3_output/post_synth.dcp

# Print summary to console
puts "\n=========================================="
puts "Synthesis Complete - streaming_attention_v3"
puts "=========================================="
puts "\nResource Utilization:"
report_utilization

puts "\nTiming Summary:"
report_timing_summary -max_paths 10

puts "\n=========================================="
puts "Reports saved to synth_v3_output/"
puts "=========================================="

exit
