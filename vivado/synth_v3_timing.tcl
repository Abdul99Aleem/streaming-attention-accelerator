# Synthesis Script for streaming_attention_v3 with Timing Analysis
# Purpose: Measure actual timing performance and compare with predictions
# Date: 2026-04-13
# Target: Zynq-7020 (xc7z020clg400-1) @ 100 MHz

#==============================================================================
# Setup
#==============================================================================
set project_dir [file dirname [info script]]
set output_dir "${project_dir}/synth_v3_timing_output"

# Create output directory
file mkdir $output_dir

# Set target device
set part "xc7z020clg400-1"

puts "=========================================="
puts "Streaming Attention v3 - Timing Analysis"
puts "=========================================="
puts "Target: $part"
puts "Clock: 100 MHz (10 ns period)"
puts "Output: $output_dir"
puts "=========================================="

#==============================================================================
# Read RTL Sources
#==============================================================================
puts "\n\[INFO\] Reading RTL sources..."

# Read in dependency order
read_verilog "${project_dir}/../rtl/primitives/mac_int8.v"
read_verilog "${project_dir}/../rtl/softmax/softmax_unit_v2.v"
read_verilog "${project_dir}/../rtl/attention/streaming_attention_v3.v"

puts "\[INFO\] RTL sources loaded successfully"

#==============================================================================
# Read Timing Constraints
#==============================================================================
puts "\n\[INFO\] Reading timing constraints..."
read_xdc "${project_dir}/constraints/streaming_attention_v3.xdc"
puts "\[INFO\] Constraints loaded successfully"

#==============================================================================
# Synthesis
#==============================================================================
puts "\n\[INFO\] Starting synthesis..."
puts "Target: streaming_attention_v3"
puts "Part: $part"

synth_design \
    -top streaming_attention_v3 \
    -part $part \
    -mode out_of_context \
    -flatten_hierarchy rebuilt \
    -keep_equivalent_registers \
    -resource_sharing off \
    -no_lc \
    -shreg_min_size 5

puts "\[INFO\] Synthesis completed"

#==============================================================================
# Generate Reports
#==============================================================================
puts "\n\[INFO\] Generating reports..."

# 1. Timing Summary Report
puts "  - Timing summary..."
report_timing_summary \
    -delay_type max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -routable_nets \
    -file "${output_dir}/timing_summary.rpt"

# 2. Critical Paths Report (top 20 paths)
puts "  - Critical paths..."
report_timing \
    -max_paths 20 \
    -nworst 1 \
    -delay_type max \
    -sort_by slack \
    -path_type full \
    -input_pins \
    -routable_nets \
    -file "${output_dir}/critical_paths.rpt"

# 3. Clock Report
puts "  - Clock analysis..."
report_clocks \
    -file "${output_dir}/clocks.rpt"

# 4. Clock Interaction Report
puts "  - Clock interaction..."
report_clock_interaction \
    -delay_type min_max \
    -file "${output_dir}/clock_interaction.rpt"

# 5. Utilization Report
puts "  - Resource utilization..."
report_utilization \
    -hierarchical \
    -file "${output_dir}/utilization.rpt"

# 6. Utilization by Hierarchy
puts "  - Hierarchical utilization..."
report_utilization \
    -hierarchical \
    -hierarchical_depth 3 \
    -file "${output_dir}/utilization_hierarchical.rpt"

# 7. Power Report
puts "  - Power estimation..."
report_power \
    -file "${output_dir}/power.rpt"

# 8. DRC (Design Rule Check)
puts "  - Design rule check..."
report_drc \
    -file "${output_dir}/drc.rpt"

# 9. Methodology Check
puts "  - Methodology check..."
report_methodology \
    -file "${output_dir}/methodology.rpt"

# 10. Datasheet Report
puts "  - Datasheet timing..."
report_datasheet \
    -file "${output_dir}/datasheet.rpt"

# 11. High Fanout Nets
puts "  - High fanout nets..."
report_high_fanout_nets \
    -timing \
    -load_types \
    -max_nets 50 \
    -file "${output_dir}/high_fanout_nets.rpt"

# 12. Control Sets
puts "  - Control sets..."
report_control_sets \
    -verbose \
    -file "${output_dir}/control_sets.rpt"

# 13. Clock Networks
puts "  - Clock networks..."
report_clock_networks \
    -file "${output_dir}/clock_networks.rpt"

#==============================================================================
# Extract Key Metrics
#==============================================================================
puts "\n\[INFO\] Extracting key metrics..."

# Get timing metrics
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set tns [get_property SLACK [get_timing_paths -nworst 1 -max_paths 1 -setup -unique_pins]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]

# Get utilization metrics
set luts [get_property LUT_AS_LOGIC [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ LUT*}]]
set ffs [get_property REGISTER [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ REGISTER*}]]
set dsps [llength [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ DSP*}]]
set brams [llength [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BRAM*}]]

# Create summary file
set summary_file [open "${output_dir}/synthesis_summary.txt" w]
puts $summary_file "=========================================="
puts $summary_file "Synthesis Summary - streaming_attention_v3"
puts $summary_file "=========================================="
puts $summary_file "Date: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $summary_file "Target: $part"
puts $summary_file "Clock: 100 MHz (10 ns period)"
puts $summary_file ""
puts $summary_file "TIMING RESULTS:"
puts $summary_file "  Worst Negative Slack (WNS): $wns ns"
puts $summary_file "  Total Negative Slack (TNS): $tns ns"
puts $summary_file "  Worst Hold Slack (WHS):     $whs ns"
puts $summary_file ""
if {$wns >= 0} {
    puts $summary_file "  Status: ✅ TIMING MET"
} else {
    puts $summary_file "  Status: ❌ TIMING VIOLATION"
}
puts $summary_file ""
puts $summary_file "RESOURCE UTILIZATION:"
puts $summary_file "  LUTs:  $luts"
puts $summary_file "  FFs:   $ffs"
puts $summary_file "  DSPs:  $dsps"
puts $summary_file "  BRAMs: $brams"
puts $summary_file ""
puts $summary_file "=========================================="
close $summary_file

#==============================================================================
# Console Summary
#==============================================================================
puts "\n=========================================="
puts "SYNTHESIS COMPLETE"
puts "=========================================="
puts "TIMING RESULTS:"
puts "  WNS: $wns ns"
puts "  TNS: $tns ns"
puts "  WHS: $whs ns"
if {$wns >= 0} {
    puts "  Status: ✅ TIMING MET"
} else {
    puts "  Status: ❌ TIMING VIOLATION"
}
puts ""
puts "RESOURCE UTILIZATION:"
puts "  LUTs:  $luts"
puts "  FFs:   $ffs"
puts "  DSPs:  $dsps"
puts "  BRAMs: $brams"
puts ""
puts "Reports saved to: $output_dir"
puts "=========================================="

#==============================================================================
# Save Design Checkpoint
#==============================================================================
puts "\n\[INFO\] Saving design checkpoint..."
write_checkpoint -force "${output_dir}/post_synth.dcp"
puts "\[INFO\] Checkpoint saved: ${output_dir}/post_synth.dcp"

puts "\n\[INFO\] Synthesis script completed successfully"
puts "=========================================="
