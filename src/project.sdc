read_sdc $::env(SCRIPTS_DIR)/base.sdc

set_input_delay 13 -clock [get_clocks $::env(CLOCK_PORT)] {uio_in}
