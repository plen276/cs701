transcript on

# Run from gp-2/ so prog_mem.vhd can resolve ./assembler/test.mif:
#   cd D:/Documents/GitHub_University/cs701/gp-2
#   do simulation/modelsim/tb_cor_pipeline.do
#
# Assembles cor_pipeline.asm before simulating.
# Topology: ReCOP(0) + ADC(1) + AVG(2) + COR(3); recvs(4) watched by TB.

exec python assembler/asm.py test/cor_pipeline.asm -o assembler/test.mif

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

# ---- ASPs ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/adc_asp.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/avg_asp.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/cor_asp/cor_asp_pkg.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/cor_asp/sample_mem.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/cor_asp/cor_asp_datapath.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/cor_asp/cor_asp_control.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/cor_asp/cor_asp.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/cor_asp_noc.vhd}

# ---- NI ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/ni/recop_ni.vhd}

# ---- Testbench ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/test/tb_cor_pipeline.vhd}

# ---- Simulate ----
vsim -t 1ps work.tb_cor_pipeline

add wave -divider "Clock / Reset"
add wave /tb_cor_pipeline/clock
add wave /tb_cor_pipeline/reset

add wave -divider "ReCOP debug"
add wave -radix hex /tb_cor_pipeline/pc_out
add wave -radix hex /tb_cor_pipeline/opcode_out
add wave -radix binary /tb_cor_pipeline/state_out

add wave -divider "NoC sends"
add wave -radix hex /tb_cor_pipeline/sends(0).data
add wave -radix hex /tb_cor_pipeline/sends(1).data
add wave -radix hex /tb_cor_pipeline/sends(2).data
add wave -radix hex /tb_cor_pipeline/sends(3).data

add wave -divider "NoC recvs"
add wave -radix hex /tb_cor_pipeline/recvs(1).data
add wave -radix hex /tb_cor_pipeline/recvs(2).data
add wave -radix hex /tb_cor_pipeline/recvs(3).data
add wave -radix hex /tb_cor_pipeline/recvs(4).data

run 600us
wave zoom full
