SIM          ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES        ?= 0

VERILOG_SOURCES  = $(abspath ../../rtl/uart/axi_uart.v)
TOPLEVEL         = axi_uart
MODULE           = test_uart

ifeq ($(WAVES),1)
EXTRA_ARGS += -fst
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
