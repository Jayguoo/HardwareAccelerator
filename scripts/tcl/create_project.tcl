# create_project.tcl — Create Vivado project for Matrix Multiply Accelerator
# Usage: vivado -mode batch -source scripts/tcl/create_project.tcl

set project_name "matmul_accelerator"
set project_dir  "./vivado_project"
set part         "xc7a35ticsg324-1L"

# Create project
create_project $project_name $project_dir -part $part -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Add RTL sources
add_files -norecurse [glob rtl/pkg/*.sv rtl/*.sv]
set_property file_type SystemVerilog [get_files *.sv]

# Add constraints
add_files -fileset constrs_1 -norecurse [glob constraints/*.xdc]

# Add testbench sources to simulation fileset
add_files -fileset sim_1 -norecurse [glob tb/*.sv]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]

# Set top modules
set_property top matmul_top [current_fileset]
set_property top tb_matmul_top [get_filesets sim_1]

# Set simulation runtime
set_property -name {xsim.simulate.runtime} -value {100us} -objects [get_filesets sim_1]

# Set synthesis strategy
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

puts "Project '$project_name' created successfully."
puts "Part: $part"
puts "Run 'launch_runs synth_1' to synthesize."
