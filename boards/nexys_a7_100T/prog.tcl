# Open the hardware manager and connect to the hardware server
open_hw_manager
connect_hw_server -allow_non_jtag

# Open the hardware target and select the device
open_hw_target
set device [get_hw_devices xc7a100t_0]
current_hw_device $device

# Refresh the hardware device and program the bitstream
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE {prebuilt/system.bit} $device
program_hw_devices $device

# Close the hardware target and disconnect from the hardware server
close_hw_target
disconnect_hw_server
close_hw_manager