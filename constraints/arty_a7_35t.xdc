## Arty A7-35T Constraints for Matrix Multiply Accelerator
## Target: xc7a35ticsg324-1L

## 100 MHz System Clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { S_AXI_ACLK }]
create_clock -add -name sys_clk -period 10.000 -waveform {0 5} [get_ports { S_AXI_ACLK }]

## Reset — Active-low, directly active-low button (active when pressed = low)
## Button BTN0
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { S_AXI_ARESETN }]

## Status LEDs (active-high)
## LED4 (LD4) — Green: IDLE
#set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led_idle }]
## LED5 (LD5) — Blue: BUSY
#set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led_busy }]
## LED6 (LD6) — Green: DONE
#set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led_done }]
## LED7 (LD7) — Red: ERROR
#set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led_error }]

## Interrupt output — PMOD JA Pin 1
#set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { irq }]

## Note: For AXI4-Lite integration via MicroBlaze block design,
## AXI signals are internal — no pin constraints needed.
## The constraints above are for standalone testing with debug LEDs.
## Uncomment LED/IRQ lines when adding a debug wrapper.
