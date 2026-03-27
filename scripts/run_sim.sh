#!/bin/bash

mkdir -p logs waves

verilator -Wall --cc rtl/top.v \
    --exe tb/test_smoke.py \
    --trace

make -C obj_dir -j -f Vtop.mk Vtop

./obj_dir/Vtop > logs/sim.log
