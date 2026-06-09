transcript on

# Run from gp-2/ so prog_mem.vhd can resolve ./assembler/test.mif:
#   cd D:/Documents/GitHub_University/cs701/gp-2
#   do simulation/modelsim/tb_app.do

exec python assembler/asm.py test/app.asm -o assembler/test.mif

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

# ---- ReCOP core (with MMIO datapath) ----
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
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/BaseAdj.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/FindPeak.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/PkMem.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/SeqMax.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/SeqMin.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/ControlUnit.vhd}
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/asps/pd_asp/PeakDetector.vhd}

# ---- NI ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/src/ni/recop_ni.vhd}

# ---- Testbench ----
vcom -93 -work work {D:/Documents/GitHub_University/cs701/gp-2/test/tb_app.vhd}

# ---- Simulate ----
vsim -t 1ps work.tb_app
set NumericStdNoWarnings 1

add wave -divider "Board I/O"
add wave -radix hex /tb_app/io_sw
add wave -radix hex /tb_app/io_events
add wave -radix hex /tb_app/io_led
add wave -radix hex /tb_app/io_hex
add wave -radix hex /tb_app/period
add wave /tb_app/io_clear

add wave -divider "ReCOP"
add wave -radix hex /tb_app/pc_out
add wave -radix hex /tb_app/dpcr
add wave /tb_app/dpcr_load
add wave -radix hex /tb_app/sip

add wave -divider "NoC pipeline"
add wave -radix hex /tb_app/sends(0).data
add wave -radix hex /tb_app/sends(1).data
add wave -radix hex /tb_app/sends(2).data
add wave -radix hex /tb_app/sends(3).data
add wave -radix hex /tb_app/sends(4).data
add wave -radix hex /tb_app/recvs(0).data

run 55 ms
wave zoom full
