# Controlled Maze timing constraints.
# The supplied DE10_Standard_Audio.sdc is a Terasic template whose generated-clock
# paths do not exist in this design; derive_pll_clocks covers the 31.5 MHz PLL output.

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks
derive_clock_uncertainty

# KEY[0] is asynchronous and passes through reset_sync. The PS/2 lines are slow
# asynchronous inputs, filtered and sampled inside the supplied keyboard block.
set_false_path -from [get_ports {resetN_pin PS2_CLK PS2_DAT}]

# LEDs and seven-segment displays are slow visual indicators.
set_false_path -to [get_ports {LEDR[*] HEX*}]
