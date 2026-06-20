# reg_reg works for xilinx FPGAs. For other devices, you need to check the netlist once.

# Multicycle path constraints for fpr_mul
# set_multicycle_path 2 -setup -to [get_cells -hierarchical fpr_mul_out_tdata_reg_reg*]
# set_multicycle_path 1 -hold -to [get_cells -hierarchical fpr_mul_out_tdata_reg_reg*]
# set_multicycle_path 2 -setup -to [get_cells -hierarchical fpr_mul_out_tvalid_reg_reg*]
# set_multicycle_path 1 -hold -to [get_cells -hierarchical fpr_mul_out_tvalid_reg_reg*]

# Multicycle path constraints for uint64_mul
# set_multicycle_path 2 -setup -to [get_cells -hierarchical uint64_mul_out_tdata_reg_reg*]
# set_multicycle_path 1 -hold -to [get_cells -hierarchical uint64_mul_out_tdata_reg_reg*]
# set_multicycle_path 2 -setup -to [get_cells -hierarchical uint64_mul_out_tvalid_reg_reg*]
# set_multicycle_path 1 -hold -to [get_cells -hierarchical uint64_mul_out_tvalid_reg_reg*]

# Multicycle path constraints for int64_mul
# set_multicycle_path 2 -setup -to [get_cells -hierarchical int64_mul_out_tdata_reg_reg*]
# set_multicycle_path 1 -hold -to [get_cells -hierarchical int64_mul_out_tdata_reg_reg*]
# set_multicycle_path 2 -setup -to [get_cells -hierarchical int64_mul_out_tvalid_reg_reg*]
# set_multicycle_path 1 -hold -to [get_cells -hierarchical int64_mul_out_tvalid_reg_reg*]

# Multicycle path constraints for fpr_add
#set_multicycle_path 2 -setup -to [get_cells -hierarchical fpr_add_out_tdata_reg_reg*]
#set_multicycle_path 1 -hold -to [get_cells -hierarchical fpr_add_out_tdata_reg_reg*]
#set_multicycle_path 2 -setup -to [get_cells -hierarchical fpr_add_out_tvalid_reg_reg*]
#set_multicycle_path 1 -hold -to [get_cells -hierarchical fpr_add_out_tvalid_reg_reg*]

# Multicycle path constraints for fpr_floor
#set_multicycle_path 2 -setup -to [get_cells -hierarchical fpr_floor_out_tdata_reg_reg*]
#set_multicycle_path 1 -hold -to [get_cells -hierarchical fpr_floor_out_tdata_reg_reg*]
#set_multicycle_path 2 -setup -to [get_cells -hierarchical fpr_floor_out_tvalid_reg_reg*]
#set_multicycle_path 1 -hold -to [get_cells -hierarchical fpr_floor_out_tvalid_reg_reg*]

# Multicycle path constraints for int2fpr
#set_multicycle_path 2 -setup -to [get_cells -hierarchical int2fpr_out_tdata_reg_reg*]
#set_multicycle_path 1 -hold -to [get_cells -hierarchical int2fpr_out_tdata_reg_reg*]
#set_multicycle_path 2 -setup -to [get_cells -hierarchical int2fpr_out_tvalid_reg_reg*]
#set_multicycle_path 1 -hold -to [get_cells -hierarchical int2fpr_out_tvalid_reg_reg*]
