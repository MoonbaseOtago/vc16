read_sdc $::env(SCRIPTS_DIR)/base.sdc

set_input_delay 16 -clock [get_clocks $::env(CLOCK_PORT)] {uio_in[0]}
set_input_delay 16 -clock [get_clocks $::env(CLOCK_PORT)] {uio_in[1]}
set_input_delay 16 -clock [get_clocks $::env(CLOCK_PORT)] {uio_in[2]}
set_input_delay 16 -clock [get_clocks $::env(CLOCK_PORT)] {uio_in[3]}
