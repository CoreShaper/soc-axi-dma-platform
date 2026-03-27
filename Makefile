TOPLEVEL_LANG = verilog
SIM = verilator

VERILOG_SOURCES = $(PWD)/rtl/top.v
TOPLEVEL = top
MODULE = test_smoke   # 或 toggle_test.py 文件名

WAVES = 1

include $(shell cocotb-config --makefiles)/Makefile.sim
