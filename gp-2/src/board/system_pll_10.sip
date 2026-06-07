set_global_assignment -entity "system_pll_10" -library "lib_system_pll_10" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "system_pll_10" -library "lib_system_pll_10" -name IP_TOOL_VERSION "18.1"
set_global_assignment -entity "system_pll_10" -library "lib_system_pll_10" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_system_pll_10" -name SPD_FILE [file join $::quartus(sip_path) "system_pll_10.spd"]

set_global_assignment -library "lib_system_pll_10" -name MISC_FILE [file join $::quartus(sip_path) "system_pll_10_sim/system_pll_10.vho"]
