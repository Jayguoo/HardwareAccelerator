# run_simulation.tcl — Run simulation in Vivado
# Usage: vivado -mode batch -source scripts/tcl/run_simulation.tcl

# Open project
open_project vivado_project/matmul_accelerator.xpr

# Set simulation top
set_property top tb_matmul_top [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {100us} -objects [get_filesets sim_1]

# Launch simulation
launch_simulation

# Run
run all

# Close
close_sim

puts "Simulation complete. Check transcript for PASS/FAIL."
