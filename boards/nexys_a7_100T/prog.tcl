open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set device [get_hw_devices xc7a100t_0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE {build/system.bit} $device
program_hw_devices $device
close_hw_target
disconnect_hw_server
close_hw_manager