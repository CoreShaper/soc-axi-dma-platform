SIM          ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES        ?= 0

VERILOG_SOURCES  = $(abspath ../../rtl/ram/axi_ram.v)
TOPLEVEL         = axi_ram
MODULE           = test_axi_ram

ifeq ($(WAVES),1)
EXTRA_ARGS += -fst
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
