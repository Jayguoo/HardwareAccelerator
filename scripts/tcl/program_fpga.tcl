# program_fpga.tcl — Program Arty A7-35T with bitstream
# Usage: vivado -mode batch -source scripts/tcl/program_fpga.tcl

set bitstream "vivado_project/matmul_accelerator.runs/impl_1/matmul_top.bit"

# Open hardware manager
open_hw_manager
connect_hw_server -allow_non_jtag

# Auto-detect target
open_hw_target

# Get device
set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Set bitstream
set_property PROGRAM.FILE $bitstream $device

# Program
program_hw_devices $device

puts "FPGA programmed successfully with $bitstream"

# Close
close_hw_target
disconnect_hw_server
close_hw_manager
