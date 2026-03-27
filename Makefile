TOPLEVEL_LANG = verilog
SIM = verilator

VERILOG_SOURCES = $(PWD)/rtl/top.v
TOPLEVEL = top
COCOTB_TEST_MODULES = tb.test_smoke

EXTRA_ARGS += --trace --trace-fst --trace-structs

.PHONY: run
run: 
	$(MAKE) sim
	mv dump.fst waves/
	gtkwave waves/dump.fst
	

clean::
	rm -rf sim_build results.xml  waves/dump.fst

include $(shell cocotb-config --makefiles)/Makefile.sim

