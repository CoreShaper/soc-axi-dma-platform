SIM          ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES        ?= 0

VERILOG_SOURCES  = \
    $(abspath ../../rtl/cpu/cpu_core.v) \
    $(abspath ../../rtl/axi/axi_interconnect.v) \
    $(abspath ../../rtl/ram/axi_ram.v) \
    $(abspath ../../rtl/uart/axi_uart.v) \
    $(abspath ../../rtl/dma/dma_engine.v) \
    $(abspath ../../rtl/soc_top.v)

TOPLEVEL         = soc_top
MODULE           = test_soc_top

ifeq ($(WAVES),1)
EXTRA_ARGS += -fst
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
