SIM          ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES        ?= 0

VERILOG_SOURCES  = $(abspath ../../rtl/dma/dma_engine.v)
TOPLEVEL         = dma_engine
MODULE           = test_dma

ifeq ($(WAVES),1)
EXTRA_ARGS += -fst
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
