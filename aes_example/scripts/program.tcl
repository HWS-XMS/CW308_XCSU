if {[llength $argv] < 1} {
    puts "PROGRAM_FAIL: no device image given"
    exit 1
}

set image [file normalize [lindex $argv 0]]

if {![file exists $image]} {
    puts "PROGRAM_FAIL: $image does not exist"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set devs [get_hw_devices]

if {[llength $devs] == 0} {
    puts "PROGRAM_FAIL: no device on the JTAG chain"
    exit 1
}

set dev [lindex $devs 0]

current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

puts "FOUND: $dev IDCODE=[get_property IDCODE $dev] PART=[get_property PART $dev]"

set_property PROGRAM.FILE $image $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "PROGRAM_OK"
close_hw_target
