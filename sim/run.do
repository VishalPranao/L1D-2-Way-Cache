if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog -sv -f files.f
vsim -voptargs=+acc work.tb_l1d_cache
run -all
quit -f
