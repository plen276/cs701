transcript on

# Run from gp-2/ so prog_mem_dp can resolve ./assembler/test.mif:
#   cd D:/Documents/GitHub_University/cs701/gp-2
#   do simulation/modelsim/tb_reconfig_demo.do

exec python assembler/asm.py test/reconfig_demo.asm -o assembler/test.mif

quit -sim

if {[file exists rtl_work]} {
    vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

# ---- ReCOP provided IP (packages first) ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/recop_types.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/various_constants.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/opcodes.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/ALU.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/regfile.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/data_mem.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/provided/prog_mem.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/prog_mem_dp.vhd}

# ---- ReCOP core ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/datapath.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/control_unit.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop.vhd}

# ---- NoC ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinTypes.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinFifo/TdmaMinFifo.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinInterface.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinSwitch.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinStage.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinSlots.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMinFabric.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/noc/TdmaMin.vhd}

# ---- Reconfig node + NI ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/recop/reconfig_node.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/ni/recop_ni.vhd}

# ---- Testbench ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/test/tb_reconfig_demo.vhd}

# ---- Simulate ----
vsim -t 1ps work.tb_reconfig_demo
set NumericStdNoWarnings 1

add wave -divider "Clock / Reset"
add wave /tb_reconfig_demo/clock
add wave /tb_reconfig_demo/reset

add wave -divider "ReCOP"
add wave -radix hex /tb_reconfig_demo/pc_out
add wave -radix hex /tb_reconfig_demo/io_hex
add wave -radix hex /tb_reconfig_demo/io_led
add wave /tb_reconfig_demo/io_events

add wave -divider "Reconfig PM write"
add wave /tb_reconfig_demo/pm_wr_en
add wave -radix hex /tb_reconfig_demo/pm_wr_addr
add wave -radix hex /tb_reconfig_demo/pm_wr_data

add wave -divider "NoC port 0 / 6"
add wave -radix hex /tb_reconfig_demo/sends(0).data
add wave -radix hex /tb_reconfig_demo/recvs(6).data

run 2 ms
wave zoom full
