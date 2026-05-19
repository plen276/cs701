# Timing constraints for standalone ASP synthesis (Cyclone V).
# The entity port is 'clock' (AspAdc / AvgAsp) - reference it by that
# exact name. 20 ns = 50 MHz: this is the DE1-SoC CLOCK_50 board clock
# the design actually runs at. The Timing Analyzer still reports the
# achieved core Fmax (Fmax Summary) - read the margin from there.

create_clock -name clk -period 20.000 [get_ports clock]

# Tell the analyzer the design has no real I/O timing budget here
# (it's an internal NoC block, not a pin-level interface) so it
# reports the core Fmax rather than failing on unconstrained ports.
set_false_path -from [all_inputs]  -to [all_registers]
set_false_path -from [all_registers] -to [all_outputs]
