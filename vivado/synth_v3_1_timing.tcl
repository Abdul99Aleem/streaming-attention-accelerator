# Synthesis Script for streaming_attention_v3.1 - Timing Verification
# Purpose: Verify that pipelined DSP fix resolves timing violation
# Date: 2026-04-13
# Expected: WNS > +2 ns (timing passes)

#==============================================================================
# Setup
#==============================================================================
set project_dir [file dirname [info script]]
set output_dir "${project_dir}/synth_v3_1_timing_output"

# Create output directory
file mkdir $output_dir

# Set target device
set part "xc7z020clg400-1"

puts "=========================================="
puts "Streaming Attention v3.1 - Timing Verification"
puts "=========================================="
puts "Target: $part"
puts "Clock: 100 MHz (10 ns period)"
puts "Expected: WNS > +2 ns (timing fix verified)"
puts "Output: $output_dir"
puts "=========================================="

#==============================================================================
# Read RTL Sources
#==============================================================================
puts "\n\[INFO\] Reading RTL sources..."

# Read in dependency order
read_verilog "${project_dir}/../rtl/primitives/mac_int8.v"
read_verilog "${project_dir}/../rtl/softmax/softmax_unit_v2.v"
read_verilog "${project_dir}/../rtl/attention/streaming_attention_v3_1.v"

puts "\[INFO\] RTL sources loaded successfully"

#==============================================================================
# Read Timing Constraints
#==============================================================================
puts "\n\[INFO\] Reading timing constraints..."
# Use same constraints as v3 (100 MHz, same I/O delays)
read_xdc "${project_dir}/constraints/streaming_attention_v3.xdc"
puts "\[INFO\] Constraints loaded successfully"

#==============================================================================
# Synthesis
#==============================================================================
puts "\n\[INFO\] Starting synthesis..."
puts "Target: streaming_attention_v3_1"
puts "Part: $part"

synth_design \
    -top streaming_attention_v3_1 \
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

# 3. Utilization Report
puts "  - Resource utilization..."
report_utilization \
    -hierarchical \
    -file "${output_dir}/utilization.rpt"

# 4. Power Report
puts "  - Power estimation..."
report_power \
    -file "${output_dir}/power.rpt"

# 5. DRC
puts "  - Design rule check..."
report_drc \
    -file "${output_dir}/drc.rpt"

#==============================================================================
# Extract Key Metrics
#==============================================================================
puts "\n\[INFO\] Extracting key metrics..."

# Get timing metrics
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set failing_endpoints [get_property ENDPOINT_COUNT [get_timing_paths -setup -slack_lesser_than 0]]

# Create summary file
set summary_file [open "${output_dir}/synthesis_summary.txt" w]
puts $summary_file "=========================================="
puts $summary_file "Synthesis Summary - streaming_attention_v3.1"
puts $summary_file "=========================================="
puts $summary_file "Date: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $summary_file "Target: $part"
puts $summary_file "Clock: 100 MHz (10 ns period)"
puts $summary_file ""
puts $summary_file "TIMING RESULTS:"
puts $summary_file "  Worst Negative Slack (WNS): $wns ns"
puts $summary_file "  Failing Endpoints: $failing_endpoints"
puts $summary_file ""
if {$wns >= 0} {
    puts $summary_file "  Status: ✅ TIMING MET"
    if {$wns >= 2.0} {
        puts $summary_file "  Quality: ✅ EXCELLENT (>2ns margin)"
    } elseif {$wns >= 1.0} {
        puts $summary_file "  Quality: ✅ GOOD (>1ns margin)"
    } else {
        puts $summary_file "  Quality: ⚠️ MARGINAL (<1ns margin)"
    }
} else {
    puts $summary_file "  Status: ❌ TIMING VIOLATION"
}
puts $summary_file ""
puts $summary_file "COMPARISON WITH v3:"
puts $summary_file "  v3 WNS:   -1.342 ns (FAILED)"
puts $summary_file "  v3.1 WNS: $wns ns"
if {$wns >= 0} {
    set improvement [expr {$wns + 1.342}]
    puts $summary_file "  Improvement: +$improvement ns"
}
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
puts "  Failing Endpoints: $failing_endpoints"
if {$wns >= 0} {
    puts "  Status: ✅ TIMING MET"
    if {$wns >= 2.0} {
        puts "  Quality: ✅ EXCELLENT (>2ns margin)"
    } elseif {$wns >= 1.0} {
        puts "  Quality: ✅ GOOD (>1ns margin)"
    } else {
        puts "  Quality: ⚠️ MARGINAL (<1ns margin)"
    }
} else {
    puts "  Status: ❌ TIMING VIOLATION"
}
puts ""
puts "COMPARISON WITH v3:"
puts "  v3 WNS:   -1.342 ns (FAILED)"
puts "  v3.1 WNS: $wns ns"
if {$wns >= 0} {
    set improvement [expr {$wns + 1.342}]
    puts "  Improvement: +$improvement ns"
}
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
