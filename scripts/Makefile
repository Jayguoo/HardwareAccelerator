# Makefile — Matrix Multiply Accelerator Build & Verification
#
# Targets:
#   gen_vectors   — Generate test vectors with Python
#   sim_mac       — Simulate MAC unit testbench
#   sim_pe        — Simulate Processing Element testbench
#   sim_array     — Simulate Systolic Array testbench
#   sim_core      — Simulate Core testbench
#   sim_top       — Simulate Full System testbench
#   verify        — Run Python verification (after sim_top)
#   clean         — Remove generated files

# Directories
RTL_DIR    := ../rtl
TB_DIR     := ../tb
SIM_DIR    := ../sim
TEST_DATA  := ../sim/test_data
PKG_DIR    := ../rtl/pkg
PYTHON_DIR := python

# Vivado xvlog/xelab/xsim (if using Vivado simulator)
XVLOG  := xvlog
XELAB  := xelab
XSIM   := xsim

# Common RTL files
PKG_FILES := $(PKG_DIR)/matmul_pkg.sv
RTL_MAC   := $(RTL_DIR)/mac_unit.sv
RTL_PE    := $(RTL_DIR)/processing_element.sv $(RTL_MAC)
RTL_ARRAY := $(RTL_DIR)/systolic_array.sv $(RTL_PE)
RTL_BRAM  := $(RTL_DIR)/bram_matrix.sv
RTL_FSM   := $(RTL_DIR)/matmul_control_fsm.sv
RTL_CORE  := $(RTL_DIR)/matmul_core.sv $(RTL_ARRAY) $(RTL_BRAM) $(RTL_FSM)
RTL_AXI   := $(RTL_DIR)/axi_lite_slave.sv
RTL_TOP   := $(RTL_DIR)/matmul_top.sv $(RTL_CORE) $(RTL_AXI)

.PHONY: all gen_vectors sim_mac sim_pe sim_array sim_core sim_top verify clean

all: gen_vectors sim_top verify

# Generate test vectors
gen_vectors:
	@echo "=== Generating test vectors ==="
	python $(PYTHON_DIR)/matmul_reference.py --dim 4 --num-tests 5

# Simulate MAC unit
sim_mac:
	@echo "=== Simulating MAC Unit ==="
	$(XVLOG) --sv $(RTL_MAC) $(TB_DIR)/tb_mac_unit.sv
	$(XELAB) tb_mac_unit -s mac_sim
	$(XSIM) mac_sim -R

# Simulate Processing Element
sim_pe:
	@echo "=== Simulating Processing Element ==="
	$(XVLOG) --sv $(RTL_PE) $(TB_DIR)/tb_processing_element.sv
	$(XELAB) tb_processing_element -s pe_sim
	$(XSIM) pe_sim -R

# Simulate Systolic Array
sim_array:
	@echo "=== Simulating Systolic Array ==="
	$(XVLOG) --sv $(RTL_ARRAY) $(TB_DIR)/tb_systolic_array.sv
	$(XELAB) tb_systolic_array -s array_sim
	$(XSIM) array_sim -R

# Simulate Core (with BRAMs and FSM)
sim_core:
	@echo "=== Simulating Core ==="
	$(XVLOG) --sv $(PKG_FILES) $(RTL_CORE) $(TB_DIR)/tb_matmul_core.sv
	$(XELAB) tb_matmul_core -s core_sim
	$(XSIM) core_sim -R

# Simulate Full System (AXI top)
sim_top:
	@echo "=== Simulating Full System ==="
	$(XVLOG) --sv $(PKG_FILES) $(RTL_TOP) $(TB_DIR)/tb_helpers_pkg.sv $(TB_DIR)/tb_matmul_top.sv
	$(XELAB) tb_matmul_top -s top_sim
	$(XSIM) top_sim -R

# Run Python verification
verify:
	@echo "=== Verifying results ==="
	python $(PYTHON_DIR)/verify_results.py --dim 4 --num-tests 5

# Clean
clean:
	@echo "=== Cleaning ==="
	rm -rf xsim.dir *.log *.jou *.pb *.wdb .Xil
	rm -rf $(TEST_DATA)/*.hex
