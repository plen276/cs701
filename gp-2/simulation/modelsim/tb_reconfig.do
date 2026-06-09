transcript on

# Run from gp-2/:
#   cd D:/Documents/GitHub_University/cs701/gp-2
#   do simulation/modelsim/tb_reconfig.do

quit -sim

if {[file exists rtl_work]} {
    vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

# ---- NoC types (needed by reconfig_node) ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinTypes.vhd}

# ---- Reconfig node ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/reconfig_node.vhd}

# ---- Testbench ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/test/tb_reconfig.vhd}

# ---- Simulate ----
vsim -t 1ps work.tb_reconfig
set NumericStdNoWarnings 1

add wave -divider "Clock / Reset"
add wave /tb_reconfig/clock
add wave /tb_reconfig/reset

add wave -divider "recv (NoC input)"
add wave -radix hex /tb_reconfig/recv.data

add wave -divider "PM write port"
add wave /tb_reconfig/pm_wr_en
add wave -radix hex /tb_reconfig/pm_wr_addr
add wave -radix hex /tb_reconfig/pm_wr_data

add wave -divider "send (should stay zero)"
add wave -radix hex /tb_reconfig/send.data

run 2us
wave zoom full
