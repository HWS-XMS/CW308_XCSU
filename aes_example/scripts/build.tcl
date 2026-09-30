set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize $script_dir/..]
set part       xcsu35p-sbvb625-2-e
set top        AES_TOP
set uart       $root/uart_sv/rtl
set aes        $root/aes/rtl

create_project -in_memory -part $part

read_verilog -sv $uart/UART_PKG.sv
read_verilog -sv $uart/UART_TX_IF.sv
read_verilog -sv $uart/UART_RX_IF.sv
read_verilog -sv $uart/UART_BAUD_GEN.sv
read_verilog -sv $uart/UART_MAJORITY.sv
read_verilog -sv $uart/UART_FIFO.sv
read_verilog -sv $uart/UART_TX.sv
read_verilog -sv $uart/UART_RX.sv
read_verilog -sv $uart/UART_CORE.sv

read_verilog -sv $aes/core/AES_PKG.sv

foreach f [lsort [glob $aes/core/*.sv]] {
    if {[file tail $f] ne "AES_PKG.sv"} {
        read_verilog -sv $f
    }
}

foreach f [lsort [glob $aes/keyschedule/*.sv]] {
    read_verilog -sv $f
}

read_verilog -sv $root/rtl/AES_TOP.sv

file copy -force $aes/keyschedule/RCON.mem [file join [pwd] RCON.mem]

read_xdc $root/CW308_XCSU.xdc

synth_design -top $top -part $part

write_checkpoint      -force post_synth.dcp
report_utilization    -file  post_synth_utilization.rpt
report_timing_summary -file  post_synth_timing.rpt

opt_design
place_design
phys_opt_design
route_design

write_checkpoint      -force post_route.dcp
report_utilization    -file  post_route_utilization.rpt
report_timing_summary -file  post_route_timing.rpt
report_drc            -file  post_route_drc.rpt

write_bitstream -force $top.bit

set bootgen [file join [file dirname [info nameofexecutable]] bootgen]

if {[catch {exec $bootgen -arch spartanuplus -image $top.bif -o $top.pdi -w on} out]} {
    puts "BOOTGEN_FAIL: $out"
    exit 1
}

puts "BUILD_OK image=$top.pdi wns=[get_property SLACK [get_timing_paths -delay_type max]]"
