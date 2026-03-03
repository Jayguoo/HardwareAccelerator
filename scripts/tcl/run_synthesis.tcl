# run_synthesis.tcl — Run synthesis and generate utilization report
# Usage: vivado -mode batch -source scripts/tcl/run_synthesis.tcl
#        (run from project root after create_project.tcl)

# Open project
open_project vivado_project/matmul_accelerator.xpr

# Run synthesis
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check for errors
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# Open synthesized design
open_run synth_1

# Generate reports
file mkdir reports
report_utilization -file reports/utilization_synth.rpt
report_timing_summary -file reports/timing_synth.rpt
report_power -file reports/power_synth.rpt

# Check for DSP48E1 inference
puts "\n=== DSP48E1 Utilization ==="
report_utilization -hierarchical -hierarchical_depth 3

# Run implementation
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# Open implemented design
open_run impl_1

# Post-implementation reports
report_utilization -file reports/utilization_impl.rpt
report_timing_summary -file reports/timing_impl.rpt
report_power -file reports/power_impl.rpt

# Check timing
set wns [get_property STATS.WNS [get_runs impl_1]]
puts "\n=== Timing Summary ==="
puts "Worst Negative Slack (WNS): $wns ns"
if {$wns < 0} {
    puts "WARNING: Timing NOT met!"
} else {
    puts "Timing MET at 100 MHz"
}

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "\nSynthesis and implementation complete."
puts "Bitstream: vivado_project/matmul_accelerator.runs/impl_1/matmul_top.bit"
